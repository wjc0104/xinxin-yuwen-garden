import Foundation

/// App-owned, bounded UI-test artifact. Only fixed event names and numeric state enter this sink.
enum PlayerTransportEvent: String {
    case checkpoint, configureBefore, configureAfter, playBefore, playAfter, pauseBefore, pauseAfter
    case setRateBefore, setRateAfter, playImmediatelyBefore, playImmediatelyAfter
    case applyBefore, applyAfter, observedState, repairPaused, repairRate, clockSample
    case appToggle, noteCaptureBefore, noteCaptureAfter, focusOn, focusOff
    case fullscreenBegin, fullscreenAppeared, fullscreenMounted
    case fullscreenExit, fullscreenDisappeared, fullscreenDismissed
    case inlineAppeared, inlineDisappeared
}

final class PlayerTransportTrace {
    static let shared = PlayerTransportTrace()
    static let fileName = "player-transport.jsonl"
    static let maxRecords = 2048
    static let maxBytes = 512 * 1024
    let enabled: Bool
    private let lock = NSLock()
    private let writer = DispatchQueue(label: "garden.ui-test-transport", qos: .utility)
    private var records = 0
    private var bytes = 0
    private var players = 0
    private let file: URL?

    private init() {
        let arguments = ProcessInfo.processInfo.arguments
        enabled = arguments.contains("--ui-testing") && arguments.contains("--trace-player-transport")
        file = enabled ? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(Self.fileName) : nil
        // The singleton is started at app launch. Reset is queued before any record, never on the main thread.
        if let file = file {
            writer.async {
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? Data().write(to: file, options: .atomic)
            }
        }
    }

    func allocatePlayer() -> Int {
        guard enabled else { return 0 }
        lock.lock(); defer { lock.unlock() }
        players += 1
        return players // Launch-local ordinal, never a resource/account/device identifier.
    }

    func record(_ event: PlayerTransportEvent, state: [String: Any]) {
        guard enabled, let file = file else { return }
        lock.lock(); defer { lock.unlock() }
        guard records < Self.maxRecords, bytes < Self.maxBytes else { return }
        var row = state
        row["event"] = event.rawValue
        row["sequence"] = records + 1
        row["uptime"] = ProcessInfo.processInfo.systemUptime
        // Reserve the last record/bytes for an explicit terminal marker; queued data is also bounded.
        guard var data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        if records == Self.maxRecords - 1 || bytes + data.count + 1 > Self.maxBytes - 128 {
            data = Data("{\"event\":\"traceLimit\",\"sequence\":\(records + 1),\"uptime\":\(ProcessInfo.processInfo.systemUptime)}".utf8)
            records = Self.maxRecords
        } else { records += 1 }
        data.append(0x0a)
        guard bytes + data.count <= Self.maxBytes else { records = Self.maxRecords; return }
        bytes += data.count
        let line = data
        writer.async {
            guard let handle = try? FileHandle(forWritingTo: file) else { return }
            defer { try? handle.close() }
            do { try handle.seekToEnd(); try handle.write(contentsOf: line) } catch { /* Diagnostic failure cannot affect playback. */ }
        }
    }
}
