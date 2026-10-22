import SwiftUI
import UIKit
import GardenCore

@MainActor final class AppStore: ObservableObject {
    @Published private(set) var data = GardenSnapshot()
    @Published var error: String?
    @Published var notice: String?
    @Published var recentResourceID = UserDefaults.standard.string(forKey: "recent-resource")
    private(set) var catalog: Catalog?
    private(set) var disk: DiskStore?
    private(set) var readable = false
    let calendar = CalendarBridge()
    private var cachedOccurrences: [Occurrence] = []
    private var occurrencesByDate: [String: [Occurrence]] = [:]
    private var allLessons: [Lesson] = []
    private var lessonByID: [String: Lesson] = [:]
    private var bookTitleByLessonID: [String: String] = [:]
    private var resourcesByLesson: [String: [StudyResource]] = [:]
    private var resourceByID: [String: StudyResource] = [:]
    private var marksByLesson: [String: [StudyMark]] = [:]

    init() {
        do {
            guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json") else { throw GardenError.invalid("目录文件缺失，请重新安装完整 IPA。") }
            catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let folder = ProcessInfo.processInfo.arguments.contains("--ui-testing") ? "GardenUITesting" : "XinxinGarden"
            let store = try DiskStore(root: base.appendingPathComponent(folder, isDirectory: true))
            disk = store
            if let saved = try store.load() { data = saved }
            else {
                var initial = GardenSnapshot()
                try store.save(initial); data = initial
            }
            if let url = Bundle.main.url(forResource: "library", withExtension: "json") {
                let bundled = try JSONDecoder().decode([StudyResource].self, from: Data(contentsOf: url))
                let retired: Set<String> = ["spring-video", "spring-plan", "pear-video", "yueyang-video"]
                let annotated = Set(data.marks.compactMap(\.resourceID))
                let previous = data.resources
                let kept = previous.filter { !(retired.contains($0.id) && !annotated.contains($0.id)) }
                data.resources = StudyLibrary.merge(bundled, into: kept, excluding: data.deletedIDs)
                // Only rewrite the library file when an upgrade actually changed it.
                var changed = data.resources != previous
                if !UserDefaults.standard.bool(forKey: "reminder-v002") { data.reminderMinutes = 60; changed = true }
                if changed { try store.save(data) }
                UserDefaults.standard.set(true, forKey: "reminder-v002")
            }
            readable = true
            reindex()
            rebuildSchedule(data)
            if ProcessInfo.processInfo.arguments.contains("--ui-testing"), !data.resources.contains(where: { $0.id == "ui-pdf" }) {
                let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
                let bytes = renderer.pdfData { context in context.beginPage(); ("PDF Garden Focus" as NSString).draw(at: CGPoint(x: 60, y: 120), withAttributes: [.font: UIFont.systemFont(ofSize: 26)]) }
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Garden-UI-Fixture.pdf")
                try bytes.write(to: temporary, options: .atomic)
                let name = try store.importFile(temporary)
                data.resources.append(StudyResource(id: "ui-pdf", lessonID: "7u-01", title: "原创测试 PDF", kind: .pdf, localFile: name))
                reindex()
                try store.save(data)
            }
        } catch { self.error = "暂时无法读取资料，已停止保存以保护原数据。\n" + error.localizedDescription }
    }
    var lessons: [Lesson] { allLessons }
    func remember(_ resource: StudyResource) { guard recentResourceID != resource.id else { return }; recentResourceID = resource.id; UserDefaults.standard.set(resource.id, forKey: "recent-resource") }
    func bookTitle(_ lessonID: String) -> String { bookTitleByLessonID[lessonID] ?? "" }
    func lesson(_ id: String) -> Lesson? { lessonByID[id] }
    func resource(_ id: String?) -> StudyResource? { guard let id = id else { return nil }; return resourceByID[id] }
    func resources(_ id: String) -> [StudyResource] { resourcesByLesson[id] ?? [] }
    func marks(_ id: String) -> [StudyMark] { marksByLesson[id] ?? [] }
    @discardableResult func update(_ change: (inout GardenSnapshot) -> Void) -> Bool {
        guard readable, let disk = disk else { error = "读取异常未解决，暂时不能修改资料。"; return false }
        var copy = data; change(&copy)
        do {
            try disk.save(copy)
            let scheduleChanged = copy.slots != data.slots || copy.changes != data.changes || copy.termStart != data.termStart || copy.termEnd != data.termEnd
            let changed = scheduleChanged || copy.reminderMinutes != data.reminderMinutes || copy.termConfirmed != data.termConfirmed
            if scheduleChanged { rebuildSchedule(copy) }
            data = copy
            reindex()
            if changed { BarkBridge.shared.changed(copy) }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func importResource(_ url: URL, lessonID: String) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let disk = disk, readable else { return }
        do {
            let name = try disk.importFile(url)
            let ext = url.pathExtension.lowercased()
            let kind: ResourceKind = ext == "pdf" ? .pdf : (["mp4","mov","m4v"].contains(ext) ? .localVideo : .guide)
            let text = kind == .guide ? try String(contentsOf: disk.attachmentURL(name), encoding: .utf8) : ""
            let resource = StudyResource(lessonID: lessonID, title: url.deletingPathExtension().lastPathComponent, kind: kind, body: text, localFile: name)
            if !update({ $0.resources.append(resource) }) { try? FileManager.default.removeItem(at: disk.attachmentURL(name)) }
        } catch { self.error = error.localizedDescription }
    }
    func exportBackup() -> URL? {
        guard readable, let disk = disk else { return nil }
        do {
            let bytes = try disk.backup(data)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("欣语-备份.json")
            try bytes.write(to: url, options: .atomic); return url
        } catch { self.error = error.localizedDescription; return nil }
    }
    func restore(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard readable, let disk = disk else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 90 * 1024 * 1024 else { throw GardenError.invalid("备份文件过大。") }
            data = try disk.mergeBackup(Data(contentsOf: url), into: data)
            reindex()
            rebuildSchedule(data)
            BarkBridge.shared.changed(data)
            notice = "已合并资料和笔记。"
        } catch { self.error = error.localizedDescription }
    }
    var occurrences: [Occurrence] { cachedOccurrences }
    func courses(on date: Date) -> [Occurrence] { occurrencesByDate[GardenDate.string(date)] ?? [] }
    /// Rebuilt once per data change, so views never rescan the whole library per row.
    private func reindex() {
        if let books = catalog?.books {
            var lessons: [Lesson] = []
            var byID: [String: Lesson] = [:]
            var titles: [String: String] = [:]
            for book in books {
                for unit in book.units {
                    for lesson in unit.lessons {
                        lessons.append(lesson)
                        byID[lesson.id] = lesson
                        titles[lesson.id] = book.title
                    }
                }
            }
            allLessons = lessons
            lessonByID = byID
            bookTitleByLessonID = titles
        }
        var grouped: [String: [StudyResource]] = [:]
        var resourcesByID: [String: StudyResource] = [:]
        for resource in data.resources {
            grouped[resource.lessonID, default: []].append(resource)
            resourcesByID[resource.id] = resource
        }
        for key in Array(grouped.keys) {
            var list = grouped[key] ?? []
            list.sort { !$0.isPaid && $1.isPaid }
            grouped[key] = list
        }
        resourcesByLesson = grouped
        resourceByID = resourcesByID
        var notes: [String: [StudyMark]] = [:]
        for mark in data.marks { notes[mark.lessonID, default: []].append(mark) }
        for key in Array(notes.keys) {
            var list = notes[key] ?? []
            list.sort { $0.createdAt > $1.createdAt }
            notes[key] = list
        }
        marksByLesson = notes
    }
    private func rebuildSchedule(_ snapshot: GardenSnapshot) {
        cachedOccurrences = ScheduleEngine().occurrences(slots: snapshot.slots, changes: snapshot.changes, start: snapshot.termStart, end: snapshot.termEnd)
        occurrencesByDate = Dictionary(grouping: cachedOccurrences, by: \.date)
    }
}
