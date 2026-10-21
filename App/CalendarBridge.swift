import Foundation
import Combine
import EventKit
import GardenCore

private struct EventLink: Codable { var eventID: String; var fingerprint: String; var dates: [Date]?; var pending: Bool? }
private struct CalendarBinding: Codable { var calendarID: String; var nonce: String; var events: [String: EventLink] = [:] }

/// Compatibility reader/remover only. New versions never create calendars or events.
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
            else if let data = UserDefaults.standard.data(forKey: key) {
                binding = try JSONDecoder().decode(CalendarBinding.self, from: data)
                try data.write(to: url, options: [.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            }
        } catch { bindingError = "无法读取旧版日历绑定，未修改日历：" + error.localizedDescription }
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
    func removeLegacyEvents() throws -> Int {
        if let error = bindingError { throw GardenError.invalid(error) }
        guard isAuthorized, let saved = binding else { throw GardenError.invalid("没有可清除的旧版绑定。") }
        guard let calendar = store.calendar(withIdentifier: saved.calendarID) else { return 0 }
        guard calendar.allowsContentModifications else { throw GardenError.invalid("旧日历不可修改，请在系统日历手动关闭该日历的提醒。") }
        let prefix = "xinxingarden://event/" + saved.nonce + "/"
        func owned(_ event: EKEvent) -> Bool {
            guard event.calendar.calendarIdentifier == saved.calendarID, let raw = event.url?.absoluteString,
                  raw.hasPrefix(prefix), let id = String(raw.dropFirst(prefix.count)).removingPercentEncoding else { return false }
            return raw == prefix + id.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        }
        var events: [String: EKEvent] = [:]
        for link in saved.events.values {
            if let event = store.event(withIdentifier: link.eventID), owned(event), let id = event.eventIdentifier { events[id] = event }
        }
        // Event identifiers can change after iCloud sync. Search the owned calendar by nonce across the old
        // school term plus a year either side, including the current year. Retain recovery data for future scans.
        let anchors = saved.events.values.flatMap { $0.dates ?? [] } + [Date()]
        if let first = anchors.min(), let last = anchors.max() {
            var begin = first.addingTimeInterval(-366*86400)
            let limit = last.addingTimeInterval(366*86400)
            while begin < limit {
                let finish = min(limit, begin.addingTimeInterval(365*86400))
                let predicate = store.predicateForEvents(withStart: begin, end: finish, calendars: [calendar])
                for event in store.events(matching: predicate) where owned(event) {
                    if let id = event.eventIdentifier { events[id] = event }
                }
                begin = finish
            }
        }
        do {
            for event in events.values { try store.remove(event, span: .thisEvent, commit: false) }
            try store.commit()
            // Keep the nonce/journal: remote events may arrive later and can safely be scanned again.
            return events.count
        } catch { store.reset(); throw error }
    }
}
