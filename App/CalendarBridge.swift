import Foundation
import EventKit
import UIKit
import GardenCore

struct CalendarAccount: Identifiable { let id: String; let title: String; let supportsRemote: Bool }
private struct EventLink: Codable { var eventID: String; var fingerprint: String }
private struct CalendarBinding: Codable { var calendarID: String; var nonce: String; var events: [String: EventLink] = [:] }
struct CalendarReview: Error { let messages: [String]; let proposals: [ScheduleChange] }

@MainActor final class CalendarBridge: ObservableObject {
    private let store = EKEventStore()
    private let key = "garden.calendar.binding.v1"
    private var binding: CalendarBinding?
    init() {
        if let data = UserDefaults.standard.data(forKey: key) { binding = try? JSONDecoder().decode(CalendarBinding.self, from: data) }
    }
    var hasBinding: Bool { binding != nil }
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
        guard snapshot.termConfirmed else { throw GardenError.invalid("请先确认本学期起止日期，再生成提醒。") }
        guard isAuthorized else { throw GardenError.invalid("日历权限未开启，未写入提醒。") }
        guard var saved = binding, let calendar = store.calendar(withIdentifier: saved.calendarID), calendar.allowsContentModifications else { throw GardenError.invalid("专用日历已删除或不可写，未写入提醒。请在系统日历恢复后再试，或在“我的”解除失效绑定。") }
        let occurrences = ScheduleEngine().occurrences(slots: snapshot.slots, changes: snapshot.changes, start: snapshot.termStart, end: snapshot.termEnd)
        guard occurrences.count <= 2000 else { throw GardenError.invalid("学期范围过大，请缩短至当前学期。") }
        var events: [String: EKEvent] = [:]; var review: [String] = []; var proposals: [ScheduleChange] = []
        // Fetch only recorded event identifiers; never enumerate or edit unrelated events.
        for (id, link) in saved.events {
            if let event = store.event(withIdentifier: link.eventID) {
                guard CalendarPolicy.mayEdit(boundCalendar: saved.calendarID, eventCalendar: event.calendar.calendarIdentifier, expectedMarker: marker(id, saved.nonce), actualMarker: event.url?.absoluteString ?? "") else { throw GardenError.invalid("有课程的日历归属或标记已改变，已停止同步以保护日历内容。请先在系统日历检查。") }
                events[id] = event
                if CalendarPolicy.needsReview(previous: link.fingerprint, actual: fingerprint(event)) {
                    review.append("已修改：" + (event.title ?? id) + " · " + GardenDate.string(event.startDate) + " " + TimeLabel.clock(GardenDate.calendar.component(.hour, from: event.startDate) * 60 + GardenDate.calendar.component(.minute, from: event.startDate)))
                    if !event.isAllDay, let change = CalendarPolicy.importChange(occurrenceID: id, start: event.startDate, end: event.endDate) { proposals.append(change) }
                }
            } else { review.append("已删除：" + id); if let change = CalendarPolicy.importChange(occurrenceID: id, start: nil, end: nil) { proposals.append(change) } }
        }
        if !review.isEmpty && !overwriteReviewed { throw CalendarReview(messages: review, proposals: proposals) }
        let wanted = Set(occurrences.map(\.id))
        do {
            for (id, event) in events where !wanted.contains(id) { try store.remove(event, span: .thisEvent, commit: false) }
            var newLinks: [String: EventLink] = [:]
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
                try store.save(event, span: .thisEvent, commit: false)
                newLinks[occurrence.id] = EventLink(eventID: event.eventIdentifier ?? "", fingerprint: fingerprint(event))
                events[occurrence.id] = event
            }
            try store.commit()
            // EventKit may assign final identifiers only at commit.
            for occurrence in occurrences { if let event = events[occurrence.id] { newLinks[occurrence.id] = EventLink(eventID: event.eventIdentifier ?? "", fingerprint: fingerprint(event)) } }
            saved.events = newLinks; binding = saved; try persist()
            return occurrences.count
        } catch { store.reset(); throw error }
    }
    func forgetMissingBinding() throws {
        guard isAuthorized, let binding = binding, store.calendar(withIdentifier: binding.calendarID) == nil else { throw GardenError.invalid("只有专用日历已不存在时才能解除失效绑定；已有日历不会被自动删除。") }
        self.binding = nil; UserDefaults.standard.removeObject(forKey: key)
    }
    private func persist() throws { UserDefaults.standard.set(try JSONEncoder().encode(binding), forKey: key) }
}
