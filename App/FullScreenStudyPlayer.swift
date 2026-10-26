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
    func makeUIViewController(context: Context) -> MountedFullScreenPlayer {
        let container = MountedFullScreenPlayer()
        container.bind(video)
        return container
    }
    func updateUIViewController(_ controller: MountedFullScreenPlayer, context: Context) {}
    static func dismantleUIViewController(_ controller: MountedFullScreenPlayer, coordinator: ()) {
        controller.endPresentation()
        (controller.playerController.player as? StudyAVPlayer)?.trace(.fullscreenDetached)
    }
}

// UIKit owns appearance and rotation forwarding for this ordinary container and its stock AVKit child.
final class MountedFullScreenPlayer: UIViewController {
    let playerController = AVPlayerViewController()
    private weak var video: NativeStudyPlayer?
    private var presentation = UUID()
    private var displayObservation: NSKeyValueObservation?
    private var appeared = false
    private var reportedMount = false
    private var reportedReady = false

    func bind(_ video: NativeStudyPlayer) {
        endPresentation()
        self.video = video
        presentation = UUID()
        reportedMount = false; reportedReady = false
        video.bindFullScreenPlayer(to: playerController, presentation: presentation)
        if isViewLoaded { observeDisplay(); checkMount() }
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        playerController.showsPlaybackControls = true
        playerController.view.accessibilityIdentifier = "fullscreen-native-player"
        addChild(playerController)
        playerController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playerController.view)
        NSLayoutConstraint.activate([
            playerController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playerController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            playerController.view.topAnchor.constraint(equalTo: view.topAnchor),
            playerController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        playerController.didMove(toParent: self)
        let status = PlayerRenderStatusView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        status.video = video; status.controller = playerController
        status.backgroundColor = .clear; status.isUserInteractionEnabled = false
        status.isAccessibilityElement = true
        status.accessibilityIdentifier = "fullscreen-video-render-status"
        status.accessibilityLabel = "播放画面状态"
        playerController.view.addSubview(status)
        observeDisplay()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        appeared = true
        checkMount()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        checkMount()
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        appeared = false
        endPresentation()
    }
    func endPresentation() {
        displayObservation = nil
        video?.endFullScreenPresentation(presentation)
    }
    private func observeDisplay() {
        displayObservation = playerController.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.checkMount() }
        }
    }
    private func checkMount() {
        guard appeared, view.window != nil, !view.bounds.isEmpty, !playerController.view.bounds.isEmpty else { return }
        if !reportedMount {
            reportedMount = true
            (playerController.player as? StudyAVPlayer)?.trace(.fullscreenMounted)
        }
        if playerController.isReadyForDisplay && !reportedReady {
            reportedReady = true
            (playerController.player as? StudyAVPlayer)?.trace(.fullscreenDisplayReady)
        }
        video?.fullScreenMounted(presentation, displayReady: playerController.isReadyForDisplay)
    }
}

// The accessible status reads the actual controller/owner at query time: no cached completion flag.
// Keep AVPlayerViewController itself stock and retain its existing accessible transport children.
private final class PlayerRenderStatusView: UIView {
    weak var video: NativeStudyPlayer?
    weak var controller: AVPlayerViewController?
    override var accessibilityValue: String? {
        get {
            guard let video = video, let controller = controller, controller.player === video.player,
                  let item = controller.player?.currentItem, video.ready, video.problem == nil,
                  item.status == .readyToPlay else { return "画面尚未就绪" }
            if video.pendingSeek != nil || video.waitingForFullScreenRestoration { return "正在定位播放时间" }
            guard window != nil, controller.isReadyForDisplay else { return "正在显示画面" }
            var ancestor: UIViewController? = controller
            while let current = ancestor {
                if current.isBeingPresented || current.isBeingDismissed || current.transitionCoordinator != nil {
                    return "正在调整画面"
                }
                ancestor = current.parent
            }
            return video.playing || controller.player?.timeControlStatus != .paused ? "画面已就绪 · 播放中" : "画面已就绪 · 已暂停"
        }
        set { } // Status is derived from the real owner/controller, never assigned by callers.
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
