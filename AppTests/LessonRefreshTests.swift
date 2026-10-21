import XCTest
@testable import XinxinGarden
import GardenCore

private final class LessonMetadataProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else { return }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor final class LessonRefreshTests: XCTestCase {
    private func service() -> LessonContentService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LessonMetadataProtocol.self]
        return LessonContentService(session: URLSession(configuration: config))
    }
    func testRealEndpointPlanRetainsVideoWhenArticleSourceBlocked() async throws {
        var requested = [URL]()
        LessonMetadataProtocol.handler = { request in
            requested.append(request.url!)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), "https://www.bilibili.com/")
            if request.url!.path == "/x/player/pagelist" {
                return (200, #"{"code":0,"data":[{"page":45,"cid":29807281516,"part":"朝天子·咏喇叭","duration":600}]}"#)
            }
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            if query.contains(where: { $0.name == "search_type" && $0.value == "article" }) { return (412, "blocked") }
            return (200, #"{"code":0,"data":{"result":[{"bvid":"BV137LizrE4S","title":"语文合集","author":"老师","duration":"10:00"}]}}"#)
        }
        defer { LessonMetadataProtocol.handler = nil }
        let result = try await service().refresh(Lesson(id: "9d-extra6-4", number: 0, title: "朝天子·咏喇叭", author: "王磐"))
        XCTAssertEqual(result.resources.count, 1)
        XCTAssertEqual(result.resources[0].videoCID, 29807281516)
        XCTAssertTrue(result.failures.contains { $0.contains("文字资料") && $0.contains("412") })
        XCTAssertEqual(requested.filter { $0.path == "/x/player/pagelist" }.count, 1, "Duplicate BVs should be validated once")
        XCTAssertEqual(requested.filter { $0.query?.contains("order=pubdate") == true }.count, 1)
        XCTAssertEqual(requested.filter { $0.query?.contains("order=totalrank") == true }.count, 2)
    }
    func testAnthologyQueriesBothWorksAndAcceptsConstituentArticleAndPart() async throws {
        var keywords = [String](), partRequests = 0
        LessonMetadataProtocol.handler = { request in
            if request.url!.path == "/x/player/pagelist" {
                partRequests += 1
                return (200, #"{"code":0,"data":[{"page":1,"cid":12,"part":"庄子与惠子游于濠梁之上","duration":600},{"page":2,"cid":13,"part":"无关合集","duration":600}]}"#)
            }
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let keyword = query.first { $0.name == "keyword" }!.value!
            keywords.append(keyword)
            if keyword == "北冥有鱼 语文" { return (200, #"{"code":0,"data":{"result":[]}}"#) }
            if query.contains(where: { $0.name == "search_type" && $0.value == "article" }) {
                return (200, #"{"code":0,"data":{"result":[{"id":123,"title":"庄子与惠子游于濠梁之上教学设计","author":"老师"}]}}"#)
            }
            return (200, #"{"code":0,"data":{"result":[{"bvid":"BV137LizrE4S","title":"初中语文全册合集","author":"老师"}]}}"#)
        }
        defer { LessonMetadataProtocol.handler = nil }
        let lesson = Lesson(id: "8d-21", number: 21, title: "《庄子》二则", focus: ["北冥有鱼", "庄子与惠子游于濠梁之上"])
        let result = try await service().refresh(lesson)
        XCTAssertEqual(keywords.filter { $0 == "北冥有鱼 语文" }.count, 3)
        XCTAssertEqual(keywords.filter { $0 == "庄子与惠子游于濠梁之上 语文" }.count, 3)
        XCTAssertEqual(keywords.count, 6)
        XCTAssertEqual(partRequests, 1)
        XCTAssertEqual(result.resources.filter { $0.kind == .video }.map(\.videoCID), [12])
        XCTAssertEqual(result.resources.filter { $0.kind == .link }.map(\.id), ["live-8d-21-cv123"])
        XCTAssertTrue(result.failures.isEmpty)
    }
    func testEmptyAndFailedRefreshNeverWipesExistingResourcesOrNotes() async {
        let store = AppStore()
        let saved = store.data
        defer { store.update { $0 = saved }; LessonMetadataProtocol.handler = nil }
        let lesson = Lesson(id: "7u-01", number: 1, title: "春", author: "朱自清")
        let own = StudyResource(lessonID: lesson.id, title: "已保存的个人链接", kind: .link, url: "https://example.com/my-notes")
        XCTAssertTrue(store.update {
            $0.resources.append(own)
            $0.marks.append(StudyMark(lessonID: lesson.id, resourceID: own.id, quote: "已有摘录", note: "刷新失败时也要保留"))
        })
        let baseline = store.data
        LessonMetadataProtocol.handler = { _ in (200, #"{"code":0,"data":{"result":[]}}"#) }
        let empty = LessonRefresh(service: service())
        await empty.refresh(lesson, store: store)
        XCTAssertEqual(store.data, baseline)
        XCTAssertTrue(empty.newIDs.isEmpty)
        XCTAssertFalse(empty.hasFailure)
        XCTAssertTrue(empty.message?.contains("没有找到新增") == true)
        LessonMetadataProtocol.handler = { _ in (412, "blocked") }
        let failed = LessonRefresh(service: service())
        await failed.refresh(lesson, store: store)
        XCTAssertEqual(store.data, baseline)
        XCTAssertTrue(failed.hasFailure)
        XCTAssertTrue(failed.message?.contains("刷新失败") == true)
        XCTAssertTrue(failed.newIDs.isEmpty)
    }
    func testAtMostEightCandidatePartRequests() async throws {
        var count = 0
        LessonMetadataProtocol.handler = { request in
            if request.url!.path == "/x/player/pagelist" {
                count += 1
                return (200, #"{"code":0,"data":[{"page":1,"cid":1,"part":"《春》教学","duration":600}]}"#)
            }
            let latest = request.url!.query?.contains("pubdate") == true
            if request.url!.query?.contains("search_type=article") == true { return (200, #"{"code":0,"data":{"result":[]}}"#) }
            let rows = (0..<20).map { index -> [String: Any] in
                ["bvid": String(format: "BV%010d", (latest ? 100 : 0) + index), "title":"《春》教学", "author":"语文老师", "duration":"10:00"]
            }
            let body = try! JSONSerialization.data(withJSONObject: ["code":0,"data":["result":rows]])
            return (200, String(data: body, encoding: .utf8)!)
        }
        defer { LessonMetadataProtocol.handler = nil }
        _ = try await service().refresh(Lesson(id: "7u-01", number: 1, title: "春", author: "朱自清"))
        XCTAssertEqual(count, 8)
    }
}
