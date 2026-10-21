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
