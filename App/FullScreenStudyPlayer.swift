import SwiftUI
import AVKit

/// The existing AVPlayer owns time and playback state across both presentations.
struct FullScreenStudyPlayer: View {
    let player: AVPlayer
    let exit: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            NativeFullScreenPlayer(player: player).ignoresSafeArea()
            Button(action: exit) {
                Label("退出全屏", systemImage: "arrow.down.right.and.arrow.up.left")
                    .padding(12).background(Color.black.opacity(0.75)).cornerRadius(12)
            }
            .foregroundColor(.white).padding(16).accessibilityIdentifier("video-exit-fullscreen")
        }.background(Color.black).accessibilityIdentifier("fullscreen-video")
    }
}

private struct NativeFullScreenPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> RotatingStudyPlayerController {
        let controller = RotatingStudyPlayerController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.view.accessibilityIdentifier = "fullscreen-native-player"
        return controller
    }
    func updateUIViewController(_ controller: RotatingStudyPlayerController, context: Context) {}
}

/// Public iOS 15 rotation support. Rotation still follows the device/OS lock.
private final class RotatingStudyPlayerController: AVPlayerViewController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
    override var shouldAutorotate: Bool { true }
}
