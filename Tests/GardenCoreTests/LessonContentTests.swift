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
    func testMissingAnthologiesUseNamedWorksAndBoundQueries() throws {
        let groups: [(String, [String])] = [
            ("《世说新语》二则", ["咏雪", "陈太丘与友期行"]),
            ("《孟子》三章", ["得道多助，失道寡助", "富贵不能淫", "生于忧患，死于安乐"]),
            ("《诗经》二首", ["关雎", "蒹葭"]),
            ("《庄子》二则", ["北冥有鱼", "庄子与惠子游于濠梁之上"]),
            ("《礼记》二则", ["虽有嘉肴", "大道之行也"]),
            ("消息二则", ["我三十万大军胜利南渡长江", "人民解放军百万大军横渡长江"]),
            ("阿西莫夫短文两篇", ["恐龙无处不有", "被压扁的沙子"]),
            ("寓言四则", ["赫耳墨斯和雕像者", "蚊子和狮子", "穿井得一人", "杞人忧天"])
        ]
        for (title, works) in groups {
            let lesson = Lesson(id: "anthology", number: 1, title: title, focus: works)
            XCTAssertEqual(LessonContent.keys(lesson), works)
            XCTAssertEqual(LessonContent.discoveryKeywords(lesson), works.map { $0 + " 语文" })
            for work in works { XCTAssertTrue(LessonContent.matches("《" + work + "》语文教学", lesson: lesson)) }
            XCTAssertFalse(LessonContent.matches("初中语文全册合集", lesson: lesson))
        }
        let ordinary = Lesson(id: "single", number: 1, title: "背影", focus: ["朗读", "父爱", "细节描写"])
        XCTAssertEqual(LessonContent.discoveryKeywords(ordinary), ["背影 语文"])
        XCTAssertFalse(LessonContent.matches("父爱教学", lesson: ordinary))
        let zhuangzi = Lesson(id: "8d-21", number: 21, title: "《庄子》二则", focus: ["北冥有鱼", "庄子与惠子游于濠梁之上"])
        let article = try LessonContent.articles(bytes(#"{"code":0,"data":{"result":[{"id":123,"title":"北冥有鱼教学设计","author":"老师"},{"id":124,"title":"语文全册教学设计","author":"老师"}]}}"#), lesson: zhuangzi, checkedAt: "today")
        XCTAssertEqual(article.map(\.id), ["live-8d-21-cv123"])
        let video = try XCTUnwrap(try LessonContent.videos(bytes(#"{"code":0,"data":{"result":[{"bvid":"BV137LizrE4S","title":"初中语文全册","author":"语文老师"}]}}"#)).first)
        let parts = [BilibiliPart(page: 1, cid: 1, part: "北冥有鱼", duration: 600), BilibiliPart(page: 2, cid: 2, part: "庄子与惠子游于濠梁之上", duration: 600), BilibiliPart(page: 3, cid: 3, part: "泛论人生", duration: 600)]
        XCTAssertEqual(LessonContent.resources(video, parts: parts, lesson: zhuangzi, checkedAt: "today").map(\.videoCID), [1, 2])
        XCTAssertEqual(LessonContent.discoveryKeywords(Lesson(id: "five", number: 1, title: "唐诗五首", focus: (1...8).map { "篇名\($0)" })).count, 5)
    }
    func testLiveSpeakingPlanStaysALinkRatherThanTrialScript() throws {
        let rows = try LessonContent.articles(bytes(#"{"code":0,"data":{"result":[{"id":12,"title":"《春》语文说课稿与试讲建议","author":"老师"}]}}"#), lesson: spring, checkedAt: "today")
        let plan = try XCTUnwrap(rows.first)
        XCTAssertEqual(plan.category, "说课稿")
        XCTAssertEqual(plan.kind, .link)
        XCTAssertTrue(plan.body.isEmpty)
        XCTAssertEqual(plan.url, "https://www.bilibili.com/read/cv12")
    }
    func testVideoMetadataRejectsNoncanonicalBVTokens() throws {
        for suffix in ["?p=2", "#fragment", "/", "/other", "?p=2#fragment", "\n", " "] {
            let payload = try JSONSerialization.data(withJSONObject: ["code":0,"data":["result":[["bvid":"BV137LizrE4S" + suffix,"title":"《春》语文","author":"老师"]]]])
            XCTAssertTrue(try LessonContent.videos(payload).isEmpty, suffix)
        }
        let valid = try LessonContent.videos(bytes(#"{"code":0,"data":{"result":[{"bvid":"BV137LizrE4S","title":"《春》语文","author":"老师"}]}}"#))
        XCTAssertEqual(valid.map(\.bvid), ["BV137LizrE4S"])
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
