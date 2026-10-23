import XCTest
@testable import XinxinGarden
import GardenCore

/// Gates intentionally ignore cancellation: the server can apply a cancelled request.
/// Every test drives the production BarkBridge, including plan encoding and revisions.
@MainActor final class BarkBridgeTests: XCTestCase {
    @MainActor private final class Harness {
        struct Call {
            let url: URL
            let method: String
            let body: [String: Any]
            let token: String?
            var completion: CheckedContinuation<[String: Any], Error>?
            var revision: Int64 { (body["revision"] as? NSNumber)?.int64Value ?? 0 }
        }
        var calls: [Call] = []
        var sleepers: [CheckedContinuation<Void, Error>?] = []
        var savedProfiles: [[String: Any]] = []
        var revision: Int64 = 0
        private var callWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
        private var sleepWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
        func bridge(enabled: Bool = true) -> BarkBridge {
            BarkBridge(address: "https://api.day.app/example123", service: "https://scheduler.invalid", token: String(repeating: "a", count: 32), enabled: enabled,
                transport: { [self] url, method, body, token in
                    try await withCheckedThrowingContinuation { continuation in
                        calls.append(Call(url: url, method: method, body: body ?? [:], token: token, completion: continuation))
                        callWaiters.removeValue(forKey: calls.count - 1)?.resume()
                    }
                }, debounce: { [self] in
                    try await withCheckedThrowingContinuation { continuation in
                        sleepers.append(continuation)
                        sleepWaiters.removeValue(forKey: sleepers.count - 1)?.resume()
                    }
                }, revision: { [self] in revision += 1; return revision }, persist: { [self] bytes in
                    savedProfiles.append(try JSONSerialization.jsonObject(with: bytes) as! [String: Any])
                })
        }
        func waitForCall(_ index: Int) async {
            if calls.count > index { return }
            await withCheckedContinuation { callWaiters[index] = $0 }
        }
        func waitForDebounce(_ index: Int) async {
            if sleepers.count > index { return }
            await withCheckedContinuation { sleepWaiters[index] = $0 }
        }
        func releaseDebounce(_ index: Int) {
            let continuation = sleepers[index]; sleepers[index] = nil; continuation?.resume()
        }
        func complete(_ index: Int, failure: Bool = false) {
            let continuation = calls[index].completion; calls[index].completion = nil
            if failure { continuation?.resume(throwing: URLError(.networkConnectionLost)) }
            else { continuation?.resume(returning: ["code": 200, "revision": calls[index].revision]) }
        }
    }
    private func snapshot(_ minutes: Int = 60) -> GardenSnapshot {
        var value = GardenSnapshot()
        value.termConfirmed = true; value.termStart = "2099-10-19"; value.termEnd = "2099-10-25"
        value.reminderMinutes = minutes
        return value
    }
    private func settleA(_ bridge: BarkBridge, _ harness: Harness) async throws {
        let task = Task { try await bridge.refresh(snapshot()) }
        await harness.waitForCall(0); harness.complete(0); try await task.value
        XCTAssertTrue(bridge.status.contains("提前60分钟"))
        XCTAssertFalse(bridge.busy)
    }
    private func encodedJobs(_ call: Harness.Call) throws -> Data {
        try JSONSerialization.data(withJSONObject: call.body["jobs"]!, options: [.sortedKeys])
    }
    func testUnchangedSettledAHasNoDebounceOrRedundantUpload() async throws {
        let h = Harness(); let bridge = h.bridge()
        try await settleA(bridge, h)
        bridge.changed(snapshot()); bridge.changed(snapshot())
        XCTAssertEqual(h.calls.count, 1); XCTAssertTrue(h.sleepers.isEmpty)
    }
    func testQueuedAToBToACancelsBWithoutUploadingAAgain() async throws {
        let h = Harness(); let bridge = h.bridge()
        try await settleA(bridge, h)
        let queued = bridge.changed(snapshot(30))
        await h.waitForDebounce(0)
        bridge.changed(snapshot())
        h.releaseDebounce(0); await queued?.value
        XCTAssertEqual(h.calls.count, 1)
        XCTAssertTrue(bridge.status.contains("提前60分钟")); XCTAssertFalse(bridge.busy)
    }
    func testInFlightReversalSendsNewerAEvenWhenBReturnsSuccessBeforeADebounce() async throws {
        let h = Harness(); let bridge = h.bridge()
        try await settleA(bridge, h)
        let b = bridge.changed(snapshot(30))
        await h.waitForDebounce(0); h.releaseDebounce(0); await h.waitForCall(1)
        let a = bridge.changed(snapshot())
        await h.waitForDebounce(1)
        h.complete(1); await b?.value
        XCTAssertEqual(bridge.status, "课表有变化，正在更新提醒", "Stale B cannot claim the later desired A is uploaded")
        h.releaseDebounce(1); await h.waitForCall(2)
        XCTAssertGreaterThan(h.calls[2].revision, h.calls[1].revision)
        XCTAssertEqual(try encodedJobs(h.calls[2]), try encodedJobs(h.calls[0]))
        XCTAssertNotEqual(try encodedJobs(h.calls[1]), try encodedJobs(h.calls[0]))
        h.complete(2); await a?.value
        XCTAssertTrue(bridge.status.contains("提前60分钟")); XCTAssertFalse(bridge.busy)
    }
    func testLateBResponseCannotOverwriteConfirmedA() async throws {
        let h = Harness(); let bridge = h.bridge()
        try await settleA(bridge, h)
        let b = bridge.changed(snapshot(30))
        await h.waitForDebounce(0); h.releaseDebounce(0); await h.waitForCall(1)
        let a = bridge.changed(snapshot())
        await h.waitForDebounce(1); h.releaseDebounce(1); await h.waitForCall(2)
        h.complete(2); await a?.value
        XCTAssertTrue(bridge.busy, "The older request is still outstanding")
        let status = bridge.status
        h.complete(1); await b?.value
        XCTAssertEqual(bridge.status, status); XCTAssertFalse(bridge.busy)
        bridge.changed(snapshot()); XCTAssertEqual(h.calls.count, 3)
    }
    func testFailedAAndLateBSuccessRemainUncertainUntilARetrySucceeds() async throws {
        let h = Harness(); let bridge = h.bridge()
        try await settleA(bridge, h)
        let b = bridge.changed(snapshot(30))
        await h.waitForDebounce(0); h.releaseDebounce(0); await h.waitForCall(1)
        let a = bridge.changed(snapshot())
        await h.waitForDebounce(1); h.releaseDebounce(1); await h.waitForCall(2)
        h.complete(2, failure: true); await a?.value
        h.complete(1); await b?.value
        XCTAssertEqual(bridge.status, "自动提醒状态待确认，请联网更新或停用")
        let retry = bridge.changed(snapshot())
        await h.waitForDebounce(2); h.releaseDebounce(2); await h.waitForCall(3)
        XCTAssertGreaterThan(h.calls[3].revision, h.calls[2].revision)
        h.complete(3); await retry?.value
        XCTAssertTrue(bridge.status.contains("提前60分钟")); XCTAssertFalse(bridge.busy)
    }
    func testStopSupersedesInflightBAndIgnoresItsLateSuccess() async throws {
        let h = Harness(); let bridge = h.bridge()
        try await settleA(bridge, h)
        let b = bridge.changed(snapshot(30))
        await h.waitForDebounce(0); h.releaseDebounce(0); await h.waitForCall(1)
        let stop = Task { try await bridge.stop() }
        await h.waitForCall(2)
        XCTAssertEqual(h.calls[2].method, "DELETE")
        XCTAssertGreaterThan(h.calls[2].revision, h.calls[1].revision)
        h.complete(2); try await stop.value
        h.complete(1); await b?.value
        XCTAssertFalse(bridge.enabled); XCTAssertFalse(bridge.busy)
        XCTAssertEqual(bridge.status, "自动提醒已停用")
        bridge.changed(snapshot()); XCTAssertEqual(h.calls.count, 3)
    }
    func testStopCancelsQueuedBAndFailureRequiresStopRetryBeforeEnable() async throws {
        let h = Harness(); let bridge = h.bridge()
        try await settleA(bridge, h)
        let b = bridge.changed(snapshot(30)); await h.waitForDebounce(0)
        let stop = Task { try await bridge.stop() }
        await h.waitForCall(1)
        h.releaseDebounce(0); await b?.value
        h.complete(1, failure: true)
        do { try await stop.value; XCTFail("Expected stop failure") } catch { }
        XCTAssertTrue(bridge.enabled)
        XCTAssertEqual(bridge.status, "停用尚未确认，请联网后重试停用")
        bridge.changed(snapshot())
        do { try await bridge.refresh(snapshot()); XCTFail("Refresh must not bypass pending Stop") } catch { }
        XCTAssertEqual(h.calls.count, 2)
        let retry = Task { try await bridge.stop() }
        await h.waitForCall(2); XCTAssertGreaterThan(h.calls[2].revision, h.calls[1].revision)
        h.complete(2); try await retry.value
        XCTAssertFalse(bridge.enabled); XCTAssertFalse(bridge.busy)
        let enable = Task { try await bridge.enable(snapshot()) }
        await h.waitForCall(3); XCTAssertGreaterThan(h.calls[3].revision, h.calls[2].revision)
        h.complete(3); try await enable.value
        XCTAssertTrue(bridge.enabled); XCTAssertTrue(bridge.status.contains("提前60分钟"))
    }
    func testExplicitRefreshCancelsQueuedBAndSendsCurrentAImmediately() async throws {
        let h = Harness(); let bridge = h.bridge()
        try await settleA(bridge, h)
        let b = bridge.changed(snapshot(30)); await h.waitForDebounce(0)
        let refresh = Task { try await bridge.refresh(snapshot()) }
        await h.waitForCall(1)
        h.releaseDebounce(0); await b?.value
        h.complete(1); try await refresh.value
        XCTAssertEqual(h.calls.count, 2)
        XCTAssertEqual(try encodedJobs(h.calls[1]), try encodedJobs(h.calls[0]))
        XCTAssertTrue(bridge.status.contains("提前60分钟"))
    }
    func testSupersededExplicitRefreshDoesNotReturnSuccessForTheLaterPlan() async throws {
        let h = Harness(); let bridge = h.bridge()
        try await settleA(bridge, h)
        let refreshB = Task { try await bridge.refresh(snapshot(30)) }
        await h.waitForCall(1)
        let a = bridge.changed(snapshot()); await h.waitForDebounce(0)
        h.complete(1)
        do { try await refreshB.value; XCTFail("Obsolete refresh must not report success") }
        catch is CancellationError { }
        catch { XCTFail("Expected cancellation of superseded refresh") }
        XCTAssertEqual(bridge.status, "课表有变化，正在更新提醒")
        h.releaseDebounce(0); await h.waitForCall(2)
        h.complete(2); await a?.value
        XCTAssertTrue(bridge.status.contains("提前60分钟"))
    }
    func testFailedEnablePersistsRecoveryBeforeRequestAndCanRefresh() async throws {
        let h = Harness(); let bridge = h.bridge(enabled: false)
        let enable = Task { try await bridge.enable(snapshot()) }
        await h.waitForCall(0)
        XCTAssertEqual(h.savedProfiles.first?["enabled"] as? Bool, true)
        h.complete(0, failure: true)
        do { try await enable.value; XCTFail("Expected enable failure") } catch { }
        XCTAssertTrue(bridge.enabled); XCTAssertEqual(bridge.status, "自动提醒状态待确认，请联网更新或停用")
        let retry = Task { try await bridge.refresh(snapshot()) }
        await h.waitForCall(1); h.complete(1); try await retry.value
        XCTAssertTrue(bridge.status.contains("提前60分钟"))
    }
    func testConfigurationChangeAfterStopUsesNewUserConnection() async throws {
        let h = Harness(); let bridge = h.bridge()
        try await settleA(bridge, h)
        let stop = Task { try await bridge.stop() }
        await h.waitForCall(1); h.complete(1); try await stop.value
        let token = String(repeating: "b", count: 32)
        try bridge.save(address: "https://api.day.app/another456", connection: "https://other-scheduler.invalid#" + token)
        let enable = Task { try await bridge.enable(snapshot()) }
        await h.waitForCall(2)
        XCTAssertEqual(h.calls[2].url.absoluteString, "https://other-scheduler.invalid/schedule")
        XCTAssertEqual(h.calls[2].token, token)
        XCTAssertEqual(h.calls[2].body["deviceKey"] as? String, "another456")
        h.complete(2); try await enable.value
        XCTAssertTrue(bridge.enabled)
    }
}
