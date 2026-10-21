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
                data.resources.removeAll { retired.contains($0.id) && !annotated.contains($0.id) }
                data.resources = StudyLibrary.merge(bundled, into: data.resources)
                if !UserDefaults.standard.bool(forKey: "reminder-v002") { data.reminderMinutes = 60 }
                try store.save(data)
                UserDefaults.standard.set(true, forKey: "reminder-v002")
            }
            readable = true
            rebuildSchedule(data)
            if ProcessInfo.processInfo.arguments.contains("--ui-testing"), !data.resources.contains(where: { $0.id == "ui-pdf" }) {
                let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
                let bytes = renderer.pdfData { context in context.beginPage(); ("PDF Garden Focus" as NSString).draw(at: CGPoint(x: 60, y: 120), withAttributes: [.font: UIFont.systemFont(ofSize: 26)]) }
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Garden-UI-Fixture.pdf")
                try bytes.write(to: temporary, options: .atomic)
                let name = try store.importFile(temporary)
                data.resources.append(StudyResource(id: "ui-pdf", lessonID: "7u-01", title: "原创测试 PDF", kind: .pdf, localFile: name))
                try store.save(data)
            }
        } catch { self.error = "暂时无法读取资料，已停止保存以保护原数据。\n" + error.localizedDescription }
    }
    var lessons: [Lesson] { catalog?.books.flatMap { $0.units.flatMap(\.lessons) } ?? [] }
    func remember(_ resource: StudyResource) { guard recentResourceID != resource.id else { return }; recentResourceID = resource.id; UserDefaults.standard.set(resource.id, forKey: "recent-resource") }
    func bookTitle(_ lessonID: String) -> String { catalog?.books.first { $0.units.contains { $0.lessons.contains { $0.id == lessonID } } }?.title ?? "" }
    func lesson(_ id: String) -> Lesson? { lessons.first { $0.id == id } }
    func resources(_ id: String) -> [StudyResource] { data.resources.filter { $0.lessonID == id }.sorted { !$0.isPaid && $1.isPaid } }
    func marks(_ id: String) -> [StudyMark] { data.marks.filter { $0.lessonID == id }.sorted { $0.createdAt > $1.createdAt } }
    @discardableResult func update(_ change: (inout GardenSnapshot) -> Void) -> Bool {
        guard readable, let disk = disk else { error = "读取异常未解决，暂时不能修改资料。"; return false }
        var copy = data; change(&copy)
        do {
            try disk.save(copy)
            let scheduleChanged = copy.slots != data.slots || copy.changes != data.changes || copy.termStart != data.termStart || copy.termEnd != data.termEnd
            let changed = scheduleChanged || copy.reminderMinutes != data.reminderMinutes || copy.termConfirmed != data.termConfirmed
            if scheduleChanged { rebuildSchedule(copy) }
            data = copy
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
            rebuildSchedule(data)
            BarkBridge.shared.changed(data)
            notice = "已合并资料和笔记。"
        } catch { self.error = error.localizedDescription }
    }
    var occurrences: [Occurrence] { cachedOccurrences }
    func courses(on date: Date) -> [Occurrence] { occurrencesByDate[GardenDate.string(date)] ?? [] }
    private func rebuildSchedule(_ snapshot: GardenSnapshot) {
        cachedOccurrences = ScheduleEngine().occurrences(slots: snapshot.slots, changes: snapshot.changes, start: snapshot.termStart, end: snapshot.termEnd)
        occurrencesByDate = Dictionary(grouping: cachedOccurrences, by: \.date)
    }
}
