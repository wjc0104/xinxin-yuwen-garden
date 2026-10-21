import Foundation

public enum StudyLibrary {
    /// Stable bundled IDs refresh while custom resources and all annotations survive upgrades.
    public static func merge(_ bundled: [StudyResource], into saved: [StudyResource]) -> [StudyResource] {
        let ids = Set(bundled.map(\.id))
        return bundled + saved.filter { !ids.contains($0.id) }
    }
    public static func search(_ query: String, resources: [StudyResource], lessons: [Lesson]) -> [StudyResource] {
        StudySearchIndex(lessons: lessons, resources: resources).search(query).flatMap(\.resources)
    }
}

/// Prepared once per catalog/resource revision. Bodies and generic source descriptions are deliberately excluded.
public struct StudySearchIndex {
    private struct ResourceEntry {
        let resource: StudyResource
        let title: String
    }
    private struct Entry {
        let lesson: Lesson
        let title: String
        let author: String
        let fields: [String]
        let resources: [ResourceEntry]
    }
    private let entries: [Entry]
    private let titles: Set<String>
    private let authors: Set<String>
    private let groupedResources: [String: [StudyResource]]

    public init(lessons: [Lesson], resources: [StudyResource]) {
        let groups = Dictionary(grouping: resources, by: \.lessonID).mapValues {
            $0.sorted { ($0.isPaid ? 1 : 0, $0.id) < ($1.isPaid ? 1 : 0, $1.id) }
        }
        groupedResources = groups
        titles = Set(lessons.map { Self.normalize($0.title) })
        authors = Set(lessons.map { Self.normalize($0.author) }.filter { !$0.isEmpty })
        entries = lessons.map { lesson in
            Entry(lesson: lesson, title: Self.normalize(lesson.title), author: Self.normalize(lesson.author),
                  fields: ([lesson.title, lesson.author] + lesson.focus).map(Self.normalize),
                  resources: (groups[lesson.id] ?? []).map { ResourceEntry(resource: $0, title: Self.normalize($0.title)) })
        }
    }

    public func resources(for lessonID: String) -> [StudyResource] { groupedResources[lessonID] ?? [] }

    public func search(_ query: String, filter: StudyResourceFilter = .all) -> [LessonSearchResult] {
        let terms = query.split(whereSeparator: \.isWhitespace).map { Self.normalize(String($0)) }.filter { !$0.isEmpty }
        let whole = Self.normalize(query)
        guard !whole.isEmpty else { return [] }
        let exactTitle = titles.contains(whole)
        let exactAuthor = authors.contains(whole)
        // A full author token also scopes combined queries such as 毛泽东 意象 to that author.
        let authorTerms = Set(terms.filter { authors.contains($0) })
        return entries.compactMap { entry -> (Int, LessonSearchResult)? in
            if exactTitle && entry.title != whole { return nil }
            if !exactTitle && exactAuthor && entry.author != whole { return nil }
            if !exactTitle && !exactAuthor {
                if !authorTerms.isEmpty && !authorTerms.contains(entry.author) { return nil }
            }
            let unmatchedTerms = terms.filter { term in !entry.fields.contains { $0.contains(term) } }
            let metadataMatch = exactTitle || exactAuthor || unmatchedTerms.isEmpty
            let matching = entry.resources.filter { item in
                filter.includes(item.resource) && (metadataMatch || unmatchedTerms.allSatisfy { item.title.contains($0) })
            }.map(\.resource)
            guard metadataMatch || !matching.isEmpty else { return nil }
            if filter != .all && matching.isEmpty { return nil }
            let rank = entry.title == whole ? 0 : (entry.author == whole ? 1 : (metadataMatch ? 2 : 3))
            return (rank, LessonSearchResult(lesson: entry.lesson, resources: matching))
        }.sorted { ($0.0, $0.1.lesson.id) < ($1.0, $1.1.lesson.id) }.map { $0.1 }
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_CN"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
}

public enum StudyResourceFilter: String, CaseIterable, Hashable {
    case all = "全部", video = "视频", text = "文字资料"
    public func includes(_ resource: StudyResource) -> Bool {
        let video = resource.kind == .video || resource.kind == .localVideo
        switch self { case .all: return true; case .video: return video; case .text: return !video }
    }
}

public struct LessonSearchResult: Identifiable {
    public var id: String { lesson.id }
    public let lesson: Lesson
    public let resources: [StudyResource]
    public var videoCount: Int { resources.filter { StudyResourceFilter.video.includes($0) }.count }
    public var textCount: Int { resources.count - videoCount }
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
