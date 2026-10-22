import Foundation
import AVFoundation

/// Keep explicit transport commands separate from delayed AVFoundation state notifications.
/// AVPlayerViewController remains the stock controller and shares this single player.
final class StudyAVPlayer: AVPlayer {
    private let transportLock = NSRecursiveLock()
    private var wantsPlayback = false
    private var selectedRate: Float = 1
    private var applyingCommand = false
    private var rateObservation: NSKeyValueObservation?
    private var controlObservation: NSKeyValueObservation?
    var traceTransport = false

    func configureRate(_ rate: Float, useSystemDefaultRate: Bool = true) {
        transportLock.lock(); defer { transportLock.unlock() }
        selectedRate = rate
        if useSystemDefaultRate {
            if #available(iOS 16.0, *) { defaultRate = rate }
        }
        if rateObservation == nil {
            rateObservation = observe(\.rate, options: [.new]) { [weak self] _, _ in self?.reconcileTransport() }
            controlObservation = observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in self?.reconcileTransport() }
        }
        if wantsPlayback { applyRate(rate) }
    }
    override func play() {
        transportLock.lock(); defer { transportLock.unlock() }
        if applyingCommand { super.play(); return }
        wantsPlayback = true; trace("play")
        applyRate(selectedRate)
    }
    override func pause() {
        transportLock.lock(); defer { transportLock.unlock() }
        if applyingCommand { super.pause(); return }
        wantsPlayback = false; trace("pause")
        applyRate(0)
    }
    override var rate: Float {
        get { super.rate }
        set {
            transportLock.lock(); defer { transportLock.unlock() }
            if applyingCommand { super.rate = newValue; return }
            wantsPlayback = newValue > 0; trace("setRate-\(newValue)")
            applyRate(wantsPlayback ? selectedRate : 0)
        }
    }
    override func playImmediately(atRate rate: Float) {
        transportLock.lock(); defer { transportLock.unlock() }
        if applyingCommand { super.playImmediately(atRate: rate); return }
        wantsPlayback = rate > 0; trace("playImmediately-\(rate)")
        applyRate(wantsPlayback ? selectedRate : 0)
    }
    private func applyRate(_ rate: Float) {
        let previous = applyingCommand
        applyingCommand = true
        defer { applyingCommand = previous }
        if rate > 0 { super.playImmediately(atRate: rate) } else { super.pause() }
    }
    private func reconcileTransport() {
        transportLock.lock(); defer { transportLock.unlock() }
        guard !applyingCommand else { return }
        if !wantsPlayback && (super.rate != 0 || timeControlStatus != .paused) {
            trace("repairPaused")
            applyRate(0)
        } else if wantsPlayback && super.rate > 0 && super.rate != selectedRate {
            trace("repairRate")
            applyRate(selectedRate)
        }
    }
    private func trace(_ command: String) {
        if traceTransport { print("NATIVE_COMMAND time=\(ProcessInfo.processInfo.systemUptime) action=\(command) wants=\(wantsPlayback) actual=\(super.rate) control=\(timeControlStatus.rawValue) selected=\(selectedRate)") }
    }
}
