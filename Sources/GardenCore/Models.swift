import Foundation

public struct Lesson: Codable, Identifiable, Equatable {
    public var id: String
    public var number: Int
    public var title: String
    public var author: String
    public var focus: [String]
    public init(id: String, number: Int, title: String, author: String = "", focus: [String] = []) { self.id = id; self.number = number; self.title = title; self.author = author; self.focus = focus }
}
public struct TeachingUnit: Codable, Identifiable { public var id: String; public var title: String; public var lessons: [Lesson] }
public struct Textbook: Codable, Identifiable { public var id: String; public var title: String; public var edition: String; public var verification: String; public var source: String; public var units: [TeachingUnit] }
public struct Catalog: Codable { public var title: String; public var checkedAt: String; public var books: [Textbook] }
public enum ResourceKind: String, Codable, CaseIterable { case guide, script, video, link, pdf, localVideo
    public var label: String { switch self { case .guide: return "教案"; case .script: return "试讲稿"; case .video, .localVideo: return "视频"; case .pdf: return "PDF"; case .link: return "资料链接" } }
}
public struct StudyResource: Codable, Identifiable, Equatable {
    public var id: String; public var lessonID: String; public var title: String; public var kind: ResourceKind; public var body: String; public var url: String; public var localFile: String; public var source: String; public var isPaid: Bool
    public init(id: String = UUID().uuidString, lessonID: String, title: String, kind: ResourceKind, body: String = "", url: String = "", localFile: String = "", source: String = "我的资料", isPaid: Bool = false) { self.id = id; self.lessonID = lessonID; self.title = title; self.kind = kind; self.body = body; self.url = url; self.localFile = localFile; self.source = source; self.isPaid = isPaid }
}
public struct PDFRegion: Codable, Equatable { public var page: Int; public var x: Double; public var y: Double; public var width: Double; public var height: Double
    public init(page: Int, x: Double, y: Double, width: Double, height: Double) { self.page = page; self.x = x; self.y = y; self.width = width; self.height = height }
}
public struct StudyMark: Codable, Identifiable, Equatable {
    public var id: String; public var lessonID: String; public var resourceID: String?; public var quote: String; public var note: String; public var seconds: Int?; public var regions: [PDFRegion]; public var createdAt: Date
    public init(id: String = UUID().uuidString, lessonID: String, resourceID: String? = nil, quote: String, note: String, seconds: Int? = nil, regions: [PDFRegion] = []) { self.id = id; self.lessonID = lessonID; self.resourceID = resourceID; self.quote = quote; self.note = note; self.seconds = seconds; self.regions = regions; self.createdAt = Date() }
}
public struct TeachingSlot: Codable, Identifiable, Equatable {
    public var id: String; public var weekday: Int; public var period: Int; public var classNumber: Int; public var subject: String; public var startMinute: Int; public var endMinute: Int; public var group: String?
    public init(id: String, weekday: Int, period: Int, classNumber: Int, subject: String = "语文", startMinute: Int, endMinute: Int, group: String? = nil) { self.id = id; self.weekday = weekday; self.period = period; self.classNumber = classNumber; self.subject = subject; self.startMinute = startMinute; self.endMinute = endMinute; self.group = group }
    public static var seed: [TeachingSlot] {
        let times = [2: (540, 580), 3: (615, 660), 4: (675, 720), 5: (830, 875), 6: (890, 935), 8: (1020, 1070), 9: (1110, 1160), 10: (1170, 1220)]
        let rows: [(String, Int, Int, Int)] = [("mon",2,2,3),("mon",2,3,1),("mon",2,9,3),("mon",2,10,1),("tue",3,8,1),("tue",3,9,3),("tue",3,10,3),("wed",4,2,3),("wed",4,3,1),("thu",5,3,1),("thu",5,4,1),("thu",5,5,3),("thu",5,6,3),("thu",5,8,1),("fri",6,2,3),("fri",6,3,1)]
        return rows.map { row in
            let composition = row.0 == "thu" && (3...6).contains(row.2)
            let time = times[row.2]!
            return TeachingSlot(id: "\(row.0)-\(row.2)", weekday: row.1, period: row.2, classNumber: row.3, subject: composition ? "作文" : "语文", startMinute: time.0, endMinute: time.1, group: composition ? "composition-\(row.3)" : nil)
        }
    }
}
public enum ChangeScope: String, Codable { case once, fromDate }
public struct ScheduleChange: Codable, Identifiable, Equatable {
    public var id: String; public var slotID: String; public var date: String; public var scope: ChangeScope; public var cancelled: Bool; public var targetDate: String?; public var startMinute: Int?; public var endMinute: Int?
    public init(id: String = UUID().uuidString, slotID: String, date: String, scope: ChangeScope = .once, cancelled: Bool = false, targetDate: String? = nil, startMinute: Int? = nil, endMinute: Int? = nil) { self.id = id; self.slotID = slotID; self.date = date; self.scope = scope; self.cancelled = cancelled; self.targetDate = targetDate; self.startMinute = startMinute; self.endMinute = endMinute }
}
public struct Occurrence: Identifiable, Equatable { public var id: String; public var slotID: String; public var originalDate: String; public var date: String; public var period: Int; public var classNumber: Int; public var subject: String; public var startMinute: Int; public var endMinute: Int; public var group: String? }
public struct GardenSnapshot: Codable, Equatable {
    public var schemaVersion = 1
    public var resources: [StudyResource] = []
    public var marks: [StudyMark] = []
    public var favorites: Set<String> = []
    public var slots: [TeachingSlot] = TeachingSlot.seed
    public var changes: [ScheduleChange] = []
    public var termStart = "2026-10-19"
    public var termEnd = "2027-01-31"
    public var reminderMinutes = 10
    public var termConfirmed = false
    public init() {}
}
public enum SearchSource: String, CaseIterable, Identifiable { case bilibili, all, smartedu, resources
    public var id: String { rawValue }
    public var label: String { switch self { case .bilibili: return "B站试讲"; case .all: return "全网资料"; case .smartedu: return "智慧教育"; case .resources: return "教案课件" } }
}
public enum TimeLabel {
    public static func seconds(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }), parts.allSatisfy({ Int($0) != nil }) else { return nil }
        let values = parts.compactMap { Int($0) }
        guard values[0] <= 86400, values.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
        let seconds = values.reduce(0) { $0 * 60 + $1 }
        return seconds <= 86400 ? seconds : nil
    }
    public static func clock(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
    public static func video(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
}
