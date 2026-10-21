import Foundation
import Combine
import GardenCore

struct LessonRefreshResult {
    var resources: [StudyResource] = []
    var failures: [String] = []
    var completedSearches = 0
}

/// Public metadata only; no credentials, scraping, article bodies or media downloads.
final class LessonContentService {
    private let session: URLSession
    init(session: URLSession? = nil) {
        if let session = session { self.session = session; return }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: config)
    }
    private func data(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
        let (bytes, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GardenError.invalid("原站没有返回响应。") }
        guard response.statusCode == 200 else {
            print("LESSON_REFRESH_HTTP \(response.statusCode) \(url.path)")
            throw GardenError.invalid("原站请求失败（HTTP \(response.statusCode)）。")
        }
        guard bytes.count <= 4 * 1024 * 1024 else { throw GardenError.invalid("原站返回的信息过大。") }
        return bytes
    }
    private func searchURL(type: String, keyword: String, order: String) -> URL {
        var url = URLComponents(string: "https://api.bilibili.com/x/web-interface/search/type")!
        url.queryItems = [URLQueryItem(name: "search_type", value: type), URLQueryItem(name: "keyword", value: keyword), URLQueryItem(name: "order", value: order), URLQueryItem(name: "page", value: "1")]
        return url.url!
    }
    func refresh(_ lesson: Lesson) async throws -> LessonRefreshResult {
        var result = LessonRefreshResult(), videos: [LessonVideoCandidate] = []
        let date = ISO8601DateFormatter().string(from: Date())
        // Keep discovery broad enough for titles without author names; validate author/context locally.
        let keyword = (LessonContent.keys(lesson).first ?? lesson.title) + " 语文"
        for (type, order, label) in [("video", "totalrank", "相关视频"), ("article", "totalrank", "文字资料"), ("video", "pubdate", "最新视频")] {
            try Task.checkCancellation()
            do {
                let bytes = try await data(searchURL(type: type, keyword: keyword, order: order))
                if type == "video" {
                    let candidates = try LessonContent.videos(bytes)
                    let ordered = candidates.filter { LessonContent.matches($0.title, lesson: lesson, context: $0.author) } + candidates.filter { !LessonContent.matches($0.title, lesson: lesson, context: $0.author) }
                    // Reserve validation space for both relevant and latest results.
                    videos += ordered.prefix(4)
                }
                else { result.resources += try LessonContent.articles(bytes, lesson: lesson, checkedAt: date) }
                result.completedSearches += 1
            } catch is CancellationError { throw CancellationError() }
            catch { result.failures.append(label + "：" + error.localizedDescription) }
        }
        var seen = Set<String>()
        // At most 8 extra API requests per refresh; sequential validation bounds concurrency to 1.
        let candidates = videos.filter { seen.insert($0.bvid).inserted }.prefix(8)
        for candidate in candidates {
            try Task.checkCancellation()
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
                let reference = try BilibiliPlayback.reference("https://www.bilibili.com/video/" + candidate.bvid)
                let parts = try BilibiliPlayback.parts(try await data(reference.partListURL))
                result.resources += LessonContent.resources(candidate, parts: parts, lesson: lesson, checkedAt: date)
            } catch is CancellationError { throw CancellationError() }
            catch { result.failures.append("部分视频分集未能核对：" + error.localizedDescription) }
        }
        return result
    }
}

@MainActor final class LessonRefresh: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var hasFailure = false
    @Published private(set) var newIDs = Set<String>()
    private let service: LessonContentService
    init(service: LessonContentService = LessonContentService()) { self.service = service }
    func refresh(_ lesson: Lesson, store: AppStore) async {
        guard !busy else { return }
        busy = true; message = "正在查找本课视频与公开文字…"; hasFailure = false; newIDs = []
        defer { busy = false }
        do {
            let result = try await service.refresh(lesson)
            try Task.checkCancellation()
            let merged = LessonContent.merge(result.resources, into: store.data.resources)
            if merged.resources != store.data.resources {
                guard store.update({ $0.resources = merged.resources }) else { message = "保存失败，原有资料和笔记已保留。"; hasFailure = true; return }
            }
            newIDs = merged.addedIDs
            hasFailure = !result.failures.isEmpty
            let count = merged.addedIDs.count
            if hasFailure {
                message = (result.completedSearches == 0 ? "刷新失败，已有资料和笔记已保留。\n" : "部分完成，新增 \(count) 份。\n") + Array(Set(result.failures)).sorted().joined(separator: "\n")
            } else { message = count == 0 ? "本次没有找到新增资料，已有资料和笔记已保留。" : "已新增 \(count) 份本课资料。" }
        } catch is CancellationError { message = "刷新已取消，已有资料和笔记已保留。" }
        catch { hasFailure = true; message = "刷新失败，已有资料和笔记已保留。\n" + error.localizedDescription }
    }
}
