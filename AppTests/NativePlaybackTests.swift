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
        XCTAssertFalse(item.asset.tracks(withMediaType: .audio).isEmpty, "The source must contain audio, not a silent DASH video track")
        XCTAssertGreaterThan(item.duration.seconds, 600, "The complete requested second episode must load")
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        defer { item.remove(output) }
        video.playPause()
        let progressed = expectation(description: "Media clock advances during real playback")
        let clock = video.$seconds.compactMap { $0 }.filter { $0 >= 1 }.prefix(1).sink { _ in progressed.fulfill() }
        await fulfillment(of: [progressed], timeout: 20)
        withExtendedLifetime(clock) {}
        let framePosition = expectation(description: "Inspect an informative lesson frame after the opening")
        player.seek(to: CMTime(seconds: 20, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { success in
            if success { framePosition.fulfill() }
        }
        await fulfillment(of: [framePosition], timeout: 10)
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
