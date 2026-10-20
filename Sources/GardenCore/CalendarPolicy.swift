import Foundation
public enum CalendarPolicy {
    public static func importChange(occurrenceID: String, start: Date?, end: Date?) -> ScheduleChange? {
        let parts = occurrenceID.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, GardenDate.parse(String(parts[1])) != nil else { return nil }
        if start == nil && end == nil { return ScheduleChange(slotID: String(parts[0]), date: String(parts[1]), cancelled: true) }
        guard let start = start, let end = end, end > start, GardenDate.string(start) == GardenDate.string(end) else { return nil }
        let calendar = GardenDate.calendar
        let begin = calendar.component(.hour, from: start) * 60 + calendar.component(.minute, from: start)
        let finish = calendar.component(.hour, from: end) * 60 + calendar.component(.minute, from: end)
        guard finish > begin else { return nil }
        return ScheduleChange(slotID: String(parts[0]), date: String(parts[1]), targetDate: GardenDate.string(start), startMinute: begin, endMinute: finish)
    }
    public static func mayEdit(boundCalendar: String, eventCalendar: String, expectedMarker: String, actualMarker: String) -> Bool { !boundCalendar.isEmpty && !expectedMarker.isEmpty && boundCalendar == eventCalendar && expectedMarker == actualMarker }
    public static func needsReview(previous: String, actual: String?) -> Bool { actual != previous }
}
