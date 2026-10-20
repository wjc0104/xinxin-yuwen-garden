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
    public static var seed: [TeachingSlot] { [] }
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
public struct ScheduleEngine { public init() {}; public func occurrences(slots: [TeachingSlot], changes: [ScheduleChange], start: String, end: String) -> [Occurrence] { [] } }
public enum SearchSource: String, CaseIterable, Identifiable { case bilibili, all, smartedu, resources
    public var id: String { rawValue }
    public var label: String { switch self { case .bilibili: return "B站试讲"; case .all: return "全网资料"; case .smartedu: return "智慧教育"; case .resources: return "教案课件" } }
}
public enum SearchEngine {
    public static func matches(_ query: String, lessons: [Lesson], resources: [StudyResource], marks: [StudyMark]) -> [Lesson] { [] }
    public static func webURL(source: SearchSource, query: String) -> URL? { nil }
    public static func validatedURL(_ text: String) -> URL? { nil }
}
public enum TimeLabel {
    public static func seconds(_ text: String) -> Int? { nil }
    public static func clock(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
    public static func video(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
}
public final class DiskStore {
    public let root: URL
    public init(root: URL) throws { self.root = root; try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    public func save(_ value: GardenSnapshot) throws {}
    public func load() throws -> GardenSnapshot? { nil }
    public func attachmentURL(_ name: String) throws -> URL { root.appendingPathComponent(name) }
    public func backup(_ value: GardenSnapshot) throws -> Data { Data() }
    public func mergeBackup(_ data: Data, into current: GardenSnapshot) throws -> GardenSnapshot { current }
}
