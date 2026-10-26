#if DEBUG
import AVKit
import AVFoundation
import CoreImage
import CoreVideo
import ImageIO
import QuartzCore
import UniformTypeIdentifiers

/// Explicit UI-test experiment only. The output can perturb AVFoundation; it is never a repair.
@MainActor final class SameItemRenderDiagnostic: NSObject {
    static let flag = "--same-item-render-diagnostics"
    static let directoryName = "same-item-render"
    static let maxSamples = 8
    static let maxPNGBytes = 4 * 1024 * 1024
    static let maxMetadataBytes = 64 * 1024
    private static var nextGeneration = 0
    private static var sampleCount = 0
    private static let writer = DispatchQueue(label: "garden.ui-test-render", qos: .utility)
    private weak var attachment: RetainedStudyPlayerController?
    private weak var item: AVPlayerItem?
    private let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ])
    private let generation: Int
    private let root: URL
    private var sequence = 0
    private let button = UIButton(type: .system)

    static func make(_ attachment: RetainedStudyPlayerController) -> SameItemRenderDiagnostic? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing"), arguments.contains(flag),
              attachment.controller.player?.currentItem != nil else { return nil }
        return SameItemRenderDiagnostic(attachment)
    }

    private init(_ attachment: RetainedStudyPlayerController) {
        Self.nextGeneration += 1
        generation = Self.nextGeneration
        self.attachment = attachment
        item = attachment.controller.player?.currentItem
        root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Self.directoryName, isDirectory: true)
        super.init()
        item?.add(output) // The SAME actual UI item; no substitute player, seek or transport command.
        let root = self.root
        let reset = generation == 1
        Self.writer.async {
            if reset { try? FileManager.default.removeItem(at: root) }
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        button.setTitle("取帧", for: .normal)
        button.backgroundColor = .black
        button.accessibilityIdentifier = "same-item-render-capture"
        button.accessibilityValue = "0"
        button.addTarget(self, action: #selector(capture), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        attachment.controller.view.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: attachment.controller.view.leadingAnchor, constant: 4),
            button.topAnchor.constraint(equalTo: attachment.controller.view.topAnchor, constant: 4),
            button.widthAnchor.constraint(equalToConstant: 44), button.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    func invalidate() {
        button.removeFromSuperview()
        item?.remove(output)
        item = nil
        attachment = nil
    }

    private static func time(_ value: CMTime) -> [String: Any] {
        ["value": value.value, "timescale": value.timescale, "flags": value.flags.rawValue,
         "epoch": value.epoch, "seconds": value.seconds.isFinite ? value.seconds as Any : NSNull()]
    }

    @objc private func capture() {
        guard Self.sampleCount < Self.maxSamples, let attachment = attachment, let item = item,
              attachment.video?.retainedController === attachment,
              let player = attachment.controller.player, player === attachment.video?.player,
              player.currentItem === item else { return }
        sequence += 1
        Self.sampleCount += 1
        let uptime = ProcessInfo.processInfo.systemUptime
        let hostTime = CACurrentMediaTime()
        let requested = output.itemTime(forHostTime: hostTime)
        var display = CMTime.invalid
        let hasNew = output.hasNewPixelBuffer(forItemTime: requested)
        let buffer = hasNew ? output.copyPixelBuffer(forItemTime: requested, itemTimeForDisplay: &display) : nil
        let controller = attachment.controller
        let bounds = controller.view.bounds
        var row: [String: Any] = [
            "generation": generation, "player": generation, "item": generation, "controller": generation,
            "identityNamespace": "same-item-render-launch-local", "sequence": sequence,
            "uptime": uptime, "hostTime": hostTime, "currentTime": Self.time(player.currentTime()),
            "requestedItemTime": Self.time(requested), "itemTimeForDisplay": Self.time(display),
            "rate": player.rate, "controlStatus": player.timeControlStatus.rawValue,
            "itemStatus": item.status.rawValue, "hasNewBuffer": hasNew, "bufferCopied": buffer != nil,
            "readyForDisplay": controller.isReadyForDisplay,
            "parentIsOwner": controller.parent === attachment.owner,
            "ownerInline": attachment.owner?.role == .inline, "inWindow": controller.view.window != nil,
            "bounds": [Double(bounds.origin.x), Double(bounds.origin.y), Double(bounds.width), Double(bounds.height)]
        ]
        if let description = item.asset.tracks(withMediaType: .video).first?.formatDescriptions.first {
            row["codecFourCC"] = CMFormatDescriptionGetMediaSubType(description as! CMFormatDescription)
        }
        if let buffer = buffer {
            row["pixelWidth"] = CVPixelBufferGetWidth(buffer)
            row["pixelHeight"] = CVPixelBufferGetHeight(buffer)
            row["pixelFormat"] = CVPixelBufferGetPixelFormatType(buffer)
        }
        // Immediate receipt is paired to the UI screenshot; PNG completion is separately recorded.
        if let receipt = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) {
            button.accessibilityValue = String(data: receipt, encoding: .utf8)
        }
        let sample = sequence, generation = self.generation, metadata = row, root = self.root
        let maxPNGBytes = Self.maxPNGBytes, maxRecordBytes = Self.maxMetadataBytes / Self.maxSamples
        Self.writer.async {
            var result = metadata
            result["pngWritten"] = false
            if let buffer = buffer, CVPixelBufferGetWidth(buffer) <= 1920,
               CVPixelBufferGetHeight(buffer) <= 1080 {
                let frame = CIImage(cvPixelBuffer: buffer)
                if let image = CIContext().createCGImage(frame, from: frame.extent) {
                    let data = NSMutableData()
                    if let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) {
                        CGImageDestinationAddImage(destination, image, nil)
                        if CGImageDestinationFinalize(destination), data.length <= maxPNGBytes {
                            let name = "g\(generation)-s\(sample).png"
                            do {
                                try (data as Data).write(to: root.appendingPathComponent(name), options: .atomic)
                                result["pngWritten"] = true; result["png"] = name; result["pngBytes"] = data.length
                            } catch { result["pngWriteFailed"] = true }
                        } else { result["pngSizeOrEncodingLimit"] = true }
                    }
                }
            } else if buffer != nil { result["pixelDimensionLimit"] = true }
            result["writeUptime"] = ProcessInfo.processInfo.systemUptime
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
               data.count <= maxRecordBytes {
                try? data.write(to: root.appendingPathComponent("g\(generation)-s\(sample).json"), options: .atomic)
            }
        }
    }
}
#endif
