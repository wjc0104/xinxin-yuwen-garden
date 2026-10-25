import SwiftUI
import AVKit

/// The existing AVPlayer owns time and playback state across both presentations.
struct FullScreenStudyPlayer: View {
    @ObservedObject var video: NativeStudyPlayer
    let exit: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if video.player != nil { NativeFullScreenPlayer(video: video).ignoresSafeArea() }
            HStack {
                Button(action: { video.traceTransportState(.fullscreenExit); exit() }) {
                    Label("退出全屏", systemImage: "arrow.down.right.and.arrow.up.left")
                        .padding(12).background(Color.black.opacity(0.75)).cornerRadius(12)
                }.accessibilityIdentifier("video-exit-fullscreen")
                Spacer()
                Text(video.seconds.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) } ?? "--:--")
                    .font(.caption.monospacedDigit()).accessibilityIdentifier("fullscreen-video-position")
                    .accessibilityValue(video.playing ? "播放中 · 实际倍速 " + NativeStudyPlayer.rateLabel(video.player?.rate ?? 0) : "已暂停")
                PlaybackSpeedSelector(video: video, identifier: "fullscreen-video-speed")
                    .background(Color.black.opacity(0.75)).cornerRadius(12)
            }
            .foregroundColor(.white).padding(16)
        }.background(Color.black)
            .background(InterfaceOrientationObservation().allowsHitTesting(false))
            .onAppear { video.traceTransportState(.fullscreenAppeared) }
            .onDisappear { video.traceTransportState(.fullscreenDisappeared) }
    }
}

struct PlaybackSpeedSelector: View {
    @ObservedObject var video: NativeStudyPlayer
    let identifier: String
    @State private var choosingSpeed = false

    var body: some View {
        Button { choosingSpeed = true } label: {
            Text("倍速 " + video.playbackRateLabel + "×")
                .padding(.horizontal, 12).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .sheet(isPresented: $choosingSpeed) { PlaybackSpeedSheet(video: video) }
    }
}

private struct PlaybackSpeedSheet: View {
    @ObservedObject var video: NativeStudyPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(NativeStudyPlayer.playbackRates, id: \.self) { rate in
                        Button {
                            video.setPlaybackRate(rate)
                            dismiss()
                        } label: {
                            HStack {
                                Text(NativeStudyPlayer.rateLabel(rate) + "×")
                                Spacer()
                                if video.playbackRate == rate { Image(systemName: "checkmark") }
                            }
                            .padding(.horizontal, 16).frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("video-speed-option-" + NativeStudyPlayer.rateLabel(rate))
                        .accessibilityValue(video.playbackRate == rate ? "已选中" : "未选中")
                    }
                }.padding(16)
            }
            .navigationTitle("播放倍速")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .navigationViewStyle(.stack)
        .foregroundColor(.primary)
    }
}

private struct NativeFullScreenPlayer: UIViewControllerRepresentable {
    let video: NativeStudyPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        // Rotation follows the app's portrait/both-landscape declarations.
        let controller = AVPlayerViewController()
        video.bindFullScreenPlayer(to: controller)
        controller.showsPlaybackControls = true
        controller.view.accessibilityIdentifier = "fullscreen-native-player"
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) {
        (controller.player as? StudyAVPlayer)?.trace(.fullscreenDetached)
    }
}

/// Public window-scene orientation, exposed for accessibility/native rotation verification.
private struct InterfaceOrientationObservation: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> OrientationController { OrientationController() }
    func updateUIViewController(_ controller: OrientationController, context: Context) {}

    final class OrientationController: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isAccessibilityElement = true
            view.accessibilityIdentifier = "fullscreen-interface-orientation"
            view.accessibilityLabel = "屏幕方向"
        }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); updateOrientation() }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); updateOrientation() }
        override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.updateOrientation() }
        }
        private func updateOrientation() {
            switch view.window?.windowScene?.interfaceOrientation {
            case .landscapeLeft: view.accessibilityValue = "landscapeLeft"
            case .landscapeRight: view.accessibilityValue = "landscapeRight"
            case .portrait: view.accessibilityValue = "portrait"
            case .portraitUpsideDown: view.accessibilityValue = "portraitUpsideDown"
            default: view.accessibilityValue = "unknown"
            }
        }
    }
}
