import XCTest
@testable import GardenCore

final class StudyLibraryTests: XCTestCase {
    func testOldResourcesDecodeAndUpgradeKeepsCustomContent() throws {
        let old = #"{"id":"spring-script","lessonID":"7u-01","title":"old","kind":"script","body":"old text","url":"","localFile":"","source":"original","isPaid":false}"#
        let saved = try JSONDecoder().decode(StudyResource.self, from: Data(old.utf8))
        XCTAssertNil(saved.thumbnail)
        let custom = StudyResource(id: "personal", lessonID: "7u-01", title: "my text", kind: .guide)
        var new = saved; new.body = "updated text"
        let merged = StudyLibrary.merge([new], into: [saved, custom])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first?.body, "updated text")
        XCTAssertEqual(merged.last, custom)
    }
    func testSearchReturnsActualMatchingResourcesAndSupportsAuthor() {
        let lessons = [Lesson(id:"spring",number:1,title:"春",author:"朱自清"),Lesson(id:"winter",number:2,title:"济南的冬天",author:"老舍")]
        let resources = [StudyResource(id:"v",lessonID:"winter",title:"温晴与拟人",kind:.video,url:"https://example.com/video"),StudyResource(id:"s",lessonID:"spring",title:"十分钟试讲",kind:.script,body:"春风图")]
        XCTAssertEqual(StudyLibrary.search("老舍 拟人", resources:resources, lessons:lessons).map(\.id),["v"])
        XCTAssertEqual(StudyLibrary.search("济南的冬天", resources:resources, lessons:lessons).map(\.id),["v"])
        XCTAssertTrue(StudyLibrary.search("不存在的内容",resources:resources,lessons:lessons).isEmpty)
    }
    func testExactNormalizedTitleAndFullAuthorSuppressUnrelatedMentions() {
        let lessons = [
            Lesson(id: "spring", number: 1, title: "春", author: "朱自清"),
            Lesson(id: "late", number: 2, title: "晚春", author: "韩愈"),
            Lesson(id: "snow", number: 3, title: "沁园春·雪", author: "毛泽东"),
            Lesson(id: "news", number: 4, title: "消息二则", author: "毛泽东")
        ]
        let resources = lessons.map { StudyResource(id: $0.id, lessonID: $0.id, title: "春 毛泽东 教学示例", kind: .video, body: "春与毛泽东的延伸阅读") }
        let index = StudySearchIndex(lessons: lessons, resources: resources)
        XCTAssertEqual(index.search(" 《春》 ").map(\.id), ["spring"])
        XCTAssertEqual(index.search("沁园春 雪").map(\.id), ["snow"])
        XCTAssertEqual(Set(index.search("毛泽东").map(\.id)), Set(["snow", "news"]))
        XCTAssertTrue(index.search("不存在").isEmpty)
        XCTAssertTrue(index.search("  ·  ").isEmpty)
    }

    func testCombinedQueriesUseFocusOrSameResourceTitleAndIgnoreBodyBoilerplate() {
        let lesson = Lesson(id: "winter", number: 2, title: "济南的冬天", author: "老舍", focus: ["景物描写", "拟人"])
        let other = Lesson(id: "spring", number: 1, title: "春", author: "朱自清")
        let resources = [
            StudyResource(id: "video", lessonID: "winter", title: "温晴的济南", kind: .video),
            StudyResource(id: "plan", lessonID: "winter", title: "朗读课堂", kind: .guide),
            StudyResource(id: "split", lessonID: "winter", title: "板书设计", kind: .script),
            StudyResource(id: "decoy", lessonID: "spring", title: "备课提纲", kind: .guide, body: "老舍 拟人 人物形象 朗读 板书")
        ]
        let index = StudySearchIndex(lessons: [lesson, other], resources: resources)
        XCTAssertEqual(index.search("老舍 拟人").first?.resources.count, 3)
        XCTAssertEqual(index.search("老舍 朗读").first?.resources.map(\.id), ["plan"])
        XCTAssertEqual(index.search("拟人", filter: .video).first?.resources.map(\.id), ["video"])
        XCTAssertEqual(index.search("老舍", filter: .text).first?.resources.count, 2)
        XCTAssertTrue(index.search("人物形象").isEmpty, "Body boilerplate must not supply matches")
        XCTAssertTrue(index.search("朗读 板书").isEmpty, "Separate resource titles must not manufacture a combined match")
    }

    func testActualBundledCatalogExactQueriesAndRepeatedPreparedLookups() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: root.appendingPathComponent("App/Resources/catalog.json")))
        let resources = try JSONDecoder().decode([StudyResource].self, from: Data(contentsOf: root.appendingPathComponent("App/Resources/library.json")))
        let lessons = catalog.books.flatMap { $0.units.flatMap(\.lessons) }
        let index = StudySearchIndex(lessons: lessons, resources: resources)
        XCTAssertEqual(index.search("春").map(\.id), lessons.filter { $0.title == "春" }.map(\.id))
        XCTAssertEqual(Set(index.search("毛泽东").map(\.id)), Set(lessons.filter { $0.author == "毛泽东" }.map(\.id)))
        let poems = index.search("古诗")
        XCTAssertGreaterThan(poems.count, 1)
        XCTAssertEqual(Set(poems.map(\.id)).count, poems.count, "Broad queries remain grouped by stable lesson ID")
        let began = Date()
        for _ in 0..<100 {
            XCTAssertEqual(lessons.reduce(0) { $0 + index.resources(for: $1.id).count }, resources.count)
            XCTAssertEqual(index.search("春").map(\.id), ["7u-01"])
            XCTAssertEqual(index.search("老舍 温晴").map(\.id), ["7u-02"])
        }
        let elapsed = Date().timeIntervalSince(began)
        print("PREPARED_LIBRARY_100_LOOKUPS_QUERIES_MS=\(elapsed * 1000)")
        XCTAssertLessThan(elapsed, 5, "A generous batch bound guards against rebuilding the index during warm lookups; this is not a frame-latency assertion")
    }

    func testOneHourReminderAndCompositionBreaks() throws {
        let events = ScheduleEngine().occurrences(slots:TeachingSlot.seed,changes:[],start:"2026-10-22",end:"2026-10-22")
        let reminders = ReminderPlan.build(events,now:GardenDate.parse("2026-10-21")!)
        XCTAssertEqual(reminders.count,3)
        let morning = try XCTUnwrap(reminders.first)
        XCTAssertEqual(morning.fireAt,GardenDate.at("2026-10-22",minute:555)!.timeIntervalSince1970*1000)
        XCTAssertTrue(morning.body.contains("10:15—12:00"))
        XCTAssertTrue(morning.body.contains("休息15分钟"))
        XCTAssertEqual(reminders[1].fireAt,GardenDate.at("2026-10-22",minute:770)!.timeIntervalSince1970*1000)
    }
    func testMovingOneCompositionPeriodSeparatesRemindersAndCancelDropsIt() throws {
        let change = ScheduleChange(slotID:"thu-4",date:"2026-10-22",scope:.once,cancelled:false,targetDate:"2026-10-23",startMinute:675,endMinute:720)
        // Use the actual stable seed ID rather than assuming a UI label.
        let second = try XCTUnwrap(TeachingSlot.seed.first { $0.weekday == 5 && $0.period == 4 })
        var actual = change; actual.slotID = second.id
        let events = ScheduleEngine().occurrences(slots:TeachingSlot.seed,changes:[actual],start:"2026-10-22",end:"2026-10-23")
        let reminders = ReminderPlan.build(events,now:GardenDate.parse("2026-10-21")!)
        XCTAssertTrue(reminders.contains { $0.id == second.id + "@2026-10-22" && $0.body.contains("2026-10-23") })
        XCTAssertFalse(reminders.first?.body.contains("连上两节") ?? true)
        XCTAssertTrue(ReminderPlan.build(events,now:GardenDate.parse("2026-10-24")!).isEmpty)
    }
}
