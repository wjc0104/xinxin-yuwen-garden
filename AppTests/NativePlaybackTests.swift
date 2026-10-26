import XCTest
import AVFoundation
import Combine
import UIKit
import CoreImage
import QuartzCore
import CoreVideo
import SwiftUI
import AVKit
@testable import XinxinGarden
import GardenCore

@MainActor final class NativePlaybackTests: XCTestCase {
    func testPublic720SourceActuallyPlaysWithAudioAndSeeks() async throws {
        var resource = StudyResource(id: "native-network-sample", lessonID: "7u-02", title: "济南的冬天", kind: .video, url: "https://www.bilibili.com/video/BV1eUAieoEZd/?p=2")
        resource.videoCID = 37155308866
        let video = NativeStudyPlayer()
        video.traceTransport = true
        video.useSystemDefaultRate = false // Exercise the iOS15 public transport path even on a newer simulator.
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
        if #available(iOS 16.0, *) { XCTAssertEqual(player.defaultRate, 1, "This regression must exercise transport without the iOS16 defaultRate API") }
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
            video.traceTransportState("rapid-\(attempt)-before-play")
            player.play()
            video.traceTransportState("rapid-\(attempt)-after-play")
            player.pause()
            video.traceTransportState("rapid-\(attempt)-after-pause")
            XCTAssertEqual(player.rate, 0, "System pause must take effect immediately (attempt \(attempt))")
            // Sample throughout the original150ms window; do not wait for a resumed player to settle.
            for _ in 0..<3 {
                try await Task.sleep(nanoseconds: 50_000_000)
                video.traceTransportState("rapid-\(attempt)-sample")
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
        try await assertFractionalFullScreenBinding(video, player: player, item: item)
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
        let oldController = try XCTUnwrap(video.retainedController)
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
        guard video.problem == nil else { XCTFail("Retry source failed: " + (video.problem ?? "unknown")); return }
        XCTAssertEqual(Double(try XCTUnwrap(video.currentSeconds())), 205, accuracy: 2, "Replacement loading/initial seek cannot overwrite the retained position with zero")
        let retried = expectation(description: "Retry restores the last position on the replacement item")
        let retryClock = video.$seconds.compactMap { $0 }.filter { $0 >= 204 }.prefix(1).sink { _ in retried.fulfill() }
        await fulfillment(of: [retried], timeout: 40)
        withExtendedLifetime(retryClock) {}
        XCTAssertTrue(video.ready)
        let replacement = try XCTUnwrap(video.retainedController)
        XCTAssertFalse(replacement === oldController, "Retry creates one new controller for its new player")
        XCTAssertTrue(replacement.controller.player === video.player)
        let staleHost = StudyPlayerHostController(role: .inline)
        staleHost.bind(oldController)
        XCTAssertNil(oldController.owner, "An obsolete generation cannot reattach")
        staleHost.release()
        XCTAssertTrue(replacement.controller.player === video.player)
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
    private func assertFractionalFullScreenBinding(_ video: NativeStudyPlayer, player: AVPlayer, item: AVPlayerItem) async throws {
        let presentation = FullScreenPresentation()
        let inline = UIHostingController(rootView: FullScreenBindingHarness(video: video, presentation: presentation))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = inline
        window.makeKeyAndVisible()
        defer { inline.dismiss(animated: false); window.isHidden = true; previousWindow?.makeKey() }

        let retained = try XCTUnwrap(video.retainedController)
        let controller = retained.controller
        await waitForPresentation {
            controller.view.window === window && retained.owner?.role == .inline &&
                controller.parent === retained.owner
        }
        XCTAssertTrue(controller.player === player)
        XCTAssertTrue(player.currentItem === item)
        let seek = expectation(description: "Position the mounted production controller at a fractional paused frame")
        player.seek(to: CMTime(seconds: 21.625, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { success in
            XCTAssertTrue(success); seek.fulfill()
        }
        await fulfillment(of: [seek], timeout: 15)
        let before = player.currentTime()
        XCTAssertEqual(before.seconds, 21.625, accuracy: 0.05)
        let noteAnchor = try XCTUnwrap(video.currentSeconds())
        let selectedRate = video.playbackRate

        for attempt in 1...2 {
            video.traceTransportState(.fullscreenBegin)
            presentation.focused = false
            presentation.fullScreen = true
            await waitForPresentation {
                presentation.appeared && retained.owner?.role == .fullscreen &&
                    controller.view.window != nil
            }
            let fullscreenHost = try XCTUnwrap(retained.owner)
            XCTAssertTrue(nativeController(inline) === controller)
            XCTAssertTrue(controller.player === player)
            XCTAssertTrue(player.currentItem === item)
            for sample in 0..<20 {
                XCTAssertNil(video.problem)
                XCTAssertTrue(video.retainedController === retained)
                XCTAssertTrue(controller.parent === fullscreenHost)
                XCTAssertEqual(player.rate, 0)
                XCTAssertEqual(player.timeControlStatus, .paused)
                XCTAssertTrue((player as? StudyAVPlayer)?.isExplicitlyPaused == true)
                XCTAssertEqual(player.currentTime().seconds, before.seconds, accuracy: 0.005,
                               "Fractional position after transfer \(attempt), sample \(sample)")
                XCTAssertEqual(video.playbackRate, selectedRate)
                XCTAssertEqual(video.currentSeconds(), noteAnchor)
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            // An old inline update while fullscreen is active must never steal the child.
            let staleInline = StudyPlayerHostController(role: .inline)
            staleInline.bind(retained)
            XCTAssertTrue(retained.owner === fullscreenHost)
            staleInline.release()
            XCTAssertTrue(retained.owner === fullscreenHost)

            let result = XCTAttachment(string: "attempt=\(attempt) before=\(before.value)/\(before.timescale) after=\(player.currentTime().value)/\(player.currentTime().timescale) rate=\(player.rate) sameController=\(video.retainedController?.controller === controller) samePlayer=\(controller.player === player) sameItem=\(player.currentItem === item)")
            result.name = "Retained paused production controller \(attempt)"
            result.lifetime = .keepAlways
            add(result)

            presentation.fullScreen = false
            await waitForPresentation {
                !presentation.appeared && inline.presentedViewController == nil &&
                    retained.owner?.role == .inline
            }
            retained.end(fullscreenHost) // Late old dismissal is harmless.
            XCTAssertTrue(retained.owner?.role == .inline)
            XCTAssertTrue(controller.player === player)
            XCTAssertEqual(player.currentTime().seconds, before.seconds, accuracy: 0.005)
            XCTAssertEqual(presentation.draft, "原始学习笔记草稿")
            XCTAssertEqual(video.currentSeconds(), noteAnchor)
        }

        try await assertNativeCommandsSupersedeAppSeek(video, player: player, item: item)
        player.play()
        await assertRate(player, equals: selectedRate)
        let runningBefore = player.currentTime().seconds
        presentation.fullScreen = true
        await waitForPresentation { presentation.appeared && retained.owner?.role == .fullscreen }
        XCTAssertTrue(video.retainedController?.controller === controller)
        XCTAssertTrue(player.currentItem === item)
        XCTAssertEqual(player.rate, selectedRate)
        XCTAssertGreaterThanOrEqual(player.currentTime().seconds, runningBefore - 0.05)
        let mounted = player.currentTime().seconds
        await waitForPresentation { player.currentTime().seconds > mounted + 0.3 }
        presentation.fullScreen = false
        await waitForPresentation { !presentation.appeared && retained.owner?.role == .inline }
        video.pause()
    }

    private func assertNativeCommandsSupersedeAppSeek(_ video: NativeStudyPlayer, player: AVPlayer, item: AVPlayerItem) async throws {
        let native = try XCTUnwrap(player as? StudyAVPlayer)
        XCTAssertTrue(item is StudyAVPlayerItem)
        for command in 0..<3 {
            let target = CMTime(seconds: 44.375 + Double(command) * 20, preferredTimescale: 600)
            video.seek(to: target)
            XCTAssertNotNil(video.pendingSeek, "The app seek must still be in flight")
            let appRevision = native.intentRevision
            let newerTarget = CMTime(seconds: 103.375 + Double(command) * 20, preferredTimescale: 600)
            let sought = expectation(description: "A later native command wins \(command)")
            if command == 0 {
                player.seek(to: newerTarget, toleranceBefore: .zero, toleranceAfter: .zero) { success in
                    XCTAssertTrue(success); sought.fulfill()
                }
            } else if command == 1 {
                item.seek(to: newerTarget, toleranceBefore: .zero, toleranceAfter: .zero) { success in
                    XCTAssertTrue(success); sought.fulfill()
                }
            } else {
                player.play(); player.pause()
                sought.fulfill()
            }
            let newerRevision = native.intentRevision
            XCTAssertNotEqual(newerRevision, appRevision)
            await fulfillment(of: [sought], timeout: 15)
            await waitForPresentation { video.pendingSeek == nil }
            for _ in 0..<10 {
                XCTAssertTrue(video.ready)
                XCTAssertNil(video.problem)
                XCTAssertTrue(video.player === player && player.currentItem === item)
                XCTAssertEqual(player.rate, 0)
                XCTAssertTrue(native.isExplicitlyPaused)
                if command < 2 {
                    XCTAssertEqual(player.currentTime().seconds, newerTarget.seconds, accuracy: 0.05)
                }
                XCTAssertEqual(native.intentRevision, newerRevision)
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }
    private func waitForPresentation(iterations: Int = 200, _ condition: () -> Bool) async {
        for _ in 0..<iterations {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(condition(), "Production fullscreen presentation/native position did not settle")
    }
    private func nativeController(_ controller: UIViewController) -> AVPlayerViewController? {
        if let native = controller as? AVPlayerViewController,
           native.view.accessibilityIdentifier == "fullscreen-native-player" ||
           native.view.accessibilityIdentifier == "native-video-player" { return native }
        if let presented = controller.presentedViewController, let native = nativeController(presented) { return native }
        return controller.children.compactMap { nativeController($0) }.first
    }
    private final class FullScreenPresentation: ObservableObject {
        @Published var focused = false
        @Published var fullScreen = false
        @Published var draft = "原始学习笔记草稿"
        var appeared = false
        var editorFocused = false
    }
    private struct FullScreenBindingHarness: View {
        @ObservedObject var video: NativeStudyPlayer
        @ObservedObject var presentation: FullScreenPresentation
        @FocusState private var focused: Bool
        var body: some View {
            VStack {
                NativeInlinePlayer(video: video).frame(height: presentation.focused ? 160 : 230)
                TextEditor(text: $presentation.draft).focused($focused)
            }
            .onAppear { focused = presentation.focused }
            .onChange(of: presentation.focused) { focused = $0 }
            .onChange(of: focused) { presentation.editorFocused = $0 }
            .fullScreenCover(isPresented: $presentation.fullScreen, onDismiss: { presentation.focused = true }) {
                FullScreenStudyPlayer(video: video) { presentation.fullScreen = false }
                    .onAppear { presentation.appeared = true }
                    .onDisappear { presentation.appeared = false }
            }
        }
    }
    private func assertRate(_ player: AVPlayer, equals expected: Float) async {
        let settled = expectation(description: "Native player retains selected \(expected)x speed")
        settled.assertForOverFulfill = false
        let checkReadiness = {
            let rate = player.rate, status = player.timeControlStatus
            if rate == expected && status == .playing { settled.fulfill() }
        }
        let observer = player.observe(\.rate, options: [.initial, .new]) { _, _ in checkReadiness() }
        let controlObserver = player.observe(\.timeControlStatus, options: [.initial, .new]) { _, _ in checkReadiness() }
        await fulfillment(of: [settled], timeout: 3)
        withExtendedLifetime((observer, controlObserver)) {}
        XCTAssertEqual(player.rate, expected)
        XCTAssertEqual(player.timeControlStatus, .playing)
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
