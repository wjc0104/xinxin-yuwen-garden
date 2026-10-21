import XCTest
import AVFoundation
import Combine
import UIKit
@testable import XinxinGarden
import GardenCore

@MainActor final class NativePlaybackTests: XCTestCase {
    func testPublic720SourceActuallyPlaysWithAudioAndSeeks() async throws {
        let resource = StudyResource(id: "native-network-sample", lessonID: "7u-02", title: "济南的冬天", kind: .video, url: "https://www.bilibili.com/video/BV1eUAieoEZd/?p=2")
        let video = NativeStudyPlayer()
        await video.load(resource)
        let ready = expectation(description: "Native AVPlayer ready with the real public source")
        let token = video.$ready.filter { $0 }.prefix(1).sink { _ in ready.fulfill() }
        await fulfillment(of: [ready], timeout: 35)
        withExtendedLifetime(token) {}
        guard video.ready else { XCTFail(video.problem ?? "player did not become ready"); return }
        XCTAssertEqual(video.height, 720)
        let player = try XCTUnwrap(video.player)
        let item = try XCTUnwrap(player.currentItem)
        XCTAssertFalse(item.asset.tracks(withMediaType: .audio).isEmpty, "The source must contain audio, not a silent DASH video track")
        XCTAssertGreaterThan(item.duration.seconds, 600, "The complete requested second episode must load")
        let imageReady = expectation(description: "Decode a real video frame for visual review")
        let generator = AVAssetImageGenerator(asset: item.asset)
        generator.appliesPreferredTrackTransform = true
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: CMTime(seconds: 20, preferredTimescale: 600))]) { _, image, _, result, _ in
            if result == .succeeded, let image = image {
                XCTAssertEqual(image.width, 1280)
                XCTAssertEqual(image.height, 720)
                let attachment = XCTAttachment(image: UIImage(cgImage: image))
                attachment.name = "14-原生解码720P视频帧"
                attachment.lifetime = .keepAlways
                self.add(attachment)
                imageReady.fulfill()
            }
        }
        await fulfillment(of: [imageReady], timeout: 25)
        withExtendedLifetime(generator) {}
        video.playPause()
        let progressed = expectation(description: "Media clock advances during real playback")
        let clock = video.$seconds.compactMap { $0 }.filter { $0 >= 1 }.prefix(1).sink { _ in progressed.fulfill() }
        await fulfillment(of: [progressed], timeout: 20)
        withExtendedLifetime(clock) {}
        video.pause()
        let seek = expectation(description: "Native player seeks to a note timestamp")
        player.seek(to: CMTime(seconds: 205, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { success in
            if success { seek.fulfill() }
        }
        await fulfillment(of: [seek], timeout: 15)
        XCTAssertEqual(Double(try XCTUnwrap(video.currentSeconds())), 205, accuracy: 1)
        let same = video.player
        await video.load(resource)
        XCTAssertTrue(video.player === same, "UI refresh must preserve the playing item and position")
    }
}
