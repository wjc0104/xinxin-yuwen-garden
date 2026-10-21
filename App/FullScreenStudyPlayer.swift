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
                PlaybackSpeedMenu(video: video, identifier: "fullscreen-video-speed")
                    .padding(12).background(Color.black.opacity(0.75)).cornerRadius(12)
            }
            .foregroundColor(.white).padding(16)
        }.background(Color.black).accessibilityIdentifier("fullscreen-video")
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
