import XCTest
@testable import GardenCore

final class LessonContentTests: XCTestCase {
    private let spring = Lesson(id: "7u-01", number: 1, title: "春", author: "朱自清")
    private func bytes(_ json: String) -> Data { Data(json.utf8) }

    func testMovedCuratedPartResolvesCIDAndNeverFallsBackToOldPage() throws {
        let ref = try BilibiliPlayback.reference("https://www.bilibili.com/video/BV137LizrE4S/?p=46")
        let parts = try BilibiliPlayback.parts(bytes(#"{"code":0,"data":[{"page":45,"cid":29807281516,"part":"朝天子·咏喇叭","duration":600},{"page":46,"cid":999,"part":"其他课文","duration":500}]}"#))
        XCTAssertEqual(try BilibiliPlayback.resolve(parts, reference: ref, knownCID: 29807281516).page, 45)
        XCTAssertThrowsError(try BilibiliPlayback.resolve(parts, reference: ref, knownCID: 123)) { error in
            XCTAssertTrue(error.localizedDescription.contains("原分集已被移除"))
        }
        XCTAssertEqual(try BilibiliPlayback.resolve(parts, reference: ref, knownCID: nil).cid, 999)
        XCTAssertEqual(ref.partListURL.path, "/x/player/pagelist")
    }
    func testBlockedAPIIsServiceErrorRatherThanMissingPart() {
        XCTAssertThrowsError(try BilibiliPlayback.parts(bytes(#"{"code":-412,"message":"blocked"}"#))) { error in
            XCTAssertTrue(error.localizedDescription.contains("服务暂不可用"))
            XCTAssertFalse(error.localizedDescription.contains("没有返回这一集"))
        }
    }
    func testShortTitleRequiresWholeWorkAndTeachingOrAuthorContext() {
        for title in ["春望 教师试讲", "晚春 教案", "青春 语文", "初中语文七年级全册教学合集", "《春》时尚穿搭"] {
            XCTAssertFalse(LessonContent.matches(title, lesson: spring), title)
        }
        for title in ["朱自清《春》", "《春》初中语文试讲稿", "春教学设计"] { XCTAssertTrue(LessonContent.matches(title, lesson: spring), title) }
        XCTAssertTrue(LessonContent.matches("《说和做》语文试讲", lesson: Lesson(id: "7d-02", number: 2, title: "说和做——记闻一多先生言行片段")))
    }
    func testSearchStripsEmAndValidatesMetadata() throws {
        let candidates = try LessonContent.videos(bytes(#"{"code":0,"data":{"result":[{"bvid":"BV137LizrE4S","title":"朱自清《<em class=\"keyword\">春</em>》语文试讲","author":"老师","pic":"//i0.hdslb.com/a.jpg","duration":"10:30"},{"bvid":"bad","title":"春","author":"x"}]}}"#))
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].title, "朱自清《春》语文试讲")
        XCTAssertEqual(candidates[0].duration, 630)
        XCTAssertEqual(candidates[0].thumbnail, "https://i0.hdslb.com/a.jpg")
        XCTAssertNil(LessonContent.imageURL("https://evil.test/x"))
    }
    func testArticleKeepsOnlyDirectOriginalMetadataAndCategory() throws {
        let articles = try LessonContent.articles(bytes(#"{"code":0,"data":{"result":[{"id":11654040,"title":"《<em>春</em>》语文试讲逐字稿","author":"老师","desc":"FULL COPYRIGHTED TEXT","image_urls":[]}]}}"#), lesson: spring, checkedAt: "today")
        XCTAssertEqual(articles.count, 1)
        XCTAssertEqual(articles[0].url, "https://www.bilibili.com/read/cv11654040")
        XCTAssertEqual(articles[0].category, "试讲稿")
        XCTAssertEqual(articles[0].kind, .script)
        XCTAssertTrue(articles[0].body.isEmpty)
        XCTAssertNil(articles[0].summary)
        XCTAssertEqual(LessonContent.articleCategory("《春》教学设计"), "教学设计")
        XCTAssertEqual(LessonContent.articleCategory("《春》课文赏析"), "课文解读")
    }
    func testMultiPartMatchesActualPartNotCollectionTitle() throws {
        let video = try XCTUnwrap(try LessonContent.videos(bytes(#"{"code":0,"data":{"result":[{"bvid":"BV137LizrE4S","title":"《春》及初中语文全册","author":"语文老师","duration":"10:00"}]}}"#)).first)
        let parts = [BilibiliPart(page: 1, cid: 1, part: "春望", duration: 300), BilibiliPart(page: 2, cid: 2, part: "《春》", duration: 600), BilibiliPart(page: 3, cid: 3, part: "第一课", duration: 600)]
        let resources = LessonContent.resources(video, parts: parts, lesson: spring, checkedAt: "today")
        XCTAssertEqual(resources.map(\.videoCID), [2])
        XCTAssertEqual(resources.first?.id, "live-7u-01-BV137LizrE4S-2")
    }
    func testMergeRetainsCuratedIDNotesAndLinksWhenPartMovesOrRefreshEmpty() {
        var old = StudyResource(id: "curated-9d-extra6-4-BV137LizrE4S-46", lessonID: "9d-extra6-4", title: "朝天子·咏喇叭", kind: .video, url: "https://www.bilibili.com/video/BV137LizrE4S/?p=46")
        old.videoCID = 29807281516
        var updated = old; updated.id = "live-9d-extra6-4-BV137LizrE4S-29807281516"; updated.url = "https://www.bilibili.com/video/BV137LizrE4S/?p=45"
        let custom = StudyResource(lessonID: old.lessonID, title: "我的链接", kind: .link, url: "https://example.com")
        var snapshot = GardenSnapshot(); snapshot.resources = [old, custom]
        snapshot.marks = [StudyMark(lessonID: old.lessonID, resourceID: old.id, quote: "我的摘录", note: "笔记")]
        let merged = LessonContent.merge([updated, updated], into: snapshot.resources)
        XCTAssertEqual(merged.resources.count, 2); XCTAssertTrue(merged.addedIDs.isEmpty)
        XCTAssertEqual(merged.resources[0].id, old.id); XCTAssertEqual(merged.resources[0].url, updated.url)
        XCTAssertEqual(snapshot.marks[0].resourceID, merged.resources[0].id)
        XCTAssertEqual(LessonContent.merge([], into: snapshot.resources).resources, snapshot.resources)
    }
    func testOldResourceJSONWithoutCIDStillDecodes() throws {
        let resource = try JSONDecoder().decode(StudyResource.self, from: bytes(#"{"id":"old","lessonID":"7u-01","title":"旧资料","kind":"video","body":"","url":"","localFile":"","source":"我","isPaid":false}"#))
        XCTAssertNil(resource.videoCID)
    }
    func testNewArticleDeduplicatesByCVAndCountsOnlyOneAddition() {
        let article = StudyResource(id: "live-7u-01-cv11654040", lessonID: spring.id, title: "《春》试讲稿", kind: .script, url: "https://www.bilibili.com/read/cv11654040")
        var same = article; same.id = "other-id"; same.url += "/"
        let result = LessonContent.merge([article, same], into: [])
        XCTAssertEqual(result.resources.count, 1)
        XCTAssertEqual(result.addedIDs, [article.id])
    }
}
