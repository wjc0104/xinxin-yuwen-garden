import XCTest
@testable import GardenCore

final class VideoPlaybackTests: XCTestCase {
    func testVideoReferenceKeepsExactEpisode() throws {
        let ref = try BilibiliPlayback.reference("https://www.bilibili.com/video/BV1eUAieoEZd/?p=2")
        XCTAssertEqual(ref.bvid, "BV1eUAieoEZd"); XCTAssertEqual(ref.page, 2)
        let data = Data(#"{"code":0,"data":{"pages":[{"page":1,"cid":110},{"page":2,"cid":220}]}}"#.utf8)
        XCTAssertEqual(try BilibiliPlayback.contentID(data, page: ref.page), 220)
        XCTAssertThrowsError(try BilibiliPlayback.contentID(data, page: 3))
    }
    func testActualReturnedQualityWinsOverAdvertisedQualities() throws {
        let data = Data(#"{"code":0,"data":{"quality":16,"format":"mp4","accept_quality":[80,64,16],"timelength":600000,"durl":[{"url":"https://upos.example.bilivideo.com/video.mp4"}]}}"#.utf8)
        let source = try BilibiliPlayback.source(data)
        XCTAssertEqual(source.offeredHeight, 360)
        XCTAssertEqual(source.duration, 600)
    }
    func testAvailable720CombinedStreamIsPreserved() throws {
        let data = Data(#"{"code":0,"data":{"quality":64,"format":"mp4720","timelength":654106,"durl":[{"url":"https://upos.example.bilivideo.com/video.mp4?deadline=42"}]}}"#.utf8)
        let source = try BilibiliPlayback.source(data)
        XCTAssertEqual(source.offeredHeight, 720)
        XCTAssertEqual(source.url.query, "deadline=42")
    }
    func testMissingOrRestrictedMediaIsNotReportedAsPlayable() {
        for json in [#"{"code":-403}"#, #"{"code":0,"data":{"quality":64,"format":"flv720","durl":[]}}"#, #"{"code":0,"data":{"quality":64,"format":"mp4","is_preview":true,"durl":[{"url":"https://upos.example.bilivideo.com/a.mp4"}]}}"#] {
            XCTAssertThrowsError(try BilibiliPlayback.source(Data(json.utf8)))
        }
    }
    func testUnrelatedHostsAndInvalidEpisodesAreRejected() {
        XCTAssertThrowsError(try BilibiliPlayback.reference("https://bilibili.com.evil/video/BV1eUAieoEZd/?p=2"))
        XCTAssertThrowsError(try BilibiliPlayback.reference("https://www.bilibili.com/video/BV1eUAieoEZd/?p=0"))
        let data = Data(#"{"code":0,"data":{"quality":64,"format":"mp4","durl":[{"url":"https://bilivideo.com.evil/video.mp4"}]}}"#.utf8)
        XCTAssertThrowsError(try BilibiliPlayback.source(data))
    }
}
