import XCTest
@testable import GardenCore

final class GardenCoreTests: XCTestCase {
    func testMondayClassesAndThursdayBreaksKeepVerifiedTimes() throws {
        let engine = ScheduleEngine()
        let monday = engine.occurrences(slots: TeachingSlot.seed, changes: [], start: "2026-10-19", end: "2026-10-19")
        XCTAssertEqual(monday.map(\.startMinute), [540, 615, 1110, 1170])
        XCTAssertEqual(monday.map(\.classNumber), [3, 1, 3, 1])
        let thursday = engine.occurrences(slots: TeachingSlot.seed, changes: [], start: "2026-10-22", end: "2026-10-22")
        XCTAssertEqual(thursday.map(\.startMinute), [615, 675, 830, 890, 1020])
        if thursday.count >= 4 {
            XCTAssertEqual(thursday[1].startMinute - thursday[0].endMinute, 15)
            XCTAssertEqual(thursday[3].startMinute - thursday[2].endMinute, 15)
        }
    }

    func testCancelledOccurrenceDoesNotCancelTheFollowingWeek() {
        let change = ScheduleChange(slotID: "mon-2", date: "2026-10-19", cancelled: true)
        let items = ScheduleEngine().occurrences(slots: TeachingSlot.seed, changes: [change], start: "2026-10-19", end: "2026-10-26")
        XCTAssertFalse(items.contains { $0.id == "mon-2@2026-10-19" })
        XCTAssertTrue(items.contains { $0.id == "mon-2@2026-10-26" })
    }

    func testMovingOneClassPreservesIdentityAndNextWeeksSchedule() {
        let change = ScheduleChange(slotID: "mon-2", date: "2026-10-19", targetDate: "2026-10-20", startMinute: 480, endMinute: 525)
        let items = ScheduleEngine().occurrences(slots: TeachingSlot.seed, changes: [change], start: "2026-10-19", end: "2026-10-26")
        let moved = items.filter { $0.id == "mon-2@2026-10-19" }
        XCTAssertEqual(moved.count, 1)
        XCTAssertEqual(moved.first?.date, "2026-10-20")
        XCTAssertEqual(moved.first?.startMinute, 480)
        XCTAssertEqual(items.first { $0.id == "mon-2@2026-10-26" }?.startMinute, 540)
    }

    func testPermanentMoveStartsAtEffectiveDate() {
        let change = ScheduleChange(slotID: "mon-2", date: "2026-10-26", scope: .fromDate, targetDate: "2026-10-27", startMinute: 480, endMinute: 525)
        let items = ScheduleEngine().occurrences(slots: TeachingSlot.seed, changes: [change], start: "2026-10-19", end: "2026-11-02")
        XCTAssertEqual(items.first { $0.id == "mon-2@2026-10-19" }?.date, "2026-10-19")
        XCTAssertEqual(items.first { $0.id == "mon-2@2026-10-26" }?.date, "2026-10-27")
        XCTAssertEqual(items.first { $0.id == "mon-2@2026-11-02" }?.date, "2026-11-03")
    }

    func testSingleExceptionWinsOverPermanentMove() {
        let changes = [ScheduleChange(slotID: "mon-2", date: "2026-10-19", scope: .fromDate, targetDate: "2026-10-20", startMinute: 480, endMinute: 525), ScheduleChange(slotID: "mon-2", date: "2026-10-26", cancelled: true)]
        let items = ScheduleEngine().occurrences(slots: TeachingSlot.seed, changes: changes, start: "2026-10-19", end: "2026-10-26")
        XCTAssertTrue(items.contains { $0.id == "mon-2@2026-10-19" })
        XCTAssertFalse(items.contains { $0.id == "mon-2@2026-10-26" })
    }

    func testCrossedOutClassesNeverBecomeCalendarEvents() {
        let items = ScheduleEngine().occurrences(slots: TeachingSlot.seed, changes: [], start: "2026-10-19", end: "2026-10-25")
        XCTAssertEqual(items.count, 16)
        XCTAssertFalse(items.contains { $0.date == "2026-10-23" && $0.startMinute == 480 })
        XCTAssertFalse(items.contains { $0.date == "2026-10-22" && $0.startMinute == 540 })
    }

    func testInvalidDateRangeAndInvalidTimesDoNotProduceEvents() {
        let engine = ScheduleEngine()
        XCTAssertTrue(engine.occurrences(slots: TeachingSlot.seed, changes: [], start: "oops", end: "2026-10-19").isEmpty)
        XCTAssertTrue(engine.occurrences(slots: TeachingSlot.seed, changes: [], start: "2026-10-26", end: "2026-10-19").isEmpty)
        let change = ScheduleChange(slotID: "mon-2", date: "2026-10-19", startMinute: 800, endMinute: 500)
        XCTAssertFalse(engine.occurrences(slots: TeachingSlot.seed, changes: [change], start: "2026-10-19", end: "2026-10-19").contains { $0.slotID == "mon-2" })
    }

