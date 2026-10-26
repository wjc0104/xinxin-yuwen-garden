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
    func makeUIViewController(context: Context) -> StudyPlayerHostController {
        let host = StudyPlayerHostController(role: .fullscreen)
        host.bind(video.retainedController)
        return host
    }
    func updateUIViewController(_ host: StudyPlayerHostController, context: Context) {
        host.bind(video.retainedController)
    }
    static func dismantleUIViewController(_ host: StudyPlayerHostController, coordinator: ()) {
        host.release()
    }
}

struct NativeInlinePlayer: UIViewControllerRepresentable {
    let video: NativeStudyPlayer
    func makeUIViewController(context: Context) -> StudyPlayerHostController {
        let host = StudyPlayerHostController(role: .inline)
        host.bind(video.retainedController)
        return host
    }
    func updateUIViewController(_ host: StudyPlayerHostController, context: Context) {
        host.bind(video.retainedController)
    }
    static func dismantleUIViewController(_ host: StudyPlayerHostController, coordinator: ()) {
        host.release()
    }
}

enum StudyPlayerHostRole: Equatable {
    case inline, fullscreen
}

// Each representable returns its own ordinary UIKit container. Only the retained
// stock AVKit child moves between them; a stale host cannot claim a new generation.
@MainActor final class StudyPlayerHostController: UIViewController {
    let role: StudyPlayerHostRole
    private(set) var attachment: RetainedStudyPlayerController?

    init(role: StudyPlayerHostRole) {
        self.role = role
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        attachment?.refresh(self)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        attachment?.refresh(self) // Only the registered host can recover a cancelled dismissal.
        if role == .fullscreen, attachment?.fullscreenMounted == true {
            (attachment?.controller.player as? StudyAVPlayer)?.trace(.fullscreenMounted)
        }
    }
    func bind(_ next: RetainedStudyPlayerController?) {
        guard attachment !== next else { return }
        release()
        attachment = next
        loadViewIfNeeded()
        next?.register(self)
    }
    func release() {
        attachment?.end(self)
        attachment = nil
    }
}

@MainActor final class RetainedStudyPlayerController {
    weak var video: NativeStudyPlayer?
    let controller: AVPlayerViewController
    private weak var inlineHost: StudyPlayerHostController?
    private weak var waitingInlineHost: StudyPlayerHostController?
    private weak var fullscreenHost: StudyPlayerHostController?
    private(set) weak var owner: StudyPlayerHostController?
    private var invalidated = false

    init(video: NativeStudyPlayer, player: StudyAVPlayer) {
        self.video = video
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = true
        controller.player = player // The sole binding for this AVPlayer generation.
        self.controller = controller
        let status = PlayerRenderStatusView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        status.video = video
        status.controller = controller
        status.attachment = self
        status.backgroundColor = .clear
        status.isUserInteractionEnabled = false
        status.isAccessibilityElement = true
        status.accessibilityIdentifier = "fullscreen-video-render-status"
        status.accessibilityLabel = "播放画面状态"
        controller.view.addSubview(status)
    }

    private var isCurrent: Bool {
        !invalidated && video?.retainedController === self &&
            controller.player === video?.player
    }

    func register(_ host: StudyPlayerHostController) {
        guard isCurrent else { return }
        switch host.role {
        case .inline:
            if let current = inlineHost, current !== host, current.isViewLoaded,
               current.view.window != nil {
                waitingInlineHost = host
                return
            }
            inlineHost = host
            guard fullscreenHost == nil else { return }
        case .fullscreen:
            fullscreenHost = host
        }
        attach(to: host)
    }

    func refresh(_ host: StudyPlayerHostController) {
        guard isCurrent else { return }
        switch host.role {
        case .inline:
            guard inlineHost === host, fullscreenHost == nil else { return }
        case .fullscreen:
            guard fullscreenHost === host else { return }
        }
        attach(to: host)
    }

    func end(_ host: StudyPlayerHostController) {
        switch host.role {
        case .inline:
            if waitingInlineHost === host { waitingInlineHost = nil }
            guard inlineHost === host else { return }
            inlineHost = nil
            if let waiting = waitingInlineHost, waiting.isViewLoaded,
               waiting.view.window != nil {
                inlineHost = waiting
                waitingInlineHost = nil
            }
        case .fullscreen:
            guard fullscreenHost === host else { return }
            fullscreenHost = nil
        }
        if owner === host { detach() }
        if host.role == .inline, fullscreenHost == nil, isCurrent,
           let inlineHost = inlineHost { attach(to: inlineHost) }
        if host.role == .fullscreen, isCurrent,
           let inlineHost = inlineHost, inlineHost.isViewLoaded,
           inlineHost.view.window != nil {
            attach(to: inlineHost)
        }
    }

    func invalidate() {
        invalidated = true
        detach()
        inlineHost = nil
        waitingInlineHost = nil
        fullscreenHost = nil
    }

    private func attach(to host: StudyPlayerHostController) {
        guard isCurrent, host.isViewLoaded else { return }
        if owner === host { return }
        detach()
        host.addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        controller.view.accessibilityIdentifier =
            host.role == .fullscreen ? "fullscreen-native-player" : "native-video-player"
        host.view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: host.view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: host.view.bottomAnchor)
        ])
        controller.didMove(toParent: host)
        owner = host
    }

    private func detach() {
        guard controller.parent != nil else { owner = nil; return }
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
        owner = nil
    }

    var fullscreenMounted: Bool {
        isCurrent && owner === fullscreenHost && owner?.role == .fullscreen &&
            controller.parent === owner && controller.view.window != nil &&
            !controller.view.bounds.isEmpty
    }
}

// The status is derived from the actual retained controller and its current UIKit owner.
private final class PlayerRenderStatusView: UIView {
    weak var video: NativeStudyPlayer?
    weak var controller: AVPlayerViewController?
    weak var attachment: RetainedStudyPlayerController?
    override var accessibilityValue: String? {
        get {
            guard let video = video, let controller = controller, let attachment = attachment,
                  attachment.fullscreenMounted, controller.player === video.player,
                  let item = controller.player?.currentItem, video.ready, video.problem == nil,
                  item.status == .readyToPlay else { return "画面尚未就绪" }
            if video.pendingSeek != nil { return "正在定位播放时间" }
            guard controller.isReadyForDisplay else { return "正在显示画面" }
            var ancestor: UIViewController? = controller
            while let current = ancestor {
                if current.isBeingPresented || current.isBeingDismissed || current.transitionCoordinator != nil {
                    return "正在调整画面"
                }
                ancestor = current.parent
            }
            if controller.player?.timeControlStatus == .paused && controller.player?.rate == 0 {
                return "画面已就绪 · 已暂停"
            }
            if controller.player?.timeControlStatus == .playing && (controller.player?.rate ?? 0) > 0 {
                return "画面已就绪 · 播放中"
            }
            return "正在显示画面"
        }
        set { }
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
