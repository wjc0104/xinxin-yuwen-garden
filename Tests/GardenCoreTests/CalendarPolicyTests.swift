import XCTest
@testable import GardenCore

final class CalendarPolicyTests: XCTestCase {
    func testOwnershipNeedsIdentifierAndPrivateMarker() {
        XCTAssertTrue(CalendarPolicy.mayEdit(boundCalendar: "owned", eventCalendar: "owned", expectedMarker: "private/1", actualMarker: "private/1"))
        XCTAssertFalse(CalendarPolicy.mayEdit(boundCalendar: "owned", eventCalendar: "other", expectedMarker: "private/1", actualMarker: "private/1"))
        XCTAssertFalse(CalendarPolicy.mayEdit(boundCalendar: "owned", eventCalendar: "owned", expectedMarker: "private/1", actualMarker: "user-added"))
        XCTAssertFalse(CalendarPolicy.mayEdit(boundCalendar: "", eventCalendar: "", expectedMarker: "", actualMarker: ""))
    }
    func testMissingOrEditedCalendarEventRequiresReview() {
        XCTAssertFalse(CalendarPolicy.needsReview(previous: "time1", actual: "time1"))
        XCTAssertTrue(CalendarPolicy.needsReview(previous: "time1", actual: "time2"))
        XCTAssertTrue(CalendarPolicy.needsReview(previous: "time1", actual: nil))
    }
    func testCalendarMoveImportsAsSingleOccurrenceAndDeletionAsCancellation() {
        let change = CalendarPolicy.importChange(occurrenceID: "mon-2@2026-10-19", start: GardenDate.at("2026-10-20", minute: 600), end: GardenDate.at("2026-10-20", minute: 640))
        XCTAssertEqual(change?.targetDate, "2026-10-20")
        XCTAssertEqual(change?.date, "2026-10-19")
        XCTAssertEqual(change?.startMinute, 600)
        XCTAssertEqual(change?.scope, .once)
        XCTAssertEqual(CalendarPolicy.importChange(occurrenceID: "mon-2@2026-10-19", start: nil, end: nil)?.cancelled, true)
        XCTAssertNil(CalendarPolicy.importChange(occurrenceID: "invalid", start: nil, end: nil))
        XCTAssertNil(CalendarPolicy.importChange(occurrenceID: "mon-2@2026-10-19", start: GardenDate.at("2026-10-20", minute: 1430), end: GardenDate.at("2026-10-21", minute: 20)))
    }
}
