import XCTest
@testable import XinxinGarden
import GardenCore

@MainActor final class PlaybackAndResponsivenessTests: XCTestCase {
    func testBilibiliPlayerUsesRequestedEpisode() throws {
        let url = try XCTUnwrap(StudyVideoURL.player("https://www.bilibili.com/video/BV1eUAieoEZd/?p=2", seconds: 205))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "p" }?.value, "2")
        XCTAssertEqual(query.first { $0.name == "t" }?.value, "205")
    }
    func testRepeatedScheduleReadsFitWarmRenderingBudget() {
        let store = AppStore()
        XCTAssertFalse(store.occurrences.isEmpty)
        let begin = Date()
        var count = 0
        for _ in 0..<100 { count += store.occurrences.count }
        let elapsed = Date().timeIntervalSince(begin)
        print("APP_WARM_SCHEDULE_100_READS_MS=\(elapsed*1000)")
        XCTAssertGreaterThan(count, 0)
        XCTAssertLessThan(elapsed, 0.1, "Reading unchanged schedule must not regenerate a whole term on the UI thread")
    }
    func testScheduleLookupUpdatesAfterTemporaryMoveAndUndo() throws {
        let store = AppStore()
        let saved = store.data
        defer { store.update { $0 = saved } }
        XCTAssertTrue(store.update { $0.termStart = "2026-10-19"; $0.termEnd = "2026-10-25"; $0.changes = [] })
        let id = "mon-2@2026-10-19"
        XCTAssertEqual(store.occurrences.first { $0.id == id }?.date, "2026-10-19")
        XCTAssertTrue(store.update { $0.changes.append(ScheduleChange(slotID: "mon-2", date: "2026-10-19", targetDate: "2026-10-20", startMinute: 480, endMinute: 520)) })
        XCTAssertEqual(store.occurrences.first { $0.id == id }?.date, "2026-10-20")
        XCTAssertTrue(store.update { $0.changes = [] })
        XCTAssertEqual(store.occurrences.first { $0.id == id }?.date, "2026-10-19")
    }
}
