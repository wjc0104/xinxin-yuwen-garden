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

/// KVO may arrive off the main actor; newer play/pause events supersede queued rate corrections.
private final class PlayerRateEvents {
    private let lock = NSLock()
    private var revision: UInt64 = 0
    func record() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        revision &+= 1
        return revision
    }
    func isLatest(_ event: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return event == revision
    }
}

@MainActor final class NativeStudyPlayer: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var loading = false
    @Published private(set) var ready = false
    @Published private(set) var problem: String?
    @Published private(set) var height: Int?
    @Published private(set) var seconds: Int?
    @Published private(set) var playing = false
    @Published private(set) var originalURL: URL?
    @Published private(set) var playbackRate: Float = 1
    static let playbackRates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]
    private var identity: String?
    private var generation = UUID()
    private var lastPosition: Int?
    private var pendingSeek: UUID?
    private var statusObserver: NSKeyValueObservation?
    private var playbackObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var clock: PlayerClock?
    private var loadWatchdog: Task<Void, Never>?
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()
    var lowQuality: Bool { height.map { $0 < 720 } ?? false }
    var qualityLabel: String { height.map { "\($0)P · 系统播放器" } ?? "系统播放器" }
    var playbackRateLabel: String { Self.rateLabel(playbackRate) }
    static func rateLabel(_ rate: Float) -> String { String(format: "%g", Double(rate)) }

    func load(_ resource: StudyResource, localURL: URL? = nil, at initial: Int? = nil, force: Bool = false) async {
        if !force, identity == resource.id, player != nil, problem == nil { return }
        // Capture before replacing a failed item. Readiness may already be false.
        let resume = identity == resource.id ? (currentSeconds() ?? initial) : initial
        if identity != resource.id { lastPosition = nil }
        if let resume = resume, (0...86400).contains(resume) { lastPosition = resume }
        let token = UUID(); generation = token
        identity = resource.id; ready = false; loading = true; problem = nil; height = nil; seconds = nil; originalURL = nil
        clearPlayer()
        do {
            let url: URL
            var options: [String: Any] = [:]
            if resource.kind == .localVideo {
                guard let localURL = localURL else { throw GardenError.invalid("本地视频文件暂时无法读取。") }
                url = localURL
            } else {
                let reference = try BilibiliPlayback.reference(resource.url)
                let parts = try BilibiliPlayback.parts(try await data(reference.partListURL))
                let part = try BilibiliPlayback.resolve(parts, reference: reference, knownCID: resource.videoCID)
                guard generation == token, !Task.isCancelled else { return }
                originalURL = URL(string: "https://www.bilibili.com/video/\(reference.bvid)/?p=\(part.page)")
                let source = try BilibiliPlayback.source(try await data(reference.playbackURL(cid: part.cid)))
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
                        self.loadWatchdog?.cancel(); self.loadWatchdog = nil
                        self.ready = true; self.loading = false
                        if let track = item.asset.tracks(withMediaType: .video).first {
                            let size = track.naturalSize.applying(track.preferredTransform)
                            let actual = Int(min(abs(size.width), abs(size.height)))
                            if actual > 0 { self.height = actual }
                        }
                        if let resume = resume, resume > 0 { self.seek(resume) }
                    } else if item.status == .failed {
                        self.playbackFailed(item)
                    }
                }
            }
            playbackObserver = value.observe(\.timeControlStatus, options: [.initial,.new]) { [weak self] value, _ in
                Task { @MainActor [weak self] in guard let self = self, self.generation == token else { return }; self.playing = value.timeControlStatus != .paused }
            }
            // iOS 15 system controls can resume using play(), which resets rate to 1.
            // Retain event identity: an old positive event cannot override a newer pause.
            let rateEvents = PlayerRateEvents()
            rateObserver = value.observe(\.rate, options: [.new]) { [weak self] value, change in
                let event = rateEvents.record()
                guard let observedRate = change.newValue, observedRate > 0 else { return }
                Task { @MainActor [weak self] in
                    guard let self = self, self.generation == token, self.player === value,
                          rateEvents.isLatest(event), value.timeControlStatus != .paused,
                          value.rate == observedRate, value.rate != self.playbackRate else { return }
                    value.rate = self.playbackRate
                }
            }
            loadWatchdog = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 25_000_000_000) } catch { return }
                guard let self = self, self.generation == token, !self.ready else { return }
                self.generation = UUID()
                self.clearPlayer()
                self.loading = false
                self.problem = "视频连接超时，请重试。"
            }
            clock = PlayerClock(value) { [weak self, weak value] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, self.generation == token, self.ready, self.pendingSeek == nil, value?.currentItem?.status == .readyToPlay,
                          let elapsed = value?.currentTime().seconds, elapsed.isFinite, elapsed >= 0, elapsed <= 86400 else { return }
                    // Read now: an enqueued pre-seek callback must not restore its stale zero sample.
                    let next = Int(elapsed)
                    self.lastPosition = next
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
    // Shared failure path; stale item callbacks cannot overwrite the current resource.
    func playbackFailed(_ item: AVPlayerItem) {
        guard player?.currentItem === item else { return }
        _ = currentSeconds()
        pendingSeek = nil
        loadWatchdog?.cancel(); loadWatchdog = nil
        if let error = item.error as NSError? { print("NATIVE_PLAYER_ERROR \(error.domain) \(error.code)") }
        player?.pause()
        ready = false; loading = false; playing = false
        problem = "系统播放器暂时无法连接视频源，请重试。"
    }
    func playPause() { guard ready, let player = player else { return }; if player.timeControlStatus != .paused { player.pause() } else { player.rate = playbackRate } }
    func setPlaybackRate(_ rate: Float) {
        guard Self.playbackRates.contains(rate) else { return }
        playbackRate = rate
        // A speed selection is not a request to play. Preserve a paused player's zero rate.
        if let player = player, player.timeControlStatus != .paused, player.rate > 0 { player.rate = rate }
    }
    func pause() { player?.pause() }
    func currentSeconds() -> Int? {
        if ready, pendingSeek == nil, player?.currentItem?.status == .readyToPlay, let value = player?.currentTime().seconds, value.isFinite, value >= 0, value <= 86400 {
            lastPosition = Int(value)
        }
        return lastPosition
    }
    func seek(_ seconds: Int) {
        guard ready, let player = player, seconds >= 0 else { return }
        let duration = player.currentItem?.duration.seconds ?? .nan
        let target = duration.isFinite ? min(Double(seconds), max(0, duration - 0.1)) : Double(seconds)
        let token = generation, seekToken = UUID()
        pendingSeek = seekToken
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak player] success in
            Task { @MainActor [weak self] in
                guard let self = self, self.generation == token, self.player === player,
                      self.pendingSeek == seekToken else { return }
                self.pendingSeek = nil
                if success {
                    self.lastPosition = Int(target); self.seconds = Int(target)
                } else {
                    // A failed restoration must not silently replace the saved position with zero.
                    self.ready = false; player?.pause(); self.playing = false
                    self.problem = "没有恢复到上次时间点，请重试。"
                }
            }
        }
    }
    private func data(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        let stage = url.path.hasSuffix("pagelist") ? "parts" : "playurl"
        let result: (Data, URLResponse)
        do { result = try await session.data(for: request) }
        catch {
            let error = error as NSError
            print("NATIVE_SOURCE stage=\(stage) path=\(url.path) http=none error_domain=\(error.domain) error_code=\(error.code)")
            throw error
        }
        let (data, response) = result
        guard let response = response as? HTTPURLResponse else { throw GardenError.invalid("原站暂时没有返回视频信息。") }
        guard data.count <= 4*1024*1024 else { throw GardenError.invalid("原站视频信息过大。") }
        // Log only the API path and numeric status, never signed media URLs or response bodies.
        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let code = (payload?["code"] as? NSNumber)?.stringValue ?? "missing"
        let quality = ((payload?["data"] as? [String: Any])?["quality"] as? NSNumber)?.stringValue ?? "none"
        print("NATIVE_SOURCE stage=\(stage) path=\(url.path) http=\(response.statusCode) code=\(code) quality=\(quality)")
        guard response.statusCode == 200 else {
            throw GardenError.invalid("原站请求失败（HTTP \(response.statusCode)），请稍后重试。")
        }
        return data
    }
    private func clearPlayer() {
        loadWatchdog?.cancel(); loadWatchdog = nil
        player?.pause()
        pendingSeek = nil
        clock = nil; statusObserver = nil; playbackObserver = nil; rateObserver = nil; player = nil; playing = false
    }
}
