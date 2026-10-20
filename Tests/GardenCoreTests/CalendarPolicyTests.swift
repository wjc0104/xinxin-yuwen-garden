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
}
