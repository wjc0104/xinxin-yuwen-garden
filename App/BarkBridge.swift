import Foundation
import Combine
import Security
import GardenCore

private struct BarkProfile: Codable {
    var address = ""
    var service = ""
    var token = ""
    var enabled = false
}
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
@MainActor final class BarkBridge: ObservableObject {
    static let shared = BarkBridge()
    @Published private(set) var enabled = false
    @Published private(set) var status = "尚未设置接收手机"
    @Published private(set) var busy = false
    private var profile = BarkProfile()
    private var pending: Task<Void, Never>?
    private let serviceName = "com.wm0104.xinxingarden.bark"
    private let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
    var address: String { profile.address }
    var connectionLink: String { profile.service.isEmpty ? "" : profile.service + "#" + profile.token }
    init() {
        var found: CFTypeRef?
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:serviceName,kSecAttrAccount as String:"profile",kSecReturnData as String:true]
        if SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let data = found as? Data, let saved = try? JSONDecoder().decode(BarkProfile.self, from: data) { profile = saved; enabled = saved.enabled; status = enabled ? "自动提醒已设置，正在核对课表" : "已保存接收手机；自动提醒未启用" }
    }
    func save(address: String, connection: String) throws {
        guard !enabled else { throw GardenError.invalid("请先停用自动提醒，再更换接收手机。") }
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = try parseAddress(address)
        guard parsed.key.count >= 6 else { throw GardenError.invalid("请粘贴 Bark 首页的完整推送地址。") }
        var next = BarkProfile(); next.address = address
        let connection = connection.trimmingCharacters(in: .whitespacesAndNewlines)
        if !connection.isEmpty {
            guard var parts = URLComponents(string: connection), parts.scheme == "https", parts.host != nil, parts.user == nil, parts.password == nil, parts.query == nil,
                  let token = parts.fragment, token.count >= 32, token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { throw GardenError.invalid("服务连接格式不正确，请粘贴部署后生成的完整连接。") }
            parts.fragment = nil
            next.service = parts.string!.trimmingCharacters(in: CharacterSet(charactersIn: "/")); next.token = token
        }
        try persist(next); status = "已保存接收手机；自动提醒未启用"
    }
    func test() async throws {
        let parsed = try parseAddress(profile.address)
        busy = true; defer { busy = false }
        _ = try await request(parsed.endpoint, body: ["device_key":parsed.key,"title":"欣语提醒测试","body":"看到这条消息，就说明这台手机可以接收上课提醒。","group":"欣语上课提醒","sound":"bell","level":"timeSensitive"])
        status = "测试请求已发送，请查看 iPhone 16"
    }
    func enable(_ snapshot: GardenSnapshot) async throws {
        guard snapshot.termConfirmed else { throw GardenError.invalid("请先在学期设置中确认开学和结束日期。") }
        guard !profile.service.isEmpty else { throw GardenError.invalid("尚未连接定时服务。测试通知可以使用，但自动上课提醒还没有启用。") }
        try await upload(snapshot)
        var next = profile; next.enabled = true; try persist(next)
    }
    func stop() async throws {
        pending?.cancel()
        guard !profile.service.isEmpty else { return }
        busy = true; defer { busy = false }
        _ = try await request(serviceURL(), method: "DELETE", body: ["revision":nextRevision()], token: profile.token)
        var next = profile; next.enabled = false; try persist(next); status = "自动提醒已停用"
    }
    func changed(_ snapshot: GardenSnapshot) {
        guard enabled else { return }
        pending?.cancel(); status = "课表有变化，正在更新提醒"
        pending = Task {
            do { try await Task.sleep(nanoseconds: 350_000_000); try Task.checkCancellation(); try await upload(snapshot) }
            catch is CancellationError { }
            catch { if !Task.isCancelled { status = "提醒尚未更新，请联网后点“更新提醒”" } }
        }
    }
    func refresh(_ snapshot: GardenSnapshot) async throws { try await upload(snapshot) }
    private func upload(_ snapshot: GardenSnapshot) async throws {
        guard snapshot.termConfirmed else { throw GardenError.invalid("学期未确认，未更新提醒。") }
        let parsed = try parseAddress(profile.address)
        // Hosted scheduler deliberately sends only to Bark's official HTTPS endpoint.
        guard parsed.endpoint.host == "api.day.app" else { throw GardenError.invalid("自动定时服务目前支持 api.day.app；自建 Bark 地址仍可测试发送。") }
        let jobs = ReminderPlan.build(ScheduleEngine().occurrences(slots: snapshot.slots, changes: snapshot.changes, start: snapshot.termStart, end: snapshot.termEnd), minutes: snapshot.reminderMinutes)
        let revision = nextRevision()
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(jobs))
        busy = true; defer { busy = false }
        _ = try await request(serviceURL(), method: "PUT", body: ["revision":revision,"deviceKey":parsed.key,"jobs":encoded], token: profile.token)
        status = "已安排 \(jobs.count) 次提醒 · 提前\(snapshot.reminderMinutes)分钟"
    }
    private func serviceURL() throws -> URL {
        guard let url = URL(string: profile.service + "/schedule"), url.scheme == "https", !profile.token.isEmpty else { throw GardenError.invalid("请先连接在线定时服务。") }
        return url
    }
    private func nextRevision() -> Int64 {
        let value = max(Int64(Date().timeIntervalSince1970 * 1000), Int64(UserDefaults.standard.double(forKey: "bark-revision")) + 1)
        UserDefaults.standard.set(Double(value), forKey: "bark-revision")
        return value
    }
    private func parseAddress(_ text: String) throws -> (endpoint: URL, key: String) {
        guard let url = SearchEngine.validatedURL(text), url.scheme == "https", url.query == nil, url.fragment == nil,
              let host = url.host, !host.isEmpty else { throw GardenError.invalid("请填写 Bark 首页的 HTTPS 推送地址。") }
        let segments = url.pathComponents.filter { $0 != "/" }
        guard segments.count == 1, let key = segments.first, key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { throw GardenError.invalid("地址只需包含服务器和设备密钥，不要附带测试消息。") }
        return (url.deletingLastPathComponent().appendingPathComponent("push"), key)
    }
    private func request(_ url: URL, method: String = "POST", body: [String: Any]?, token: String? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let body = body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], (json["code"] as? Int) == 200 else { throw GardenError.invalid("服务没有确认成功。请检查连接和网络后重试。") }
        return json
    }
    private func persist(_ next: BarkProfile) throws {
        let bytes = try JSONEncoder().encode(next)
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:serviceName,kSecAttrAccount as String:"profile"]
        var result = SecItemUpdate(query as CFDictionary, [kSecValueData as String:bytes] as CFDictionary)
        if result == errSecItemNotFound { var insert = query; insert[kSecValueData as String] = bytes; insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly; result = SecItemAdd(insert as CFDictionary, nil) }
        guard result == errSecSuccess else { throw GardenError.invalid("无法安全保存提醒配置。") }
        profile = next; enabled = next.enabled
    }
}
