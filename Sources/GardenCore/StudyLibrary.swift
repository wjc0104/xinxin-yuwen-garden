import Foundation

public enum StudyLibrary {
    /// Stable bundled IDs refresh while custom resources and all annotations survive upgrades.
    public static func merge(_ bundled: [StudyResource], into saved: [StudyResource]) -> [StudyResource] {
        let ids = Set(bundled.map(\.id))
        return bundled + saved.filter { !ids.contains($0.id) }
    }
    public static func search(_ query: String, resources: [StudyResource], lessons: [Lesson]) -> [StudyResource] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let names = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0.title + " " + $0.author + " " + $0.focus.joined(separator: " ")) })
        return resources.filter { resource in
            let searchable = [resource.title, resource.body, resource.source, resource.category ?? "", resource.summary ?? "", names[resource.lessonID] ?? ""].joined(separator: " ").lowercased()
            return terms.allSatisfy { searchable.contains($0) }
        }.sorted { lhs, rhs in
            let l = lhs.title.hasPrefix(query) ? 0 : 1
            let r = rhs.title.hasPrefix(query) ? 0 : 1
            return (l, lhs.isPaid ? 1 : 0, lhs.lessonID, lhs.id) < (r, rhs.isPaid ? 1 : 0, rhs.lessonID, rhs.id)
        }
    }
}

public struct ClassReminder: Codable, Equatable, Identifiable {
    public var id: String
    public var fireAt: Double
    public var expiresAt: Double
    public var title: String
    public var body: String
}
public enum ReminderPlan {
    public static func build(_ occurrences: [Occurrence], minutes: Int = 60, now: Date = Date()) -> [ClassReminder] {
        let sorted = occurrences.sorted { ($0.date, $0.startMinute, $0.id) < ($1.date, $1.startMinute, $1.id) }
        var blocks: [[Occurrence]] = []
        for item in sorted {
            if let index = blocks.lastIndex(where: { block in
                guard let last = block.last, let group = item.group else { return false }
                return last.group == group && last.originalDate == item.originalDate && last.date == item.date && last.classNumber == item.classNumber && last.subject == item.subject && item.startMinute - last.endMinute == 15
            }) { blocks[index].append(item) } else { blocks.append([item]) }
        }
        return blocks.compactMap { block in
            guard let first = block.first, let last = block.last,
                  let start = GardenDate.at(first.date, minute: first.startMinute) else { return nil }
            let fire = start.addingTimeInterval(-Double(max(0, min(60, minutes))) * 60)
            guard fire > now else { return nil }
            let section = first.startMinute < 720 ? "上午" : (first.startMinute < 1080 ? "下午" : "晚上")
            let rest = block.count > 1 ? "（连上两节，中间休息15分钟）" : ""
            return ClassReminder(id: first.id, fireAt: fire.timeIntervalSince1970 * 1000,
                expiresAt: start.timeIntervalSince1970 * 1000,
                title: "还有\(minutes)分钟上课 · \(first.subject) · \(first.classNumber)班",
                body: "\(first.date) \(section) \(TimeLabel.clock(first.startMinute))—\(TimeLabel.clock(last.endMinute))\(rest)")
        }.sorted { $0.fireAt < $1.fireAt }
    }
}
