import Foundation

public enum GardenDate {
    // Shared value type: no DateFormatter allocation on the schedule hot path.
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }()
    public static func parse(_ text: String) -> Date? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              string(date) == text else { return nil }
        return date
    }
    public static func string(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    public static func at(_ date: String, minute: Int) -> Date? {
        guard let day = parse(date), (0..<1440).contains(minute) else { return nil }
        return calendar.date(byAdding: .minute, value: minute, to: day)
    }
}

public struct ScheduleEngine {
    public init() {}
    public func movedChanges(occurrence: Occurrence, related: [Occurrence], targetDate: String, startMinute: Int, endMinute: Int, scope: ChangeScope, cancelled: Bool) throws -> [ScheduleChange] {
        let sorted = related.sorted { ($0.startMinute, $0.id) < ($1.startMinute, $1.id) }
        guard let anchor = sorted.firstIndex(where: { $0.id == occurrence.id }) else { throw GardenError.invalid("没有找到需要调整的课次。") }
        let duration = endMinute - startMinute
        // One edit may produce several rows (a composition moves both periods); they undo together.
        let batch = UUID().uuidString
        return try sorted.enumerated().map { index, item in
            // A grouped composition remains two independent lessons, with a 15-minute break even when duration changes.
            let shift = (index - anchor) * (duration + 15)
            let begin = startMinute + shift, finish = endMinute + shift
            guard cancelled || (begin >= 0 && finish < 1440 && begin < finish) else { throw GardenError.invalid("连堂课移动后超出当天，请重新设置时间。") }
            return ScheduleChange(slotID: item.slotID, date: item.originalDate, scope: scope, cancelled: cancelled, targetDate: cancelled ? nil : targetDate, startMinute: cancelled ? nil : begin, endMinute: cancelled ? nil : finish, batch: batch)
        }
    }
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
