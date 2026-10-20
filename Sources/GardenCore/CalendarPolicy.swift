import Foundation
public enum CalendarPolicy {
    public static func importChange(occurrenceID: String, start: Date?, end: Date?) -> ScheduleChange? { nil }
    public static func mayEdit(boundCalendar: String, eventCalendar: String, expectedMarker: String, actualMarker: String) -> Bool { !boundCalendar.isEmpty && !expectedMarker.isEmpty && boundCalendar == eventCalendar && expectedMarker == actualMarker }
    public static func needsReview(previous: String, actual: String?) -> Bool { actual != previous }
}
