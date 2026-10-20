import Foundation
import EventKit
import UIKit
import GardenCore

struct CalendarAccount: Identifiable { let id: String; let title: String; let supportsRemote: Bool }
private struct EventLink: Codable { var eventID: String; var fingerprint: String; var dates: [Date]?; var pending: Bool? }
private struct CalendarBinding: Codable { var calendarID: String; var nonce: String; var events: [String: EventLink] = [:] }
struct CalendarReview: Error { let messages: [String]; let proposals: [ScheduleChange] }

@MainActor final class CalendarBridge: ObservableObject {
    private let store = EKEventStore()
    private let key = "garden.calendar.binding.v1"
    private var binding: CalendarBinding?
    private var bindingURL: URL?
    private var bindingError: String?
    init() {
        do {
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let folder = ProcessInfo.processInfo.arguments.contains("--ui-testing") ? "GardenUITesting" : "XinxinGarden"
            let root = base.appendingPathComponent(folder, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent("calendar-binding.json"); bindingURL = url
            if FileManager.default.fileExists(atPath: url.path) { binding = try JSONDecoder().decode(CalendarBinding.self, from: Data(contentsOf: url)) }
            else if let data = UserDefaults.standard.data(forKey: key) { binding = try JSONDecoder().decode(CalendarBinding.self, from: data); try persist() }
        } catch { bindingError = "无法读取日历绑定，已停止写入以防重复课程：" + error.localizedDescription }
    }
    var hasBinding: Bool { binding != nil || bindingError != nil }
    var isAuthorized: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) { return status == .fullAccess }
        return status == .authorized
    }
    func requestAccess() async throws {
        let granted: Bool
        if #available(iOS 17.0, *) { granted = try await store.requestFullAccessToEvents() }
        else { granted = try await withCheckedThrowingContinuation { continuation in store.requestAccess(to: .event) { success, error in if let error = error { continuation.resume(throwing: error) } else { continuation.resume(returning: success) } } } }
        guard granted, isAuthorized else { throw GardenError.invalid("没有获得日历权限。资料学习仍可使用；可在系统设置中稍后开启。") }
        store.reset()
    }
    func accounts() throws -> [CalendarAccount] {
        guard isAuthorized else { throw GardenError.invalid("请先允许日历访问。") }
        return store.sources.filter { [.calDAV, .local, .exchange, .mobileMe].contains($0.sourceType) }.map {
            CalendarAccount(id: $0.sourceIdentifier, title: $0.title + ($0.sourceType == .local ? "（仅本机）" : ""), supportsRemote: $0.sourceType != .local)
        }
    }
    func connect(sourceID: String) throws {
        if let error = bindingError { throw GardenError.invalid(error) }
        guard isAuthorized else { throw GardenError.invalid("日历权限已关闭。") }
        guard binding == nil else { throw GardenError.invalid("已有专用日历绑定，请使用现有日历同步。") }
        guard let source = store.sources.first(where: { $0.sourceIdentifier == sourceID }) else { throw GardenError.invalid("该日历账户已不可用。") }
        // Never adopt a calendar by its display title: only the ID returned on creation is owned.
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "欣欣的小花园 · 上课提醒"
        calendar.source = source; calendar.cgColor = UIColor.systemPink.cgColor
        try store.saveCalendar(calendar, commit: true)
        binding = CalendarBinding(calendarID: calendar.calendarIdentifier, nonce: UUID().uuidString)
        try persist()
    }
    func boundTitle() -> String? {
        guard isAuthorized, let binding = binding else { return nil }
        return store.calendar(withIdentifier: binding.calendarID)?.source.title
    }
    private func marker(_ occurrenceID: String, _ nonce: String) -> String {
        "xinxingarden://event/" + nonce + "/" + occurrenceID.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
    }
    private func fingerprint(_ event: EKEvent) -> String {
        let alarms = (event.alarms ?? []).map { String($0.relativeOffset) }.sorted().joined(separator: ",")
        return [event.title ?? "", String(event.startDate.timeIntervalSince1970), String(event.endDate.timeIntervalSince1970), String(event.isAllDay), alarms, event.notes ?? ""].joined(separator: "|")
    }
    func sync(_ snapshot: GardenSnapshot, overwriteReviewed: Bool = false) throws -> Int {
        if let error = bindingError { throw GardenError.invalid(error) }
        guard snapshot.termConfirmed else { throw GardenError.invalid("请先确认本学期起止日期，再生成提醒。") }
        guard isAuthorized else { throw GardenError.invalid("日历权限未开启，未写入提醒。") }
        guard var saved = binding, let calendar = store.calendar(withIdentifier: saved.calendarID), calendar.allowsContentModifications else { throw GardenError.invalid("专用日历已删除或不可写，未写入提醒。请在系统日历恢复后再试，或在“我的”解除失效绑定。") }
        let occurrences = ScheduleEngine().occurrences(slots: snapshot.slots, changes: snapshot.changes, start: snapshot.termStart, end: snapshot.termEnd)
        guard occurrences.count <= 2000 else { throw GardenError.invalid("学期范围过大，请缩短至当前学期。") }
        var events: [String: EKEvent] = [:]; var review: [String] = []; var proposals: [ScheduleChange] = []
        // Reconcile IDs only inside the bound calendar, using our private nonce and canonical occurrence marker.
        // Date windows include the durable pre-commit journal, so a process stop after commit cannot lose new events.
        var candidatesByID: [String: EKEvent] = [:]
        var anchors = occurrences.compactMap { GardenDate.parse($0.date) }
        anchors += saved.events.values.flatMap { $0.dates ?? [] }
        anchors += snapshot.changes.compactMap { $0.targetDate.flatMap(GardenDate.parse) }
        if let first = GardenDate.parse(snapshot.termStart), let last = GardenDate.parse(snapshot.termEnd) { anchors += [first,last] }
        var windows: [(Date,Date)] = []
        if let first = GardenDate.parse(snapshot.termStart), let last = GardenDate.parse(snapshot.termEnd) { windows.append((first.addingTimeInterval(-366*86400),last.addingTimeInterval(366*86400))) }
        windows += anchors.map { ($0.addingTimeInterval(-86400), $0.addingTimeInterval(2*86400)) }
        var merged: [(Date,Date)] = []
        for window in windows.sorted(by: { $0.0 < $1.0 }) {
            if let last = merged.last, window.0 <= last.1 { merged[merged.count-1].1 = max(last.1,window.1) }
            else { merged.append(window) }
        }
        for window in merged {
            var begin = window.0
            while begin < window.1 {
                let finish = min(window.1,begin.addingTimeInterval(365*86400))
                let predicate = store.predicateForEvents(withStart: begin, end: finish, calendars: [calendar])
                for event in store.events(matching: predicate) { if let id = event.eventIdentifier, !id.isEmpty { candidatesByID[id] = event } }
                begin = finish
            }
        }
        // A direct ID outside the recovery windows must still pass calendar + marker ownership checks.
        for (id, link) in saved.events where !link.eventID.isEmpty {
            if let event = store.event(withIdentifier: link.eventID) {
                guard CalendarPolicy.mayEdit(boundCalendar: saved.calendarID, eventCalendar: event.calendar.calendarIdentifier, expectedMarker: marker(id, saved.nonce), actualMarker: event.url?.absoluteString ?? "") else { throw GardenError.invalid("有课程的日历归属或标记已改变，已停止同步以保护日历内容。请先在系统日历检查。") }
                candidatesByID[link.eventID] = event
            }
        }
        let prefix = "xinxingarden://event/" + saved.nonce + "/"
        var known = Set(saved.events.keys).union(occurrences.map(\.id))
        for event in candidatesByID.values {
            guard let url = event.url?.absoluteString, url.hasPrefix(prefix), let id = String(url.dropFirst(prefix.count)).removingPercentEncoding, marker(id,saved.nonce) == url else { continue }
            let parts = id.split(separator: "@")
            if parts.count == 2, GardenDate.parse(String(parts[1])) != nil { known.insert(id) }
        }
        let candidates = candidatesByID.map { CalendarCandidate(id: $0.key, calendarID: $0.value.calendar.calendarIdentifier, marker: $0.value.url?.absoluteString ?? "") }
        for id in known {
            let recovered = try CalendarPolicy.recover(calendarID: saved.calendarID, marker: marker(id,saved.nonce), candidates: candidates)
            let link = saved.events[id]
            if let recovered = recovered, let event = candidatesByID[recovered] {
                events[id] = event
                if let link = link, CalendarPolicy.needsReview(previous: link.fingerprint, actual: fingerprint(event)) {
                    review.append("已修改：" + (event.title ?? id) + " · " + GardenDate.string(event.startDate) + " " + TimeLabel.clock(GardenDate.calendar.component(.hour, from: event.startDate) * 60 + GardenDate.calendar.component(.minute, from: event.startDate)))
                    if !event.isAllDay, let change = CalendarPolicy.importChange(occurrenceID: id, start: event.startDate, end: event.endDate) { proposals.append(change) }
                }
            } else if let link = link, link.pending != true { review.append("已删除或无法定位（请核对）：" + id); if let change = CalendarPolicy.importChange(occurrenceID: id, start: nil, end: nil) { proposals.append(change) } }
        }
        if !review.isEmpty && !overwriteReviewed { throw CalendarReview(messages: review, proposals: proposals) }
        let wanted = Set(occurrences.map(\.id))
        do {
            var newLinks: [String: EventLink] = [:]
            var prepared: [String: EKEvent] = [:]
            var journal = saved
            for occurrence in occurrences {
                guard let start = GardenDate.at(occurrence.date, minute: occurrence.startMinute), let end = GardenDate.at(occurrence.date, minute: occurrence.endMinute) else { continue }
                let event = events[occurrence.id] ?? EKEvent(eventStore: store)
                event.calendar = calendar
                event.title = "\(occurrence.subject) · \(occurrence.classNumber)班 · 第\(occurrence.period)节"
                event.startDate = start; event.endDate = end; event.isAllDay = false
                event.timeZone = TimeZone(identifier: "Asia/Shanghai")
                event.notes = "欣欣的小花园 🌷\n临时调课请在小花园修改后点按同步。作文两节之间保留休息。"
                event.url = URL(string: marker(occurrence.id, saved.nonce))
                event.alarms = [EKAlarm(relativeOffset: -Double(snapshot.reminderMinutes * 60))]
                let dates = [start,end]
                newLinks[occurrence.id] = EventLink(eventID: event.eventIdentifier ?? "", fingerprint: fingerprint(event), dates: dates, pending: nil)
                if var link = journal.events[occurrence.id] { link.dates = (link.dates ?? []) + dates; journal.events[occurrence.id] = link }
                else { journal.events[occurrence.id] = EventLink(eventID: event.eventIdentifier ?? "", fingerprint: fingerprint(event), dates: dates, pending: true) }
                prepared[occurrence.id] = event
            }
            // Atomic write-ahead recovery data is durable before any EventKit commit.
            binding = journal; try persist()
            for (id, event) in events where !wanted.contains(id) { try store.remove(event, span: .thisEvent, commit: false) }
            for event in prepared.values { try store.save(event, span: .thisEvent, commit: false) }
            try store.commit()
            // EventKit may assign final identifiers only at commit.
            for occurrence in occurrences {
                guard let event = prepared[occurrence.id], let id = event.eventIdentifier, !id.isEmpty else { throw GardenError.invalid("日历已提交，但系统尚未返回有效编号；恢复信息已保留，请稍后重新同步。") }
                newLinks[occurrence.id] = EventLink(eventID: id, fingerprint: fingerprint(event), dates: [event.startDate,event.endDate], pending: nil)
            }
            saved.events = newLinks; binding = saved; try persist()
            return occurrences.count
        } catch { store.reset(); throw error }
    }
    func forgetMissingBinding() throws {
        guard isAuthorized, let binding = binding, store.calendar(withIdentifier: binding.calendarID) == nil else { throw GardenError.invalid("只有专用日历已不存在时才能解除失效绑定；已有日历不会被自动删除。") }
        if let url = bindingURL, FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        self.binding = nil; UserDefaults.standard.removeObject(forKey: key)
    }
    private func persist() throws {
        guard let url = bindingURL else { throw GardenError.invalid("日历绑定文件不可用，未开始写入。") }
        try JSONEncoder().encode(binding).write(to: url, options: [.atomic,.completeFileProtectionUntilFirstUserAuthentication])
    }
}
