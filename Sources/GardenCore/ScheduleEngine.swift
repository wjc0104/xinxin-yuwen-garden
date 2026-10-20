import Foundation

public enum GardenDate {
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }
    public static func parse(_ text: String) -> Date? {
        guard text.count == 10 else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: text), string(date) == text else { return nil }
        return date
    }
    public static func string(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    public static func at(_ date: String, minute: Int) -> Date? {
        guard let day = parse(date), (0..<1440).contains(minute) else { return nil }
        return calendar.date(byAdding: .minute, value: minute, to: day)
    }
}

public struct ScheduleEngine {
    public init() {}
    public func occurrences(slots: [TeachingSlot], changes: [ScheduleChange], start: String, end: String) -> [Occurrence] {
        guard let first = GardenDate.parse(start), let last = GardenDate.parse(end), first <= last,
              let span = GardenDate.calendar.dateComponents([.day], from: first, to: last).day, span <= 730 else { return [] }
        let calendar = GardenDate.calendar
        var result: [Occurrence] = []
        for offset in 0...span {
            guard let original = calendar.date(byAdding: .day, value: offset, to: first) else { continue }
            let date = GardenDate.string(original)
            let weekday = calendar.component(.weekday, from: original)
            for slot in slots where slot.weekday == weekday {
                let permanent = changes.filter { $0.slotID == slot.id && $0.scope == .fromDate && $0.date <= date }.sorted { $0.date < $1.date }.last
                let once = changes.last { $0.slotID == slot.id && $0.scope == .once && $0.date == date }
                let change = once ?? permanent
                if change?.cancelled == true { continue }
                var target = date
                if let targetDate = change?.targetDate, let targetValue = GardenDate.parse(targetDate), let anchor = change.flatMap({ GardenDate.parse($0.date) }) {
                    if change?.scope == .once { target = targetDate }
                    else {
                        let shift = calendar.dateComponents([.day], from: anchor, to: targetValue).day ?? 0
                        // A permanent move shifts the weekday within the same teaching week.
                        if abs(shift) <= 6, let moved = calendar.date(byAdding: .day, value: shift, to: original) { target = GardenDate.string(moved) }
                    }
                }
                let begin = change?.startMinute ?? slot.startMinute
                let finish = change?.endMinute ?? slot.endMinute
                guard (0..<1440).contains(begin), finish > begin, finish <= 1439 else { continue }
                result.append(Occurrence(id: "\(slot.id)@\(date)", slotID: slot.id, originalDate: date, date: target, period: slot.period, classNumber: slot.classNumber, subject: slot.subject, startMinute: begin, endMinute: finish, group: slot.group))
            }
        }
        return result.sorted { ($0.date, $0.startMinute, $0.id) < ($1.date, $1.startMinute, $1.id) }
    }
}
