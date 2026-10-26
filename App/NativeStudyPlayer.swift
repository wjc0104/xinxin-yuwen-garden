import Foundation
import Combine
import AVFoundation
import AVKit
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
    private struct FullScreenRestoration {
        let presentation: UUID
        let generation: UUID
        let player: StudyAVPlayer
        let item: AVPlayerItem
        let position: CMTime
        let intentRevision: UUID
    }
    private struct IssuedRestoration {
        let presentation: UUID
        let seek: UUID
        let player: StudyAVPlayer
        let item: AVPlayerItem
        let intentRevision: UUID
    }
    @Published private(set) var player: AVPlayer?
    @Published private(set) var loading = false
    @Published private(set) var ready = false
    @Published private(set) var problem: String?
    @Published private(set) var height: Int?
    @Published private(set) var seconds: Int?
    @Published private(set) var playing = false
    @Published private(set) var originalURL: URL?
    @Published private(set) var playbackRate: Float = 1
    var traceTransport = ProcessInfo.processInfo.arguments.contains("--trace-player-transport")
    var useSystemDefaultRate = !ProcessInfo.processInfo.arguments.contains("--legacy-player-transport")
    static let playbackRates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]
    private var identity: String?
    private var generation = UUID()
    private var lastPosition: Int?
    @Published private(set) var pendingSeek: UUID?
    private var fullScreenRestoration: FullScreenRestoration?
    private var issuedRestoration: IssuedRestoration?
    private var restorationWatchdog: Task<Void, Never>?
    var waitingForFullScreenRestoration: Bool {
        guard let ticket = fullScreenRestoration else { return false }
        return generation == ticket.generation && player === ticket.player &&
            ticket.player.currentItem === ticket.item && ticket.player.intentRevision == ticket.intentRevision
    }
    private var statusObserver: NSKeyValueObservation?
    private var playbackObserver: NSKeyValueObservation?
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
            let item = StudyAVPlayerItem(asset: asset)
            let value = StudyAVPlayer(playerItem: item)
            item.studyPlayer = value
            value.traceTransport = traceTransport
            value.configureRate(playbackRate, useSystemDefaultRate: useSystemDefaultRate)
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
                    guard let self = self, self.generation == token, self.ready, self.pendingSeek == nil,
                          !self.waitingForFullScreenRestoration, value?.currentItem?.status == .readyToPlay,
                          let elapsed = value?.currentTime().seconds, elapsed.isFinite, elapsed >= 0, elapsed <= 86400 else { return }
                    // Read now: an enqueued pre-seek callback must not restore its stale zero sample.
                    let next = Int(elapsed)
                    self.lastPosition = next
                    if self.seconds != next { self.seconds = next }
                    self.traceTransportState(.clockSample)
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
        cancelFullScreenRestoration()
        cancelIssuedRestoration()
        pendingSeek = nil
        loadWatchdog?.cancel(); loadWatchdog = nil
        if let error = item.error as NSError? { print("NATIVE_PLAYER_ERROR \(error.domain) \(error.code)") }
        player?.pause()
        ready = false; loading = false; playing = false
        problem = "系统播放器暂时无法连接视频源，请重试。"
    }
    func playPause() { guard ready, let player = player else { return }; cancelFullScreenRestoration(); cancelIssuedRestoration(); traceTransportState(.appToggle); if player.timeControlStatus != .paused { player.pause() } else { player.play() } }
    func setPlaybackRate(_ rate: Float) {
        guard Self.playbackRates.contains(rate) else { return }
        playbackRate = rate
        (player as? StudyAVPlayer)?.configureRate(rate, useSystemDefaultRate: useSystemDefaultRate)
    }
    func traceTransportState(_ command: String) {
        if traceTransport { print("NATIVE_TRANSPORT time=\(ProcessInfo.processInfo.systemUptime) command=\(command) rate=\(player?.rate ?? -1) control=\(player?.timeControlStatus.rawValue ?? -1)") }
        traceTransportState(.checkpoint)
    }
    func traceTransportState(_ event: PlayerTransportEvent) {
        (player as? StudyAVPlayer)?.trace(event, publishedSeconds: seconds, publishedPlaying: playing, ready: ready, pendingSeek: pendingSeek != nil)
    }
    func pause() { cancelFullScreenRestoration(); cancelIssuedRestoration(); player?.pause() }
    func currentSeconds() -> Int? {
        if ready, pendingSeek == nil, !waitingForFullScreenRestoration,
           player?.currentItem?.status == .readyToPlay, let value = player?.currentTime().seconds, value.isFinite, value >= 0, value <= 86400 {
            lastPosition = Int(value)
        }
        return lastPosition
    }
    func bindFullScreenPlayer(to controller: AVPlayerViewController, presentation: UUID) {
        cancelFullScreenRestoration()
        cancelIssuedRestoration()
        guard let player = player else { return }
        let item = player.currentItem, position = player.currentTime(), token = generation
        let native = player as? StudyAVPlayer
        let intentRevision = native?.intentRevision
        let paused = ready && pendingSeek == nil && item?.status == .readyToPlay &&
            native?.isExplicitlyPaused == true &&
            position.isValid && position.seconds.isFinite && (0...86400).contains(position.seconds)
        (player as? StudyAVPlayer)?.trace(.fullscreenAttachedBefore)
        controller.player = player
        (player as? StudyAVPlayer)?.trace(.fullscreenAttachedAfter)
        // AVKit can retime a paused item during this assignment; preserve its exact fractional position.
        guard paused, generation == token, self.player === player, player.currentItem === item,
              ready, pendingSeek == nil, item?.status == .readyToPlay,
              native?.isExplicitlyPaused == true, native?.intentRevision == intentRevision,
              CMTimeCompare(player.currentTime(), position) != 0,
              let native = native, let item = item, let intentRevision = intentRevision else { return }
        lastPosition = Int(position.seconds); seconds = Int(position.seconds)
        fullScreenRestoration = FullScreenRestoration(presentation: presentation, generation: token,
            player: native, item: item, position: position, intentRevision: intentRevision)
        native.trace(.fullscreenRestoreWaiting, pendingSeek: true, targetSeconds: position.seconds)
        restorationWatchdog = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
            guard let self = self, self.fullScreenRestoration?.presentation == presentation else { return }
            if !self.waitingForFullScreenRestoration { self.cancelFullScreenRestoration(presentation: presentation); return }
            self.cancelFullScreenRestoration(presentation: presentation)
            native.trace(.fullscreenRestoreTimedOut, targetSeconds: position.seconds)
            self.problem = "全屏画面未就绪，请退出后重试。"
        }
    }
    func fullScreenMounted(_ presentation: UUID, displayReady: Bool) {
        guard let ticket = fullScreenRestoration, ticket.presentation == presentation else { return }
        if !waitingForFullScreenRestoration || !ready || pendingSeek != nil ||
            ticket.item.status != .readyToPlay || !ticket.player.isExplicitlyPaused ||
            CMTimeCompare(ticket.player.currentTime(), ticket.position) == 0 {
            cancelFullScreenRestoration(presentation: presentation)
            return
        }
        guard displayReady else { return }
        fullScreenRestoration = nil
        restorationWatchdog?.cancel(); restorationWatchdog = nil
        seek(to: ticket.position, preservingPausedBinding: true, presentation: presentation)
    }
    func cancelFullScreenRestoration(presentation: UUID? = nil) {
        guard let ticket = fullScreenRestoration,
              presentation == nil || ticket.presentation == presentation else { return }
        fullScreenRestoration = nil
        restorationWatchdog?.cancel(); restorationWatchdog = nil
        ticket.player.trace(.fullscreenRestoreCancelled, targetSeconds: ticket.position.seconds)
    }
    func endFullScreenPresentation(_ presentation: UUID) {
        cancelFullScreenRestoration(presentation: presentation)
        cancelIssuedRestoration(presentation: presentation)
    }
    private func cancelIssuedRestoration(presentation: UUID? = nil) {
        guard let issued = issuedRestoration,
              presentation == nil || issued.presentation == presentation else { return }
        issuedRestoration = nil
        if pendingSeek == issued.seek { pendingSeek = nil }
        // Only cancel this seek while it is still the latest native intent.
        if player === issued.player, issued.player.currentItem === issued.item,
           issued.player.intentRevision == issued.intentRevision {
            issued.item.cancelPendingSeeks()
        }
    }
    func seek(_ seconds: Int) {
        guard ready, let player = player, seconds >= 0 else { return }
        let duration = player.currentItem?.duration.seconds ?? .nan
        let target = duration.isFinite ? min(Double(seconds), max(0, duration - 0.1)) : Double(seconds)
        seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }
    func seek(to target: CMTime, preservingPausedBinding: Bool = false, presentation: UUID? = nil) {
        if !preservingPausedBinding { cancelFullScreenRestoration(); cancelIssuedRestoration() }
        guard ready, let player = player, let item = player.currentItem else { return }
        let token = generation, seekToken = UUID()
        let nativeRevision = (player as? StudyAVPlayer)?.intentRevision
        pendingSeek = seekToken
        if preservingPausedBinding, let presentation = presentation, let native = player as? StudyAVPlayer {
            issuedRestoration = IssuedRestoration(presentation: presentation, seek: seekToken,
                player: native, item: item, intentRevision: native.intentRevision)
        }
        if preservingPausedBinding { (player as? StudyAVPlayer)?.trace(.fullscreenRestoreBefore, pendingSeek: true, targetSeconds: target.seconds) }
        let completion: (Bool) -> Void = { [weak self, weak player, weak item] success in
            Task { @MainActor [weak self] in
                guard let self = self, self.generation == token, self.player === player,
                      let item = item, player?.currentItem === item, self.pendingSeek == seekToken else { return }
                if let presentation = presentation {
                    guard self.issuedRestoration?.presentation == presentation,
                          self.issuedRestoration?.seek == seekToken else { return }
                    self.issuedRestoration = nil
                }
                self.pendingSeek = nil
                if preservingPausedBinding {
                    (player as? StudyAVPlayer)?.trace(.fullscreenRestoreCompleted, pendingSeek: false, targetSeconds: target.seconds, seekSucceeded: success)
                    // Later native seeks/transport win even if they end paused again before this callback.
                    guard (player as? StudyAVPlayer)?.intentRevision == nativeRevision,
                          (player as? StudyAVPlayer)?.isExplicitlyPaused == true else { return }
                }
                if success {
                    self.lastPosition = Int(target.seconds); self.seconds = Int(target.seconds)
                } else {
                    // A failed restoration must not silently replace the saved position with zero.
                    self.ready = false; player?.pause(); self.playing = false
                    self.problem = "没有恢复到上次时间点，请重试。"
                }
            }
        }
        if preservingPausedBinding, let player = player as? StudyAVPlayer {
            player.seekPreservingPausedBinding(to: target, completionHandler: completion)
        } else {
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: completion)
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
        if stage == "playurl", let body = payload?["data"] as? [String: Any] {
            let segments = body["durl"] as? [[String: Any]]
            let media = (segments?.first?["url"] as? String).flatMap { URL(string: $0) }
            print("NATIVE_SOURCE_SHAPE mp4=\((body["format"] as? String)?.hasPrefix("mp4") == true) preview=\((body["is_preview"] as? Bool) == true) durl_count=\(segments?.count ?? -1) dash=\(body["dash"] != nil) scheme=\(media?.scheme ?? "none") host=\(media?.host ?? "none")")
        }
        guard response.statusCode == 200 else {
            throw GardenError.invalid("原站请求失败（HTTP \(response.statusCode)），请稍后重试。")
        }
        return data
    }
    private func clearPlayer() {
        cancelFullScreenRestoration()
        cancelIssuedRestoration()
        loadWatchdog?.cancel(); loadWatchdog = nil
        player?.pause()
        pendingSeek = nil
        clock = nil; statusObserver = nil; playbackObserver = nil; player = nil; playing = false
    }
}
