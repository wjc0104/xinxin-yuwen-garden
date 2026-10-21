import Foundation

public enum GardenError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let value): return value } }
}
private struct BackupEnvelope: Codable {
    var format = "xinxin-garden"
    var version = 1
    var snapshot: GardenSnapshot
    var attachments: [String: Data]
}

public final class DiskStore {
    public let root: URL
    private var stateURL: URL { root.appendingPathComponent("garden.json") }
    private var attachments: URL { root.appendingPathComponent("Attachments", isDirectory: true) }
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
    }
    public func save(_ value: GardenSnapshot) throws {
        try validate(value)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: stateURL, options: .atomic)
    }
    public func load() throws -> GardenSnapshot? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return nil }
        let value = try JSONDecoder().decode(GardenSnapshot.self, from: Data(contentsOf: stateURL))
        try validate(value)
        return value
    }
    public func attachmentURL(_ name: String) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains(":"), !name.contains("\0") else { throw GardenError.invalid("资料文件名不安全，请重新选择文件。") }
        let url = attachments.appendingPathComponent(name)
        if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true { throw GardenError.invalid("不支持链接文件。") }
        return url
    }
    public func importFile(_ source: URL) throws -> String {
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 40 * 1024 * 1024 else { throw GardenError.invalid("首版单个本地资料限 40 MB，大视频可以保存原链接。") }
        let ext = source.pathExtension.lowercased()
        guard ["pdf", "txt", "md", "mp4", "mov", "m4v"].contains(ext) else { throw GardenError.invalid("支持 PDF、TXT、Markdown 和 MP4/MOV 视频。") }
        let name = UUID().uuidString + "." + ext
        let destination = try attachmentURL(name)
        try FileManager.default.copyItem(at: source, to: destination)
        return name
    }
    public func backup(_ value: GardenSnapshot) throws -> Data {
        try validate(value)
        var files: [String: Data] = [:]
        var bytes = 0
        for name in Set(value.resources.map(\.localFile).filter { !$0.isEmpty }) {
            let url = try attachmentURL(name)
            let data = try Data(contentsOf: url)
            bytes += data.count
            guard bytes <= 60 * 1024 * 1024 else { throw GardenError.invalid("资料附件超过 60 MB，首版请分别保存大文件，再备份笔记。") }
            files[name] = data
        }
        return try JSONEncoder().encode(BackupEnvelope(snapshot: value, attachments: files))
    }
    public func mergeBackup(_ data: Data, into current: GardenSnapshot) throws -> GardenSnapshot {
        guard data.count <= 90 * 1024 * 1024 else { throw GardenError.invalid("备份文件过大。") }
        let backup = try JSONDecoder().decode(BackupEnvelope.self, from: data)
        guard backup.format == "xinxin-garden", backup.version == 1 else { throw GardenError.invalid("这不是受支持的欣语备份。") }
        try validate(backup.snapshot)
        var incoming = backup.snapshot
        // Rename restored attachments, so a backup cannot replace a current file with the same name.
        var renamed: [String: String] = [:]
        for resource in incoming.resources where !resource.localFile.isEmpty {
            let old = resource.localFile
            _ = try attachmentURL(old)
            guard let file = backup.attachments[old], file.count <= 40 * 1024 * 1024 else { throw GardenError.invalid("备份缺少附件，或附件过大，未更改现有笔记。") }
            if renamed[old] == nil { renamed[old] = UUID().uuidString + "." + URL(fileURLWithPath: old).pathExtension }
        }
        for name in backup.attachments.keys { _ = try attachmentURL(name) }
        for index in incoming.resources.indices { if let name = renamed[incoming.resources[index].localFile] { incoming.resources[index].localFile = name } }
        var result = current
        result.resources += incoming.resources.filter { value in !current.resources.contains { $0.id == value.id } }
        result.marks += incoming.marks.filter { value in !current.marks.contains { $0.id == value.id } }
        result.favorites.formUnion(incoming.favorites)
        result.changes += incoming.changes.filter { value in !current.changes.contains { $0.id == value.id } }
        // Term settings, current timetable and calendar bindings stay device-local/current.
        try validate(result)
        var written: [URL] = []
        do {
            for (old, new) in renamed { let destination = try attachmentURL(new); try backup.attachments[old]!.write(to: destination, options: .atomic); written.append(destination) }
            try save(result)
        } catch { for url in written { try? FileManager.default.removeItem(at: url) }; throw error }
        return result
    }
    private func validate(_ value: GardenSnapshot) throws {
        guard value.schemaVersion == 1, value.resources.count <= 5000, value.marks.count <= 30000, value.changes.count <= 5000,
              Set(value.resources.map(\.id)).count == value.resources.count, Set(value.marks.map(\.id)).count == value.marks.count,
              Set(value.changes.map(\.id)).count == value.changes.count,
              GardenDate.parse(value.termStart) != nil, GardenDate.parse(value.termEnd) != nil,
              value.termStart <= value.termEnd, (0...60).contains(value.reminderMinutes) else { throw GardenError.invalid("资料或备份格式不正确，原文件保持不变。") }
        for resource in value.resources {
            if !resource.localFile.isEmpty { _ = try attachmentURL(resource.localFile) }
            if !resource.url.isEmpty && SearchEngine.validatedURL(resource.url) == nil { throw GardenError.invalid("资料包含不支持的链接。") }
        }
        for slot in value.slots {
            guard (1...7).contains(slot.weekday), slot.startMinute >= 0, slot.endMinute < 1440, slot.endMinute > slot.startMinute else { throw GardenError.invalid("课表时间不正确。") }
        }
        guard Set(value.slots.map(\.id)).count == value.slots.count else { throw GardenError.invalid("课表编号重复。") }
        for change in value.changes {
            guard let slot = value.slots.first(where: { $0.id == change.slotID }), let anchor = GardenDate.parse(change.date) else { throw GardenError.invalid("调课记录包含无效课次或日期，未导入备份。") }
            let begin = change.startMinute ?? slot.startMinute, finish = change.endMinute ?? slot.endMinute
            guard begin >= 0, finish < 1440, begin < finish else { throw GardenError.invalid("调课记录的开始／结束时间不正确，未导入备份。") }
            if let target = change.targetDate {
                guard let targetDate = GardenDate.parse(target) else { throw GardenError.invalid("调课目标日期不正确。") }
                if change.scope == .fromDate {
                    let shift = GardenDate.calendar.dateComponents([.day], from: anchor, to: targetDate).day ?? 999
                    guard abs(shift) <= 6 else { throw GardenError.invalid("长期调课的星期位移超出范围，未导入备份。") }
                }
            }
        }
        for mark in value.marks {
            if let seconds = mark.seconds, !(0...86400).contains(seconds) { throw GardenError.invalid("视频时间标记不正确。") }
        }
    }
}
