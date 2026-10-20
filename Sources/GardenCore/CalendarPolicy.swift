import Foundation
public enum CalendarPolicy {
    public static func mayEdit(boundCalendar: String, eventCalendar: String, expectedMarker: String, actualMarker: String) -> Bool { false }
    public static func needsReview(previous: String, actual: String?) -> Bool { false }
}
