import XCTest
import Combine
@testable import XinxinGarden
import GardenCore

@MainActor final class PlaybackAndResponsivenessTests: XCTestCase {
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
    func testPreparedLibraryRepeatedReadsAndNoteOnlySaveReuseRevision() throws {
        let store = AppStore()
        let saved = store.data
        defer { store.update { $0 = saved } }
        XCTAssertGreaterThan(store.lessons.count, 190)
        XCTAssertGreaterThan(store.data.resources.count, 800)
        let revision = store.libraryRevision
        let schedule = store.occurrences
        let began = Date()
        for _ in 0..<100 {
            XCTAssertEqual(store.lessons.reduce(0) { $0 + store.resources($1.id).count }, store.data.resources.count)
            for lesson in store.lessons {
                XCTAssertEqual(store.lesson(lesson.id), lesson)
                XCTAssertFalse(store.bookTitle(lesson.id).isEmpty)
            }
            XCTAssertEqual(store.search("春").map(\.id), ["7u-01"])
            XCTAssertEqual(Set(store.search("毛泽东").map(\.id)), Set(store.lessons.filter { $0.author == "毛泽东" }.map(\.id)))
        }
        let elapsed = Date().timeIntervalSince(began)
        print("APP_PREPARED_LIBRARY_100_READS_QUERIES_MS=\(elapsed * 1000)")
        XCTAssertLessThan(elapsed, 5, "Warm batch reads must reuse prepared library data; this is not a frame-latency assertion")
        XCTAssertTrue(store.update { $0.marks.append(StudyMark(lessonID: "7u-01", quote: "", note: "cache regression")) })
        XCTAssertEqual(store.libraryRevision, revision, "Notes must not rebuild the resource/search index")
        XCTAssertEqual(store.occurrences, schedule)
        var custom = StudyResource(id: "cache-regression", lessonID: "7u-01", title: "缓存回归专用资料", kind: .guide)
        let observed = expectation(description: "Published snapshot sees current resource/search cache")
        let observation = store.$data.dropFirst().sink { snapshot in
            if snapshot.resources.contains(where: { $0.id == custom.id }) {
                XCTAssertEqual(store.resources("7u-01").first { $0.id == custom.id }?.title, custom.title)
                XCTAssertEqual(store.search(custom.title).first?.resources.map(\.id), [custom.id])
                observed.fulfill()
            }
        }
        XCTAssertTrue(store.update { $0.resources.append(custom) })
        wait(for: [observed], timeout: 1)
        observation.cancel()
        XCTAssertEqual(store.libraryRevision, revision + 1)
        XCTAssertEqual(store.search("缓存回归专用资料").first?.resources.map(\.id), [custom.id])
        custom.title = "修改后的专用资料"
        XCTAssertTrue(store.update { snapshot in snapshot.resources[snapshot.resources.firstIndex { $0.id == custom.id }!] = custom })
        XCTAssertEqual(store.libraryRevision, revision + 2)
        XCTAssertTrue(store.search("缓存回归专用资料").isEmpty)
        XCTAssertEqual(store.search("修改后的专用资料").first?.resources.map(\.id), [custom.id])
        XCTAssertTrue(store.update { $0.resources.removeAll { $0.id == custom.id } })
        XCTAssertEqual(store.libraryRevision, revision + 3)
        XCTAssertTrue(store.search("修改后的专用资料").isEmpty)
        XCTAssertFalse(store.resources("7u-01").contains { $0.id == custom.id })
    }

    func testBackupMergePublishesPreparedLibraryAndKeepsCurrentNotes() throws {
        let store = AppStore()
        let saved = store.data
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { store.update { $0 = saved }; try? FileManager.default.removeItem(at: url) }
        let note = StudyMark(lessonID: "7u-01", quote: "", note: "restore cache regression")
        XCTAssertTrue(store.update { $0.marks.append(note) })
        let revision = store.libraryRevision
        var incoming = GardenSnapshot()
        let resource = StudyResource(lessonID: "7u-01", title: "合并备份的专用资料", kind: .guide)
        incoming.resources = [resource]
        let disk = try XCTUnwrap(store.disk)
        try disk.backup(incoming).write(to: url)
        store.restore(url)
        XCTAssertEqual(store.libraryRevision, revision + 1)
        XCTAssertEqual(store.search(resource.title).first?.resources.map(\.id), [resource.id])
        XCTAssertTrue(store.marks("7u-01").contains { $0.id == note.id })
        XCTAssertEqual(store.resources("7u-01").first { $0.id == resource.id }, resource)
    }

    func testKnownCDNThumbnailSizingPreservesOtherOrigins() throws {
        let source = "https://i0.hdslb.com/bfs/archive/example.jpg?token=public#cover"
        let resized = try XCTUnwrap(GardenTheme.thumbnailURL(source))
        XCTAssertEqual(resized.path, "/bfs/archive/example.jpg@320w_220h_1c.webp")
        XCTAssertEqual(resized.query, "token=public")
        XCTAssertEqual(resized.fragment, "cover")
        XCTAssertEqual(GardenTheme.thumbnailURL("https://i2.hdslb.com/bfs/a.png@640w.webp")?.path, "/bfs/a.png@320w_220h_1c.webp")
        for source in ["https://example.com/a.jpg?size=original", "https://i0.hdslb.com.example.com/a.jpg", "https://i0.hdslb.com/", "https://i0.hdslb.com/bfs/a.gif"] {
            XCTAssertEqual(GardenTheme.thumbnailURL(source)?.absoluteString, source)
        }
        XCTAssertNil(GardenTheme.thumbnailURL(nil))
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
