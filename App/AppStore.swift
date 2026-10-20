import SwiftUI
import GardenCore

@MainActor final class AppStore: ObservableObject {
    @Published private(set) var data = GardenSnapshot()
    @Published var error: String?
    @Published var notice: String?
    @Published var tab = 0
    private(set) var catalog: Catalog?
    private(set) var disk: DiskStore?
    private(set) var readable = false
    let calendar = CalendarBridge()

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
                if let url = Bundle.main.url(forResource: "seed-resources", withExtension: "json") { initial.resources = try JSONDecoder().decode([StudyResource].self, from: Data(contentsOf: url)) }
                try store.save(initial); data = initial
            }
            readable = true
        } catch { self.error = "小花园暂时无法读取资料，已停止保存以保护原数据。\n" + error.localizedDescription }
    }
    var lessons: [Lesson] { catalog?.books.flatMap { $0.units.flatMap(\.lessons) } ?? [] }
    func lesson(_ id: String) -> Lesson? { lessons.first { $0.id == id } }
    func resources(_ id: String) -> [StudyResource] { data.resources.filter { $0.lessonID == id }.sorted { !$0.isPaid && $1.isPaid } }
    func marks(_ id: String) -> [StudyMark] { data.marks.filter { $0.lessonID == id }.sorted { $0.createdAt > $1.createdAt } }
    @discardableResult func update(_ change: (inout GardenSnapshot) -> Void) -> Bool {
        guard readable, let disk = disk else { error = "读取异常未解决，暂时不能修改资料。"; return false }
        var copy = data; change(&copy)
        do { try disk.save(copy); data = copy; return true } catch { self.error = error.localizedDescription; return false }
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
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("欣欣的小花园-备份.json")
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
            notice = "已合并资料和小重点；相同编号保留本机内容。学期与日历绑定保持本机设置。"
        } catch { self.error = error.localizedDescription }
    }
    var occurrences: [Occurrence] { ScheduleEngine().occurrences(slots: data.slots, changes: data.changes, start: data.termStart, end: data.termEnd) }
}