    func testChineseSearchAlsoMatchesPersonalNotesAndAuthor() {
        let lessons = [Lesson(id: "spring", number: 1, title: "春", author: "朱自清", focus: ["比喻", "朗读"]), Lesson(id: "winter", number: 2, title: "济南的冬天", author: "老舍", focus: [])]
        XCTAssertEqual(SearchEngine.matches(" 朱自清 ", lessons: lessons, resources: [], marks: []).map(\.id), ["spring"])
        let mark = StudyMark(lessonID: "winter", quote: "", note: "面试：拟人教学")
        XCTAssertEqual(SearchEngine.matches("拟人", lessons: lessons, resources: [], marks: [mark]).map(\.id), ["winter"])
        XCTAssertEqual(SearchEngine.matches("", lessons: lessons, resources: [], marks: []).count, 2)
    }

    func testSearchLinksEncodeChineseAmpersandAndPlusWithoutExtraParameters() throws {
        let url = try XCTUnwrap(SearchEngine.webURL(source: .bilibili, query: "春 A+B & 初中语文"))
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.host, "search.bilibili.com")
        XCTAssertEqual(parts.queryItems?.count, 1)
        XCTAssertEqual(parts.queryItems?.first?.value, "春 A+B & 初中语文")
        XCTAssertTrue(url.absoluteString.contains("%2B"))
    }

    func testUnsafeAndEmptyExternalURLsAreRejected() {
        for value in ["", "javascript:alert(1)", "file:///etc/passwd", "https://", "https://user:secret@example.com"] {
            XCTAssertNil(SearchEngine.validatedURL(value))
        }
        XCTAssertEqual(SearchEngine.validatedURL(" https://www.bilibili.com/video/BV1rK4y1Y7RD/ ")?.host, "www.bilibili.com")
    }

    func testVideoBookmarkParsesClockTimesAndRejectsInvalidSeconds() {
        XCTAssertEqual(TimeLabel.seconds("03:25"), 205)
        XCTAssertEqual(TimeLabel.seconds("1:02:03"), 3723)
        XCTAssertNil(TimeLabel.seconds("3:70"))
        XCTAssertNil(TimeLabel.seconds("-3"))
    }

    func testNotesAndScheduleChangesSurviveSaveAndLoad() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try DiskStore(root: folder)
        var snapshot = GardenSnapshot()
        snapshot.marks = [StudyMark(lessonID: "spring", quote: "重点", note: "慢一点讲", seconds: 205)]
        snapshot.changes = [ScheduleChange(slotID: "mon-2", date: "2026-10-19", cancelled: true)]
        try store.save(snapshot)
        let restored = try XCTUnwrap(store.load())
        XCTAssertEqual(restored.marks.first?.note, "慢一点讲")
        XCTAssertEqual(restored.marks.first?.seconds, 205)
        XCTAssertEqual(restored.changes.first?.cancelled, true)
    }

    func testMalformedBackupDoesNotOverwriteExistingNotes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try DiskStore(root: folder)
        var snapshot = GardenSnapshot()
        snapshot.marks = [StudyMark(lessonID: "spring", quote: "existing", note: "keep")]
        try store.save(snapshot)
        XCTAssertThrowsError(try store.mergeBackup(Data("{broken".utf8), into: snapshot))
        XCTAssertEqual(try store.load()?.marks.first?.note, "keep")
    }

    func testBackupMergeKeepsCurrentEditsAndAddsMissingNotes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try DiskStore(root: folder)
        var old = GardenSnapshot()
        old.marks = [StudyMark(id: "same", lessonID: "spring", quote: "", note: "older"), StudyMark(id: "missing", lessonID: "spring", quote: "", note: "restore")]
        let data = try store.backup(old)
        var current = GardenSnapshot()
        current.marks = [StudyMark(id: "same", lessonID: "spring", quote: "", note: "new edit")]
        let merged = try store.mergeBackup(data, into: current)
        XCTAssertEqual(merged.marks.count, 2)
        XCTAssertEqual(merged.marks.first { $0.id == "same" }?.note, "new edit")
        XCTAssertEqual(merged.marks.first { $0.id == "missing" }?.note, "restore")
    }

    func testAttachmentPathsCannotEscapeDocuments() throws {
        let store = try DiskStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: store.root) }
        for name in ["../secret", "/etc/passwd", "a/b.pdf", "a\\b.pdf", "..", ""] {
            XCTAssertThrowsError(try store.attachmentURL(name))
        }
        XCTAssertEqual(try store.attachmentURL("safe.pdf").lastPathComponent, "safe.pdf")
    }
}
