import XCTest
@testable import GardenCore

final class ReviewRegressionTests: XCTestCase {
    func testChangingCompositionDurationKeepsFifteenMinuteBreak() throws {
        let engine = ScheduleEngine()
        let group = engine.occurrences(slots: TeachingSlot.seed, changes: [], start: "2026-10-22", end: "2026-10-22").filter { $0.group == "composition-1" }
        let first = try XCTUnwrap(group.first)
        let changes = try engine.movedChanges(occurrence: first, related: group, targetDate: "2026-10-22", startMinute: 615, endMinute: 670, scope: .once, cancelled: false)
        let moved = engine.occurrences(slots: TeachingSlot.seed, changes: changes, start: "2026-10-22", end: "2026-10-22").filter { $0.group == "composition-1" }
        XCTAssertEqual(moved[0].endMinute, 670)
        XCTAssertEqual(moved[1].startMinute, 685)
        XCTAssertEqual(moved[1].startMinute - moved[0].endMinute, 15)
    }
    func testInvalidScheduleBackupIsRejectedBeforeChangingStoredNotes() throws {
        let store = try DiskStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: store.root) }
        var current = GardenSnapshot(); current.marks = [StudyMark(lessonID: "7u-01", quote: "原笔记", note: "保留")]
        try store.save(current)
        let valid = try store.backup(current)
        for invalid in [
            ScheduleChange(slotID: "mon-2", date: "2026-10-19", startMinute: 700, endMinute: 600),
            ScheduleChange(slotID: "mon-2", date: "2026-99-99", cancelled: true),
            ScheduleChange(slotID: "not-a-slot", date: "2026-10-19", cancelled: true),
            ScheduleChange(slotID: "mon-2", date: "2026-10-19", scope: .fromDate, targetDate: "2026-11-19")
        ] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
            var snapshot = try XCTUnwrap(object["snapshot"] as? [String: Any])
            snapshot["changes"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([invalid]))
            object["snapshot"] = snapshot
            XCTAssertThrowsError(try store.mergeBackup(JSONSerialization.data(withJSONObject: object), into: current))
            XCTAssertEqual(try store.load(), current)
        }
    }
}
