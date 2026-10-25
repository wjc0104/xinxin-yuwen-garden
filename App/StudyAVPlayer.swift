import Foundation
import AVFoundation

/// Keep explicit transport commands separate from delayed AVFoundation state notifications.
/// AVPlayerViewController remains the stock controller and shares this single player.
final class StudyAVPlayer: AVPlayer {
    private let transportLock = NSRecursiveLock()
    private var wantsPlayback = false
    private var selectedRate: Float = 1
    private var applyingCommand = false
    private var commandRevision = UUID()
    private var preservingBindingSeek = false
    private var rateObservation: NSKeyValueObservation?
    private var controlObservation: NSKeyValueObservation?
    var traceTransport = false
    private lazy var tracePlayer = PlayerTransportTrace.shared.allocatePlayer()
    private weak var traceItem: AVPlayerItem?
    private var traceItemVersion = 0

    var isExplicitlyPaused: Bool {
        transportLock.lock(); defer { transportLock.unlock() }
        return !wantsPlayback && super.rate == 0 && timeControlStatus == .paused
    }
    var intentRevision: UUID {
        transportLock.lock(); defer { transportLock.unlock() }
        return commandRevision
    }
    func nativeSeekWillStart() {
        transportLock.lock(); defer { transportLock.unlock() }
        if !preservingBindingSeek { commandRevision = UUID() }
    }
    func seekPreservingPausedBinding(to time: CMTime, completionHandler: @escaping (Bool) -> Void) {
        transportLock.lock(); defer { transportLock.unlock() }
        let previous = preservingBindingSeek
        preservingBindingSeek = true
        defer { preservingBindingSeek = previous }
        // Exclude this owner seek and synchronous item forwarding from later native user intent.
        super.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: completionHandler)
    }
    override func seek(to time: CMTime) {
        nativeSeekWillStart(); super.seek(to: time)
    }
    override func seek(to time: CMTime, completionHandler: @escaping (Bool) -> Void) {
        nativeSeekWillStart(); super.seek(to: time, completionHandler: completionHandler)
    }
    override func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) {
        nativeSeekWillStart(); super.seek(to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter)
    }
    override func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime, completionHandler: @escaping (Bool) -> Void) {
        nativeSeekWillStart(); super.seek(to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter, completionHandler: completionHandler)
    }
    override func seek(to date: Date) {
        nativeSeekWillStart(); super.seek(to: date)
    }
    override func seek(to date: Date, completionHandler: @escaping (Bool) -> Void) {
        nativeSeekWillStart(); super.seek(to: date, completionHandler: completionHandler)
    }

    func configureRate(_ rate: Float, useSystemDefaultRate: Bool = true) {
        transportLock.lock(); defer { transportLock.unlock() }
        trace(.configureBefore, requestedRate: rate)
        selectedRate = rate
        if useSystemDefaultRate {
            if #available(iOS 16.0, *) { defaultRate = rate }
        }
        if rateObservation == nil {
            rateObservation = observe(\.rate, options: [.new]) { [weak self] _, _ in self?.reconcileTransport() }
            controlObservation = observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in self?.reconcileTransport() }
        }
        if wantsPlayback { applyRate(rate) }
        trace(.configureAfter, requestedRate: rate)
    }
    override func play() {
        transportLock.lock(); defer { transportLock.unlock() }
        if applyingCommand { super.play(); return }
        commandRevision = UUID()
        trace(.playBefore)
        wantsPlayback = true
        applyRate(selectedRate)
        trace(.playAfter)
    }
    override func pause() {
        transportLock.lock(); defer { transportLock.unlock() }
        if applyingCommand { super.pause(); return }
        commandRevision = UUID()
        trace(.pauseBefore)
        wantsPlayback = false
        applyRate(0)
        trace(.pauseAfter)
    }
    override var rate: Float {
        get { super.rate }
        set {
            transportLock.lock(); defer { transportLock.unlock() }
            if applyingCommand { super.rate = newValue; return }
            commandRevision = UUID()
            trace(.setRateBefore, requestedRate: newValue)
            wantsPlayback = newValue > 0
            applyRate(wantsPlayback ? selectedRate : 0)
            trace(.setRateAfter, requestedRate: newValue)
        }
    }
    override func playImmediately(atRate rate: Float) {
        transportLock.lock(); defer { transportLock.unlock() }
        if applyingCommand { super.playImmediately(atRate: rate); return }
        commandRevision = UUID()
        trace(.playImmediatelyBefore, requestedRate: rate)
        wantsPlayback = rate > 0
        applyRate(wantsPlayback ? selectedRate : 0)
        trace(.playImmediatelyAfter, requestedRate: rate)
    }
    override func setRate(_ rate: Float, time itemTime: CMTime, atHostTime hostClockTime: CMTime) {
        transportLock.lock(); defer { transportLock.unlock() }
        if !applyingCommand { commandRevision = UUID() }
        super.setRate(rate, time: itemTime, atHostTime: hostClockTime)
    }
    private func applyRate(_ rate: Float) {
        let previous = applyingCommand
        applyingCommand = true
        defer { applyingCommand = previous }
        trace(.applyBefore, requestedRate: rate)
        if rate > 0 { super.playImmediately(atRate: rate) } else { super.pause() }
        trace(.applyAfter, requestedRate: rate)
    }
    private func reconcileTransport() {
        transportLock.lock(); defer { transportLock.unlock() }
        trace(.observedState)
        guard !applyingCommand else { return }
        if !wantsPlayback && (super.rate != 0 || timeControlStatus != .paused) {
            trace(.repairPaused)
            applyRate(0)
        } else if wantsPlayback && super.rate > 0 && super.rate != selectedRate {
            trace(.repairRate)
            applyRate(selectedRate)
        }
    }
    func trace(_ event: PlayerTransportEvent, requestedRate: Float? = nil, publishedSeconds: Int? = nil, publishedPlaying: Bool? = nil, ready: Bool? = nil, pendingSeek: Bool? = nil, targetSeconds: Double? = nil, seekSucceeded: Bool? = nil) {
        guard traceTransport else { return }
        transportLock.lock(); defer { transportLock.unlock() }
        if event != .clockSample {
            print("NATIVE_COMMAND time=\(ProcessInfo.processInfo.systemUptime) action=\(event.rawValue) wants=\(wantsPlayback) actual=\(super.rate) control=\(timeControlStatus.rawValue) selected=\(selectedRate)")
        }
        guard PlayerTransportTrace.shared.enabled else { return }
        if traceItem !== currentItem { traceItem = currentItem; traceItemVersion += 1 }
        let position = currentTime().seconds
        let actualRate = super.rate
        var state: [String: Any] = ["player": tracePlayer, "item": traceItemVersion,
            "position": position.isFinite ? position : -1, "rate": actualRate.isFinite ? actualRate : -1,
            "control": timeControlStatus.rawValue, "selected": selectedRate.isFinite ? selectedRate : -1,
            "wants": wantsPlayback, "applying": applyingCommand,
            "itemStatus": currentItem?.status.rawValue ?? -1]
        if let requestedRate = requestedRate { state["requested"] = requestedRate.isFinite ? requestedRate : -1 }
        if let publishedSeconds = publishedSeconds { state["publishedSeconds"] = publishedSeconds }
        if let publishedPlaying = publishedPlaying { state["publishedPlaying"] = publishedPlaying }
        if let ready = ready { state["ready"] = ready }
        if let pendingSeek = pendingSeek { state["pendingSeek"] = pendingSeek }
        if let targetSeconds = targetSeconds { state["targetSeconds"] = targetSeconds.isFinite ? targetSeconds : -1 }
        if let seekSucceeded = seekSucceeded { state["seekSucceeded"] = seekSucceeded }
        PlayerTransportTrace.shared.record(event, state: state)
    }
}

/// Stock controls can seek the current item directly instead of calling AVPlayer.seek.
final class StudyAVPlayerItem: AVPlayerItem {
    weak var studyPlayer: StudyAVPlayer?
    override func seek(to time: CMTime, completionHandler: ((Bool) -> Void)? = nil) {
        studyPlayer?.nativeSeekWillStart()
        super.seek(to: time, completionHandler: completionHandler)
    }
    override func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime, completionHandler: ((Bool) -> Void)? = nil) {
        studyPlayer?.nativeSeekWillStart()
        super.seek(to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter, completionHandler: completionHandler)
    }
    override func seek(to date: Date, completionHandler: ((Bool) -> Void)? = nil) -> Bool {
        studyPlayer?.nativeSeekWillStart()
        return super.seek(to: date, completionHandler: completionHandler)
    }
    override func cancelPendingSeeks() {
        studyPlayer?.nativeSeekWillStart()
        super.cancelPendingSeeks()
    }
}
