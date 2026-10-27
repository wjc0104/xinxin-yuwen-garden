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
    func testPlainAVPlayerSharedAssetDecodedOutputControl() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GARDEN_SAME_ITEM_RENDER_DIAGNOSTICS"] == "1", "Diagnostic-only plain decoded-output control")
        try await capturePlainDecodedOutputControl()
    }
    func testCompleteObjectSameBytesDecodedOutputControl() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GARDEN_COMPLETE_OBJECT_SAME_BYTES"] == "1", "Diagnostic-only complete-object decoded-output control")
        try await capturePlainDecodedOutputControl(localContext: CompleteObjectTestContext())
    }
    private func capturePlainDecodedOutputControl(localContext: CompleteObjectTestContext? = nil) async throws {
        let started = ProcessInfo.processInfo.systemUptime, softDeadline = started + 130
        var summary: [String: Any] = ["schema": 1, "scope": "plainDecodedOutput", "episode": 2,
            "cid": 37155308866, "startedUptime": started, "completed": false, "stage": "load",
            "captureCompleted": false, "artifactsSucceeded": false, "captureExitUptime": NSNull(),
            "exportStartedUptime": NSNull(), "exportEndedUptime": NSNull(),
            "actualScreenCaptured": false, "productionPaused52BufferAvailable": false]
        var frames: [[String: Any]] = [], pngBytes = 0, rawBytes = 0
        var ownedSnapshots: [(index: Int, name: String, buffer: CVPixelBuffer)] = []
        var captureCompleted = false, artifactsSucceeded = true
        func finite(_ value: Double) -> Any { value.isFinite ? value as Any : NSNull() }
        func poll() async throws {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        defer {
            summary["frames"] = frames; summary["pngBytes"] = pngBytes; summary["rawBytes"] = rawBytes
            summary["captureCompleted"] = captureCompleted; summary["artifactsSucceeded"] = artifactsSucceeded
            summary["completed"] = captureCompleted && artifactsSucceeded
            if captureCompleted { summary["stage"] = artifactsSucceeded ? "complete" : "export-failed" }
            summary["endedUptime"] = finite(ProcessInfo.processInfo.systemUptime)
            // COMPLETE_OBJECT_LOCAL_BEGIN summary-finalize
            if let localContext = localContext, !localContext.finalize(&summary) {
                XCTFail("Complete-object source verification failed")
            }
            // COMPLETE_OBJECT_LOCAL_END summary-finalize
            let encoded = try? JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys])
            let data: Data
            if let encoded = encoded, encoded.count <= 16 * 1024 { data = encoded }
            else {
                artifactsSucceeded = false; summary["completed"] = false; summary["artifactsSucceeded"] = false
                XCTFail("Plain decoded-output summary exceeded its fixed schema/16KiB budget")
                data = Data("{\"schema\":1,\"scope\":\"plainDecodedOutput\",\"completed\":false,\"captureCompleted\":\(captureCompleted),\"artifactsSucceeded\":false,\"summaryUnavailable\":true}".utf8)
            }
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "plain-decoded-output.json"; attachment.lifetime = .keepAlways; add(attachment)
            // COMPLETE_OBJECT_LOCAL_BEGIN result-write
            if let localContext = localContext {
                do { try localContext.writeResult(summary) }
                catch { XCTFail("Complete-object bounded result write failed") }
            }
            // COMPLETE_OBJECT_LOCAL_END result-write
        }
        defer {
            summary["exportStartedUptime"] = finite(ProcessInfo.processInfo.systemUptime)
            if !ownedSnapshots.isEmpty {
                let context = CIContext()
                for snapshot in ownedSnapshots {
                    autoreleasepool {
                        frames[snapshot.index]["exportStartedUptime"] = finite(ProcessInfo.processInfo.systemUptime)
                        frames[snapshot.index]["exportState"] = "failed"
                        defer { frames[snapshot.index]["exportEndedUptime"] = finite(ProcessInfo.processInfo.systemUptime) }
                        let frame = CIImage(cvPixelBuffer: snapshot.buffer)
                        guard let image = context.createCGImage(frame, from: frame.extent) else {
                            artifactsSucceeded = false; XCTFail("Plain owned first buffer must convert to an image"); return
                        }
                        guard image.width == 1280, image.height == 720 else {
                            artifactsSucceeded = false; XCTFail("Plain first buffer must be an uncropped 1280x720 image"); return
                        }
                        guard let png = UIImage(cgImage: image).pngData() else {
                            artifactsSucceeded = false; XCTFail("Plain owned first buffer must encode as PNG"); return
                        }
                        guard png.count <= 4 * 1024 * 1024, pngBytes + png.count <= 16 * 1024 * 1024 else {
                            artifactsSucceeded = false; XCTFail("Plain PNG attachment exceeded its fixed byte budget"); return
                        }
                        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                        attachment.name = snapshot.name; attachment.lifetime = .keepAlways; add(attachment)
                        pngBytes += png.count; frames[snapshot.index]["pngBytes"] = png.count
                        frames[snapshot.index]["exportState"] = "attached"
                        // COMPLETE_OBJECT_LOCAL_BEGIN png-write
                        if let localContext = localContext {
                            do { try localContext.writePNG(png, name: snapshot.name) }
                            catch { artifactsSucceeded = false; XCTFail("Complete-object bounded PNG write failed") }
                        }
                        // COMPLETE_OBJECT_LOCAL_END png-write
                    }
                }
            }
            summary["exportEndedUptime"] = finite(ProcessInfo.processInfo.systemUptime)
        }
        // Setup failures have no native cleanup; stamp them before the deferred export too.
        defer {
            if summary["captureExitUptime"] is NSNull {
                summary["captureExitUptime"] = finite(ProcessInfo.processInfo.systemUptime)
            }
        }
        var resource = StudyResource(id: "native-network-sample", lessonID: "7u-02", title: "济南的冬天", kind: .video, url: "https://www.bilibili.com/video/BV1eUAieoEZd/?p=2")
        resource.videoCID = 37155308866
        var sharedAsset: AVURLAsset?, readyDeadline = softDeadline
        weak var loaderWitness: NativeStudyPlayer?
        // COMPLETE_OBJECT_LOCAL_BEGIN source-branch
        if let localContext = localContext {
            do {
                let localAsset = AVURLAsset(url: try localContext.prepare(softDeadline: softDeadline))
                let videos = localAsset.tracks(withMediaType: .video)
                guard ProcessInfo.processInfo.systemUptime < softDeadline,
                      localAsset.duration.seconds.isFinite, localAsset.duration.seconds > 600,
                      !localAsset.tracks(withMediaType: .audio).isEmpty, videos.count == 1,
                      videos[0].naturalSize == CGSize(width: 1280, height: 720),
                      videos[0].preferredTransform == .identity else {
                    XCTFail("Complete-object control requires a complete 720p episode with audio"); return
                }
                try Task.checkCancellation()
                readyDeadline = min(softDeadline, ProcessInfo.processInfo.systemUptime + 35)
                summary["stage"] = "ready"
                sharedAsset = localAsset
            } catch {
                XCTFail("Complete-object source setup failed"); return
            }
        } else {
        // COMPLETE_OBJECT_LOCAL_END source-branch
        do {
            let loader = NativeStudyPlayer()
            loaderWitness = loader
            defer { loader.pause() }
            await loader.load(resource) // Reuse the existing resolver, options, requests and watchdog.
            try Task.checkCancellation()
            readyDeadline = min(softDeadline, ProcessInfo.processInfo.systemUptime + 35)
            summary["stage"] = "ready"
            while !loader.ready && loader.problem == nil && ProcessInfo.processInfo.systemUptime < readyDeadline {
                try await poll()
            }
            guard ProcessInfo.processInfo.systemUptime < readyDeadline, loader.ready, loader.problem == nil else {
                XCTFail("Plain decoded-output source setup failed or exceeded its soft deadline"); return
            }
            loader.pause()
            let sourcePlayer = try XCTUnwrap(loader.player, "Plain control requires the loaded public source")
            let sourceItem = try XCTUnwrap(sourcePlayer.currentItem, "Plain control requires the loaded source item")
            guard sourcePlayer.rate == 0, loader.height == 720, sourceItem.duration.seconds.isFinite,
                  sourceItem.duration.seconds > 600, !sourceItem.asset.tracks(withMediaType: .audio).isEmpty else {
                XCTFail("Plain control requires a paused complete 720p public episode with audio"); return
            }
            sharedAsset = try XCTUnwrap(sourceItem.asset as? AVURLAsset, "Plain control requires the existing AVURLAsset")
        } // Drop the loader's strong references without adding production teardown.
        // COMPLETE_OBJECT_LOCAL_BEGIN source-end
        }
        // COMPLETE_OBJECT_LOCAL_END source-end
        summary["loaderReleased"] = loaderWitness == nil
        let asset = try XCTUnwrap(sharedAsset, "Plain control requires the shared asset")
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        let controller = AVPlayerViewController()
        controller.player = player
        var window: UIWindow?, previousWindow: UIWindow?
        defer {
            player.pause(); item.remove(output); controller.player = nil
            player.replaceCurrentItem(with: nil)
            window?.isHidden = true; window?.rootViewController = nil; previousWindow?.makeKey()
        }
        defer { summary["captureExitUptime"] = finite(ProcessInfo.processInfo.systemUptime) }
        guard type(of: item) == AVPlayerItem.self, type(of: player) == AVPlayer.self,
              item.asset === asset, player.currentItem === item else {
            XCTFail("Plain control must use exact AVPlayerItem/AVPlayer classes and the shared asset object"); return
        }
        summary["exactPlainClasses"] = true; summary["sharedAssetObject"] = true
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previousWindow = scene.windows.first { $0.isKeyWindow }
        let mountedWindow = UIWindow(windowScene: scene)
        window = mountedWindow; mountedWindow.rootViewController = controller; mountedWindow.makeKeyAndVisible()
        summary["stage"] = "window"
        let windowDeadline = min(softDeadline, ProcessInfo.processInfo.systemUptime + 2)
        while controller.view.window !== mountedWindow && ProcessInfo.processInfo.systemUptime < windowDeadline { try await poll() }
        guard ProcessInfo.processInfo.systemUptime < windowDeadline, controller.view.window === mountedWindow else {
            XCTFail("Plain controller did not enter the test window within its soft setup budget"); return
        }
        summary["controllerInWindow"] = true // Setup only, never evidence of displayed video pixels.
        while item.status == .unknown && ProcessInfo.processInfo.systemUptime < readyDeadline { try await poll() }
        guard ProcessInfo.processInfo.systemUptime < readyDeadline, item.status == .readyToPlay,
              player.currentTime().seconds.isFinite, abs(player.currentTime().seconds) <= 0.05 else {
            XCTFail("Plain item did not become ready at zero within its soft ready budget"); return
        }
        summary["readyForDisplayAtSetup"] = controller.isReadyForDisplay
        let playStarted = ProcessInfo.processInfo.systemUptime
        let playDeadline = min(softDeadline, playStarted + 50)
        summary["playStartedUptime"] = playStarted; summary["stage"] = "playing"
        player.playImmediately(atRate: 1.5) // One natural run from zero; no seeks or rate reconciliation.
        let targets: [(Double, String)] = [(5, "plain-05.png"), (15, "plain-15.png"), (25, "plain-25.png"), (52, "plain-paused52.png")]
        for (target, name) in targets {
            let paused = target == 52, index = frames.count
            frames.append(["targetSeconds": target, "paused": paused, "state": "waiting",
                "copyStartedUptime": NSNull(), "copyEndedUptime": NSNull(),
                "exportStartedUptime": NSNull(), "exportEndedUptime": NSNull(), "exportState": "not-retained"])
            while ProcessInfo.processInfo.systemUptime < playDeadline {
                try Task.checkCancellation()
                let current = player.currentTime().seconds
                guard current.isFinite, item.status == .readyToPlay else {
                    XCTFail("Plain playback lost a finite ready media clock"); return
                }
                if current >= target { break }
                try await poll()
            }
            guard ProcessInfo.processInfo.systemUptime < playDeadline else {
                XCTFail("Plain natural playback exceeded its 50s/total soft budget"); return
            }
            if paused {
                player.pause() // Pause on the first observed crossing, even when the media window was missed.
                guard player.rate == 0 else { XCTFail("Plain pause did not stop the native rate"); return }
            }
            let captureDeadline = min(playDeadline, paused ? ProcessInfo.processInfo.systemUptime + 1 : playDeadline)
            var captured = false
            summary["stage"] = "capture"
            while ProcessInfo.processInfo.systemUptime < captureDeadline {
                try Task.checkCancellation()
                let beforeUptime = ProcessInfo.processInfo.systemUptime, before = player.currentTime().seconds
                let beforeRate = player.rate, beforeControl = player.timeControlStatus.rawValue
                let requested = output.itemTime(forHostTime: CACurrentMediaTime())
                frames[index].merge(["currentBeforeSeconds": finite(before), "requestedSeconds": finite(requested.seconds),
                    "rateBefore": finite(Double(beforeRate)), "controlBefore": beforeControl, "beforeUptime": beforeUptime]) { _, new in new }
                guard before.isFinite, before >= target, before <= target + 0.75, requested.seconds.isFinite,
                      abs(requested.seconds - before) <= 0.75 else {
                    XCTFail("Plain capture missed the current 0.75s media window"); return
                }
                if output.hasNewPixelBuffer(forItemTime: requested) {
                    var actual = CMTime.invalid
                    if let buffer = output.copyPixelBuffer(forItemTime: requested, itemTimeForDisplay: &actual) {
                        let after = player.currentTime().seconds, afterRate = player.rate
                        let afterControl = player.timeControlStatus.rawValue, afterUptime = ProcessInfo.processInfo.systemUptime
                        frames[index].merge(["state": "first-buffer", "actualPTSValue": actual.value,
                            "actualPTSTimescale": actual.timescale, "actualPTSSeconds": finite(actual.seconds),
                            "currentAfterSeconds": finite(after), "rateAfter": finite(Double(afterRate)),
                            "controlAfter": afterControl, "afterUptime": afterUptime,
                            "readyForDisplay": controller.isReadyForDisplay]) { _, new in new }
                        // COMPLETE_OBJECT_LOCAL_BEGIN pts-flags
                        if localContext != nil {
                            frames[index].merge(["actualPTSFlags": actual.flags.rawValue,
                                "actualPTSEpoch": actual.epoch]) { _, new in new }
                        }
                        // COMPLETE_OBJECT_LOCAL_END pts-flags
                        frames[index].merge(["pixelFormat": CVPixelBufferGetPixelFormatType(buffer),
                            "width": CVPixelBufferGetWidth(buffer), "height": CVPixelBufferGetHeight(buffer),
                            "sourceStride": CVPixelBufferGetBytesPerRow(buffer),
                            "sourceAllocationBytes": CVPixelBufferGetDataSize(buffer)]) { _, new in new }
                        var copyStarted: Double?, copyEnded: Double?
                        let owned = plainOwnedBGRA(buffer, retainedBytes: rawBytes, retainedCount: ownedSnapshots.count,
                            copyStartedUptime: &copyStarted, copyEndedUptime: &copyEnded)
                        frames[index]["copyStartedUptime"] = copyStarted.map { finite($0) } ?? NSNull()
                        frames[index]["copyEndedUptime"] = copyEnded.map { finite($0) } ?? NSNull()
                        guard let owned = owned else {
                            XCTFail("Plain first buffer requires a bounded independent BGRA copy with preserved attachments"); return
                        }
                        // Retain the first snapshot before any later gate; never retry for a better frame.
                        ownedSnapshots.append((index: index, name: name, buffer: owned.buffer))
                        rawBytes += owned.allocationBytes
                        frames[index].merge(["ownedStride": owned.stride, "rawBytes": owned.allocationBytes,
                            "imageAttachmentsPreserved": true, "exportState": "pending"]) { _, new in new }
                        let colors = try XCTUnwrap(plainDecodedOutputColors(buffer), "Plain output must contain readable BGRA pixels")
                        frames[index].merge(["samples": colors.samples, "populatedColors": colors.populated,
                            "largestBucket": colors.largest]) { _, new in new }
                        let expectedRate: Float = paused ? 0 : 1.5
                        let expectedControl = paused ? AVPlayer.TimeControlStatus.paused.rawValue : AVPlayer.TimeControlStatus.playing.rawValue
                        guard after.isFinite, actual.seconds.isFinite, after >= target, after <= target + 0.75,
                              abs(actual.seconds - before) <= 0.75, abs(actual.seconds - after) <= 0.75,
                              beforeRate == expectedRate, afterRate == expectedRate,
                              beforeControl == expectedControl, afterControl == expectedControl,
                              afterUptime < captureDeadline, ProcessInfo.processInfo.systemUptime < softDeadline else {
                            XCTFail("Plain first buffer failed media alignment, native transport or soft deadline checks"); return
                        }
                        guard colors.populated >= 16, colors.largest < colors.samples * 9 / 10 else {
                            XCTFail("Plain first buffer is nearly uniform; inspect the retained decoded PNG"); return
                        }
                        frames[index]["state"] = "decoded-output-gates-passed"
                        captured = true; break
                    }
                }
                try await poll()
            }
            guard captured else { XCTFail("Plain item emitted no first new buffer within its soft capture budget"); return }
        }
        captureCompleted = true; summary["stage"] = "capture-complete"
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
        let inlineHost = try XCTUnwrap(retained.owner)
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
            if attempt == 1 {
                try await assertCompactPageSheetKeepsFullscreenOwner(
                    video: video, player: player, item: item, retained: retained,
                    fullscreenHost: fullscreenHost, inlineHost: inlineHost)
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
        assertSupersededFullscreenHostCannotReclaim(retained: retained, player: player,
                                                   item: item, inline: inline, inlineHost: inlineHost)
    }

    private func assertCompactPageSheetKeepsFullscreenOwner(
        video: NativeStudyPlayer, player: AVPlayer, item: AVPlayerItem,
        retained: RetainedStudyPlayerController, fullscreenHost: StudyPlayerHostController,
        inlineHost: StudyPlayerHostController
    ) async throws {
        let parent = try XCTUnwrap(fullscreenHost.parent)
        parent.setOverrideTraitCollection(UITraitCollection(verticalSizeClass: .compact), forChild: fullscreenHost)
        defer { parent.setOverrideTraitCollection(nil, forChild: fullscreenHost) }
        XCTAssertEqual(fullscreenHost.traitCollection.verticalSizeClass, .compact)
        let original = player.currentTime()
        let sheet = UIViewController()
        sheet.view.backgroundColor = .systemBackground
        sheet.modalPresentationStyle = .pageSheet // The production speed selector's UIKit presentation style.
        defer { sheet.dismiss(animated: false) }
        fullscreenHost.present(sheet, animated: false)
        await waitForPresentation { sheet.view.window != nil }
        XCTAssertTrue(retained.owner === fullscreenHost)
        XCTAssertTrue(retained.controller.parent === fullscreenHost)
        XCTAssertTrue(retained.controller.player === player && player.currentItem === item)
        inlineHost.viewDidAppear(false) // An inline callback while covered cannot steal fullscreen.
        XCTAssertTrue(retained.owner === fullscreenHost)
        XCTAssertEqual(player.currentTime().seconds, original.seconds, accuracy: 0.005)
        XCTAssertEqual(player.rate, 0)
        XCTAssertNil(video.problem)
        sheet.dismiss(animated: false)
        await waitForPresentation { sheet.presentingViewController == nil && fullscreenHost.view.window != nil }
        XCTAssertTrue(retained.owner === fullscreenHost)
        XCTAssertTrue(retained.controller.parent === fullscreenHost)
        XCTAssertTrue(retained.controller.player === player && player.currentItem === item)
        XCTAssertEqual(player.currentTime().seconds, original.seconds, accuracy: 0.005)
    }

    private func assertSupersededFullscreenHostCannotReclaim(
        retained: RetainedStudyPlayerController, player: AVPlayer, item: AVPlayerItem,
        inline: UIViewController, inlineHost: StudyPlayerHostController
    ) {
        let first = StudyPlayerHostController(role: .fullscreen)
        inline.addChild(first)
        inline.view.addSubview(first.view)
        first.didMove(toParent: inline)
        first.bind(retained)
        XCTAssertTrue(retained.owner === first)
        let newer = StudyPlayerHostController(role: .fullscreen)
        inline.addChild(newer)
        inline.view.addSubview(newer.view)
        newer.didMove(toParent: inline)
        newer.bind(retained)
        XCTAssertTrue(retained.owner === newer)
        first.viewDidAppear(false) // A delayed or cancelled old appearance cannot re-register A.
        XCTAssertTrue(retained.owner === newer)
        first.release() // A stale end also cannot detach B.
        XCTAssertTrue(retained.owner === newer)
        newer.viewWillDisappear(true)
        newer.viewDidAppear(false) // B's own cancelled disappearance retains its authorization.
        XCTAssertTrue(retained.owner === newer)
        XCTAssertTrue(retained.controller.parent === newer)
        XCTAssertTrue(retained.controller.player === player && player.currentItem === item)
        newer.release()
        XCTAssertTrue(retained.owner === inlineHost)
        for host in [newer, first] {
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
        }
    }

    private func assertNativeCommandsSupersedeAppSeek(_ video: NativeStudyPlayer, player: AVPlayer, item: AVPlayerItem) async throws {
        #if DEBUG
        enum DiagnosticPhase: String, Encodable {
            case source, sink, appIssued, nativeIssued, nativeAwaitResumed, pendingWaitResumed, commandFinished
        }
        struct DiagnosticEvent: Encodable {
            let sequence: Int
            let command: Int
            let phase: DiagnosticPhase
            let origin: NativeStudyPlayer.SeekPublicationDiagnostic.Origin?
            let decision: NativeStudyPlayer.SeekPublicationDiagnostic.Decision?
            let sourceSeconds: Double?
            let emittedSeconds: Int?
            let actualAtSink: Double?
            let sinkSequence: Int?
            let pendingSeek: Bool
            let completionSucceeded: Bool?
            let revisionMatches: Bool?
        }
        struct DiagnosticAttachment: Encodable {
            let schema: Int
            let maxEvents: Int
            let maxBytes: Int
            let truncated: Bool
            let droppedEvents: Int
            let nonFiniteNumbers: Int
            let unavailable: Bool
            let completed: Bool
            let events: [DiagnosticEvent]
        }
        let maxDiagnosticEvents = 256, maxDiagnosticBytes = 64 * 1024
        var diagnosticEvents: [DiagnosticEvent] = []
        var diagnosticCommand = -1, diagnosticSequence = 0, diagnosticDropped = 0, diagnosticNonFinite = 0
        var diagnosticCompleted = false
        var lastSinkSequence: Int?
        @MainActor @discardableResult func record(
            _ phase: DiagnosticPhase, source: NativeStudyPlayer.SeekPublicationDiagnostic? = nil,
            sourceSeconds: Double? = nil, emittedSeconds: Int? = nil, actualAtSink: Double? = nil,
            sinkSequence: Int? = nil, revisionMatches: Bool? = nil
        ) -> Int {
            diagnosticSequence += 1
            guard diagnosticEvents.count < maxDiagnosticEvents else {
                diagnosticDropped += 1
                return diagnosticSequence
            }
            let sample = source?.sourceSeconds ?? sourceSeconds
            if let sample = sample, !sample.isFinite { diagnosticNonFinite += 1 }
            if let actualAtSink = actualAtSink, !actualAtSink.isFinite { diagnosticNonFinite += 1 }
            diagnosticEvents.append(.init(sequence: diagnosticSequence, command: diagnosticCommand, phase: phase,
                origin: source?.origin, decision: source?.decision,
                sourceSeconds: sample.flatMap { $0.isFinite ? $0 : nil },
                emittedSeconds: source?.emittedSeconds ?? emittedSeconds,
                actualAtSink: actualAtSink.flatMap { $0.isFinite ? $0 : nil }, sinkSequence: sinkSequence,
                pendingSeek: source?.pendingSeek ?? (video.pendingSeek != nil),
                completionSucceeded: source?.completionSucceeded, revisionMatches: source?.revisionMatches ?? revisionMatches))
            return diagnosticSequence
        }
        video.seekPublicationObserver = { source in
            // The original synchronous sink runs before this post-assignment source event.
            record(.source, source: source, sinkSequence: source.decision == .published ? lastSinkSequence : nil)
            if source.decision == .published { lastSinkSequence = nil }
        }
        defer {
            video.seekPublicationObserver = nil
            let encoder = JSONEncoder()
            func encode() -> Data? {
                try? encoder.encode(DiagnosticAttachment(schema: 1, maxEvents: maxDiagnosticEvents,
                    maxBytes: maxDiagnosticBytes, truncated: diagnosticDropped > 0,
                    droppedEvents: diagnosticDropped, nonFiniteNumbers: diagnosticNonFinite,
                    unavailable: diagnosticEvents.isEmpty || diagnosticNonFinite > 0,
                    completed: diagnosticCompleted, events: diagnosticEvents))
            }
            var bytes = encode()
            while let encoded = bytes, encoded.count > maxDiagnosticBytes, !diagnosticEvents.isEmpty {
                diagnosticEvents.removeLast(); diagnosticDropped += 1
                bytes = encode()
            }
            // A fixed fallback makes an encoding failure explicit without exporting exception text.
            let data = bytes ?? Data("{\"schema\":1,\"unavailable\":true,\"completed\":false,\"truncated\":true,\"events\":[]}".utf8)
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "Native seek publication attribution"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        #endif
        let native = try XCTUnwrap(player as? StudyAVPlayer)
        XCTAssertTrue(item is StudyAVPlayerItem)
        for command in 0..<3 {
            #if DEBUG
            diagnosticCommand = command
            #endif
            let target = CMTime(seconds: 44.375 + Double(command) * 20, preferredTimescale: 600)
            var published: [(seconds: Int?, actual: Double)] = []
            let publication = video.$seconds.dropFirst().sink {
                let actual = player.currentTime().seconds
                published.append(($0, actual))
                #if DEBUG
                lastSinkSequence = record(.sink, emittedSeconds: $0, actualAtSink: actual)
                #endif
            }
            defer { publication.cancel() }
            video.seek(to: target)
            XCTAssertNotNil(video.pendingSeek, "The app seek must still be in flight")
            let appRevision = native.intentRevision
            #if DEBUG
            record(.appIssued, sourceSeconds: target.seconds)
            #endif
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
            #if DEBUG
            record(.nativeIssued, sourceSeconds: command < 2 ? newerTarget.seconds : nil,
                   revisionMatches: newerRevision == appRevision)
            #endif
            await fulfillment(of: [sought], timeout: 15)
            #if DEBUG
            record(.nativeAwaitResumed)
            #endif
            await waitForPresentation { video.pendingSeek == nil }
            #if DEBUG
            record(.pendingWaitResumed)
            #endif
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
                if command < 2 {
                    XCTAssertFalse(published.contains {
                        $0.seconds == Int(target.seconds) &&
                            abs($0.actual - newerTarget.seconds) <= 0.05
                    }, "An obsolete app target must not publish after the newer native position takes effect")
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            #if DEBUG
            record(.commandFinished)
            #endif
        }
        #if DEBUG
        diagnosticCompleted = true
        #endif
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
    private func plainOwnedBGRA(_ source: CVPixelBuffer, retainedBytes: Int, retainedCount: Int,
                                copyStartedUptime: inout Double?, copyEndedUptime: inout Double?)
        -> (buffer: CVPixelBuffer, allocationBytes: Int, stride: Int)? {
        let width = CVPixelBufferGetWidth(source), height = CVPixelBufferGetHeight(source)
        let maxCopy = 4 * 1024 * 1024, maxRetained = 16 * 1024 * 1024
        guard CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_32BGRA,
              !CVPixelBufferIsPlanar(source), CVPixelBufferGetPlaneCount(source) == 0,
              width == 1280, height == 720, retainedCount >= 0, retainedCount < 4,
              retainedBytes >= 0, retainedBytes <= maxRetained - maxCopy else { return nil }
        let (rowBytes, rowOverflow) = width.multipliedReportingOverflow(by: 4)
        let sourceStride = CVPixelBufferGetBytesPerRow(source), sourceAllocation = CVPixelBufferGetDataSize(source)
        let (sourceRows, sourceOverflow) = sourceStride.multipliedReportingOverflow(by: height)
        guard !rowOverflow, !sourceOverflow, rowBytes > 0, sourceStride >= rowBytes,
              sourceRows > 0, sourceRows <= sourceAllocation, sourceAllocation <= maxCopy else { return nil }
        copyStartedUptime = ProcessInfo.processInfo.systemUptime
        defer { copyEndedUptime = ProcessInfo.processInfo.systemUptime }
        guard CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        var created: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &created) == kCVReturnSuccess,
              let owned = created, owned !== source,
              CVPixelBufferGetWidth(owned) == width, CVPixelBufferGetHeight(owned) == height,
              CVPixelBufferGetPixelFormatType(owned) == kCVPixelFormatType_32BGRA,
              !CVPixelBufferIsPlanar(owned), CVPixelBufferGetPlaneCount(owned) == 0 else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(owned), allocation = CVPixelBufferGetDataSize(owned)
        let (rows, overflow) = stride.multipliedReportingOverflow(by: height)
        guard !overflow, stride >= rowBytes, rows > 0, rows <= allocation,
              allocation <= maxCopy, allocation <= maxRetained - retainedBytes,
              CVPixelBufferLockBaseAddress(owned, []) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(owned, []) }
        guard let sourceBase = CVPixelBufferGetBaseAddress(source), let base = CVPixelBufferGetBaseAddress(owned),
              base != sourceBase else { return nil }
        base.initializeMemory(as: UInt8.self, repeating: 0, count: rows)
        for row in 0..<height {
            base.advanced(by: row * stride).copyMemory(from: sourceBase.advanced(by: row * sourceStride), byteCount: rowBytes)
        }
        // Keep Core Image's original buffer interpretation, including each attachment's propagation mode.
        CVBufferRemoveAllAttachments(owned)
        CVBufferPropagateAttachments(source, owned)
        for mode in [CVAttachmentMode.shouldPropagate, .shouldNotPropagate] {
            if let attachments = CVBufferCopyAttachments(source, mode) {
                if mode == .shouldNotPropagate { CVBufferSetAttachments(owned, attachments, mode) }
                guard let copied = CVBufferCopyAttachments(owned, mode), CFEqual(attachments, copied) else { return nil }
            } else if CVBufferCopyAttachments(owned, mode) != nil { return nil }
        }
        return (buffer: owned, allocationBytes: allocation, stride: stride)
    }
    private func plainDecodedOutputColors(_ buffer: CVPixelBuffer) -> (populated: Int, largest: Int, samples: Int)? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
              CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        guard width >= 64, height >= 36, stride >= width * 4,
              let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var colors: [Int: Int] = [:]
        for row in 0..<36 {
            let y = height / 10 + (2 * row + 1) * (height - height / 5) / 72
            for column in 0..<64 {
                let x = width / 10 + (2 * column + 1) * (width - width / 5) / 128
                let offset = y * stride + x * 4
                let color = (Int(bytes[offset + 2]) >> 4) << 8 | (Int(bytes[offset + 1]) >> 4) << 4 | (Int(bytes[offset]) >> 4)
                colors[color, default: 0] += 1
            }
        }
        return (colors.values.filter { $0 >= 4 }.count, colors.values.max() ?? 0, 64 * 36)
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
