import Foundation
import Combine
import AVFoundation
import GardenCore

private final class PlayerClock {
    private let player: AVPlayer
    private let token: Any
    init(_ player: AVPlayer, handler: @escaping (CMTime) -> Void) {
        self.player = player
        token = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main, using: handler)
    }
    deinit { player.removeTimeObserver(token) }
}

@MainActor final class NativeStudyPlayer: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var loading = false
    @Published private(set) var ready = false
    @Published private(set) var problem: String?
    @Published private(set) var height: Int?
    @Published private(set) var seconds: Int?
    @Published private(set) var playing = false
    private var identity: String?
    private var generation = UUID()
    private var statusObserver: NSKeyValueObservation?
    private var playbackObserver: NSKeyValueObservation?
    private var clock: PlayerClock?
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()
    var lowQuality: Bool { height.map { $0 < 720 } ?? false }
    var qualityLabel: String { height.map { "\($0)P · 系统播放器" } ?? "系统播放器" }

    func load(_ resource: StudyResource, localURL: URL? = nil, at initial: Int? = nil, force: Bool = false) async {
        if !force, identity == resource.id, player != nil, problem == nil { return }
        let token = UUID(); generation = token
        identity = resource.id; ready = false; loading = true; problem = nil; height = nil; seconds = nil
        clearPlayer()
        do {
            let url: URL
            var options: [String: Any] = [:]
            if resource.kind == .localVideo {
                guard let localURL = localURL else { throw GardenError.invalid("本地视频文件暂时无法读取。") }
                url = localURL
            } else {
                let reference = try BilibiliPlayback.reference(resource.url)
                let cid = try BilibiliPlayback.contentID(try await data(reference.metadataURL), page: reference.page)
                let source = try BilibiliPlayback.source(try await data(reference.playbackURL(cid: cid)))
                url = source.url
                guard generation == token, !Task.isCancelled else { return }
                height = source.offeredHeight
                // Origin CDN requires its normal Referer. No cookies, login credentials or quality unlocking.
                options["AVURLAssetHTTPHeaderFieldsKey"] = ["Referer":"https://www.bilibili.com/", "User-Agent":"Mozilla/5.0"]
            }
            guard generation == token, !Task.isCancelled else { return }
            let asset = AVURLAsset(url: url, options: options)
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            let item = AVPlayerItem(asset: asset)
            let value = AVPlayer(playerItem: item)
            value.automaticallyWaitsToMinimizeStalling = true
            player = value
            statusObserver = item.observe(\.status, options: [.initial,.new]) { [weak self] item, _ in
                Task { @MainActor [weak self] in
                    guard let self = self, self.generation == token else { return }
                    if item.status == .readyToPlay {
                        self.ready = true; self.loading = false
                        if let track = item.asset.tracks(withMediaType: .video).first {
                            let size = track.naturalSize.applying(track.preferredTransform)
                            let actual = Int(min(abs(size.width), abs(size.height)))
                            if actual > 0 { self.height = actual }
                        }
                        if let initial = initial, initial > 0 { self.seek(initial) }
                    } else if item.status == .failed {
                        if let error = item.error as NSError? { print("NATIVE_PLAYER_ERROR \(error.domain) \(error.code)") }
                        self.ready = false; self.loading = false
                        self.problem = "系统播放器暂时无法连接视频源，请重试。"
                    }
                }
            }
            playbackObserver = value.observe(\.timeControlStatus, options: [.initial,.new]) { [weak self] value, _ in
                Task { @MainActor [weak self] in guard let self = self, self.generation == token else { return }; self.playing = value.timeControlStatus == .playing }
            }
            clock = PlayerClock(value) { [weak self] time in
                Task { @MainActor [weak self] in
                    guard let self = self, self.generation == token, time.seconds.isFinite, time.seconds >= 0, time.seconds <= 86400 else { return }
                    let next = Int(time.seconds)
                    if self.seconds != next { self.seconds = next }
                }
            }
        } catch {
            guard generation == token, !Task.isCancelled else { return }
            loading = false; ready = false
            let diagnostic = error as NSError
            print("NATIVE_SOURCE_ERROR \(diagnostic.domain) \(diagnostic.code)")
            problem = (error as? GardenError)?.localizedDescription ?? "没有取得可播放的视频源，请联网后重试。"
        }
    }
    func playPause() { guard ready, let player = player else { return }; if player.timeControlStatus == .playing { player.pause() } else { player.play() } }
    func pause() { player?.pause() }
    func currentSeconds() -> Int? {
        guard ready, let value = player?.currentTime().seconds, value.isFinite, value >= 0, value <= 86400 else { return nil }
        return Int(value)
    }
    func seek(_ seconds: Int) {
        guard ready, let player = player, seconds >= 0 else { return }
        let duration = player.currentItem?.duration.seconds ?? .nan
        let target = duration.isFinite ? min(Double(seconds), max(0, duration - 0.1)) : Double(seconds)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    private func data(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        let (data,response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= 4*1024*1024 else { throw GardenError.invalid("原站暂时没有返回视频信息。") }
        return data
    }
    private func clearPlayer() {
        player?.pause()
        clock = nil; statusObserver = nil; playbackObserver = nil; player = nil; playing = false
    }
}
