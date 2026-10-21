import XCTest
@testable import GardenCore

final class RenderWorkloadTests: XCTestCase {
    /// Diagnostic baseline for the 0.0.2 HomeView expression, using its actual term and slots.
    func testBaselineHomeScheduleWorkload() {
        let data = GardenSnapshot()
        let day = GardenDate.parse("2026-10-21")!
        let began = Date()
        var found = 0
        for _ in 0..<10 {
            let occurrences = ScheduleEngine().occurrences(slots: data.slots, changes: data.changes, start: data.termStart, end: data.termEnd)
            found += occurrences.filter { $0.date == GardenDate.string(day) }.count
        }
        XCTAssertEqual(found, 20)
        print("HOME_BASELINE_10_READS_MS=\(Date().timeIntervalSince(began) * 1000)")
    }
}
