import XCTest
import AVFoundation
import Combine
import UIKit
import CoreImage
import QuartzCore
import CoreVideo
@testable import XinxinGarden
import GardenCore

@MainActor final class NativePlaybackTests: XCTestCase {
    func testPublic720SourceActuallyPlaysWithAudioAndSeeks() async throws {
        var resource = StudyResource(id: "native-network-sample", lessonID: "7u-02", title: "济南的冬天", kind: .video, url: "https://www.bilibili.com/video/BV1eUAieoEZd/?p=2")
        resource.videoCID = 37155308866
        let video = NativeStudyPlayer()
        XCTAssertEqual(video.playbackRate, 1)
        XCTAssertEqual(NativeStudyPlayer.playbackRates, [0.5, 0.75, 1, 1.25, 1.5, 2])
        await video.load(resource)
        defer { video.pause() }
        guard video.problem == nil else { XCTFail(video.problem ?? "source error"); return }
        let ready = expectation(description: "Native AVPlayer ready or reports a real source error")
        let token = video.$ready.combineLatest(video.$problem).filter { $0.0 || $0.1 != nil }.prefix(1).sink { _ in ready.fulfill() }
        await fulfillment(of: [ready], timeout: 35)
        withExtendedLifetime(token) {}
        guard video.ready else { XCTFail(video.problem ?? "player did not become ready"); return }
        XCTAssertEqual(video.height, 720)
        let player = try XCTUnwrap(video.player)
        let item = try XCTUnwrap(player.currentItem)
        video.setPlaybackRate(0.75)
        XCTAssertEqual(player.rate, 0, "Selecting speed while paused must not start playback")
        video.setPlaybackRate(3)
        XCTAssertEqual(video.playbackRate, 0.75, "Reject rates outside the explicit menu")
        XCTAssertFalse(item.asset.tracks(withMediaType: .audio).isEmpty, "The source must contain audio, not a silent DASH video track")
        XCTAssertGreaterThan(item.duration.seconds, 600, "The complete requested second episode must load")
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        defer { item.remove(output) }
        video.playPause()
        await assertRate(player, equals: 0.75)
        let progressed = expectation(description: "Media clock advances during real playback")
        let clock = video.$seconds.compactMap { $0 }.filter { $0 >= 1 }.prefix(1).sink { _ in progressed.fulfill() }
        await fulfillment(of: [progressed], timeout: 20)
        withExtendedLifetime(clock) {}
        video.setPlaybackRate(1.5)
        await assertRate(player, equals: 1.5)
        // Native AVKit controls call play()/pause(); play() resets rate on iOS15.
        player.pause()
        video.setPlaybackRate(1.25)
        XCTAssertEqual(player.rate, 0)
        player.play()
        await assertRate(player, equals: 1.25)
        // A queued rate correction must not undo a subsequent system pause.
        for attempt in 0..<5 {
            player.play(); player.pause()
            XCTAssertEqual(player.rate, 0, "System pause must take effect immediately (attempt \(attempt))")
            // Sample throughout the original150ms window; do not wait for a resumed player to settle.
            for _ in 0..<3 {
                try await Task.sleep(nanoseconds: 50_000_000)
                XCTAssertEqual(player.rate, 0, "Queued rate correction must not resume a system pause (attempt \(attempt))")
            }
            video.setPlaybackRate(1.25)
            XCTAssertEqual(player.rate, 0, "Changing selected speed after system pause must remain paused")
        }
        player.play()
        await assertRate(player, equals: 1.25)
        let framePosition = expectation(description: "Inspect an informative lesson frame after the opening")
        player.seek(to: CMTime(seconds: 20, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { success in
            if success { framePosition.fulfill() }
        }
        await fulfillment(of: [framePosition], timeout: 10)
        await assertRate(player, equals: 1.25)
        // Inspect the frame emitted by this actual AVPlayerItem, not a separate image generator.
        var decoded: CVPixelBuffer?
        for _ in 0..<80 {
            let time = output.itemTime(forHostTime: CACurrentMediaTime())
            if output.hasNewPixelBuffer(forItemTime: time) {
                decoded = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
                if decoded != nil { break }
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let buffer = try XCTUnwrap(decoded, "The playing AVPlayerItem must emit a decoded frame")
        let frame = CIImage(cvPixelBuffer: buffer)
        let image = try XCTUnwrap(CIContext().createCGImage(frame, from: frame.extent))
        XCTAssertEqual(image.width, 1280); XCTAssertEqual(image.height, 720)
        let attachment = XCTAttachment(image: UIImage(cgImage: image))
        attachment.name = "14-实际AVPlayer输出720P视频帧"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertTrue(hasSpatialDetail(buffer), "A uniform green/black output is not evidence of the lesson picture; inspect the retained frame")
        video.pause()
        video.setPlaybackRate(2)
        XCTAssertEqual(player.rate, 0)
        let seek = expectation(description: "Native player seeks to a note timestamp")
        player.seek(to: CMTime(seconds: 205, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { success in
            if success { seek.fulfill() }
        }
        await fulfillment(of: [seek], timeout: 15)
        XCTAssertEqual(Double(try XCTUnwrap(video.currentSeconds())), 205, accuracy: 1)
        XCTAssertEqual(video.playbackRate, 2)
        XCTAssertEqual(player.rate, 0, "Seek must not resume a paused player")
        let same = video.player
        await video.load(resource)
        XCTAssertTrue(video.player === same, "UI refresh must preserve the playing item and position")
        XCTAssertEqual(video.playbackRate, 2)
        video.playPause()
        await assertRate(player, equals: 2)
        // Exercise the same handler used by AVPlayerItem failure after a nonzero seek.
        video.pause()
        video.playbackFailed(item)
        XCTAssertFalse(video.ready)
        XCTAssertEqual(Double(try XCTUnwrap(video.currentSeconds())), 205, accuracy: 2)
        var unavailable = resource; unavailable.url = "invalid"
        await video.load(unavailable, force: true)
        XCTAssertFalse(video.ready)
        XCTAssertNotNil(video.problem)
        XCTAssertEqual(Double(try XCTUnwrap(video.currentSeconds())), 205, accuracy: 2, "A failed retry must retain the same resource's position")
        await video.load(resource, force: true)
        XCTAssertEqual(Double(try XCTUnwrap(video.currentSeconds())), 205, accuracy: 2, "Replacement loading/initial seek cannot overwrite the retained position with zero")
        let retried = expectation(description: "Retry restores the last position on the replacement item")
        let retryClock = video.$seconds.compactMap { $0 }.filter { $0 >= 204 }.prefix(1).sink { _ in retried.fulfill() }
        await fulfillment(of: [retried], timeout: 40)
        withExtendedLifetime(retryClock) {}
        XCTAssertTrue(video.ready)
        XCTAssertEqual(video.playbackRate, 2)
        XCTAssertEqual(video.player?.rate, 0, "Retry and seek preserve the paused state")
        XCTAssertEqual(Double(try XCTUnwrap(video.currentSeconds())), 205, accuracy: 2)
        video.playbackFailed(item) // callback from the replaced generation
        XCTAssertNil(video.problem)
        video.seek(0)
        let reset = expectation(description: "An explicit seek to zero still replaces the retained position")
        let resetClock = video.$seconds.filter { $0 == 0 }.prefix(1).sink { _ in reset.fulfill() }
        await fulfillment(of: [reset], timeout: 10)
        withExtendedLifetime(resetClock) {}
        XCTAssertEqual(video.currentSeconds(), 0)
        var other = resource; other.id = "different-video"; other.url = "invalid"
        await video.load(other, force: true)
        XCTAssertNil(video.currentSeconds(), "The old resource's position must not leak into another video")
        video.playbackFailed(item)
        XCTAssertNil(video.currentSeconds())
    }
    private func assertRate(_ player: AVPlayer, equals expected: Float) async {
        let settled = expectation(description: "Native player retains selected \(expected)x speed")
        let observer = player.observe(\.rate, options: [.initial, .new]) { player, _ in
            if player.rate == expected { settled.fulfill() }
        }
        settled.assertForOverFulfill = false
        await fulfillment(of: [settled], timeout: 3)
        withExtendedLifetime(observer) {}
        XCTAssertEqual(player.rate, expected)
    }
    private func hasSpatialDetail(_ buffer: CVPixelBuffer) -> Bool {
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return false }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var low = [255, 255, 255], high = [0, 0, 0]
        for y in Swift.stride(from: 0, to: CVPixelBufferGetHeight(buffer), by: 16) {
            for x in Swift.stride(from: 0, to: CVPixelBufferGetWidth(buffer), by: 16) {
                for channel in 0..<3 {
                    let value = Int(bytes[y * stride + x * 4 + channel])
                    low[channel] = min(low[channel], value); high[channel] = max(high[channel], value)
                }
            }
        }
        return (0..<3).contains { high[$0] - low[$0] > 12 }
    }
}
