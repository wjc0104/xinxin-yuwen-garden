import SwiftUI
import AVKit

/// The existing AVPlayer owns time and playback state across both presentations.
struct FullScreenStudyPlayer: View {
    @ObservedObject var video: NativeStudyPlayer
    let exit: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let player = video.player { NativeFullScreenPlayer(player: player).ignoresSafeArea() }
            HStack {
                Button(action: exit) {
                    Label("退出全屏", systemImage: "arrow.down.right.and.arrow.up.left")
                        .padding(12).background(Color.black.opacity(0.75)).cornerRadius(12)
                }.accessibilityIdentifier("video-exit-fullscreen")
                Spacer()
                Text(video.seconds.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) } ?? "--:--")
                    .font(.caption.monospacedDigit()).accessibilityIdentifier("fullscreen-video-position")
                PlaybackSpeedMenu(video: video, identifier: "fullscreen-video-speed")
                    .padding(12).background(Color.black.opacity(0.75)).cornerRadius(12)
            }
            .foregroundColor(.white).padding(16)
        }.background(Color.black)
            .background(InterfaceOrientationObservation().allowsHitTesting(false))
            .accessibilityIdentifier("fullscreen-video")
    }
}

struct PlaybackSpeedMenu: View {
    @ObservedObject var video: NativeStudyPlayer
    let identifier: String
    var body: some View {
        Menu {
            ForEach(NativeStudyPlayer.playbackRates, id: \.self) { rate in
                Button { video.setPlaybackRate(rate) } label: {
                    HStack {
                        Text(NativeStudyPlayer.rateLabel(rate) + "×")
                        if video.playbackRate == rate { Image(systemName: "checkmark") }
                    }
                }.accessibilityIdentifier("video-speed-option-" + NativeStudyPlayer.rateLabel(rate))
            }
        } label: { Text("倍速 " + video.playbackRateLabel + "×") }
        .accessibilityIdentifier(identifier)
    }
}

private struct NativeFullScreenPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        // Rotation follows the app's portrait/both-landscape declarations.
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.view.accessibilityIdentifier = "fullscreen-native-player"
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
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
