import SwiftUI
import AVFoundation
import WhimIPhone

/// A short walkthrough with reserved slots for setup photos or videos. Assignments remain in Apple's system UI.
struct QuickCaptureSetupView: View {
    @State private var page = 0
    var isWatch = false
    var onPageChange: (Int) -> Void = { _ in }
    @State private var controlCenter = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let route = QuickCaptureGuide.currentRoute
    private var actionButton: Bool { route == .actionButton && !isWatch }

    private var titles: [String] {
        if isWatch { return ["A Note from your wrist", "Make room for Whim", "Tap. Talk. Done."] }
        if actionButton { return ["A button for your thoughts", "Set up your Action button"] }
        if controlCenter { return ["One swipe away", "Add Whim", "Ready when you are"] }
        return ["Capture from your Lock Screen", "Make room for Whim", "Ready when you are"]
    }
    private var details: [String] {
        if isWatch { return [
            "Install Whim from the Watch app on iPhone. Open it on your Watch and allow microphone access.",
            "Hold your watch face, tap Edit, then swipe to Complications. Choose a slot that supports Whim.",
            "Select Record a Whim and press the Digital Crown. Tap the complication to record; tap Stop in Whim to finish."
        ] }
        if actionButton { return [
            "Your iPhone has an Action button. Set it up once, then press and hold to capture a thought.",
            "Open Settings → Action Button → Controls → Choose a Control. Select Whim’s Record a Whim control. Press and hold to record; invoke it again to stop and save your Note."
        ] }
        if controlCenter { return [
            "Open Control Center, then touch and hold an empty area to edit your controls.",
            "Tap Add a Control. Search for Whim and choose Record a Whim.",
            "Tap the Whim control to start recording. Tap it again to stop and save your Note."
        ] }
        return [
            "Unlock your iPhone, then hold the Lock Screen. Tap Customize → Lock Screen.",
            "Remove a bottom control with the minus button. Tap the empty slot and search for Whim.",
            "Choose Record a Whim, then tap Done. Use the control to start recording, and again to stop and save."
        ]
    }
    var body: some View {
        if isWatch || route != nil { guide }
    }
    private var guide: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(isWatch ? "Apple Watch" : actionButton ? "Action button" : controlCenter ? "Control Center" : "Lock Screen")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(page + 1) of \(titles.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let name = QuickCaptureGuide.mediaName(route: route, isWatch: isWatch, page: page),
               let url = Bundle.main.url(forResource: name, withExtension: "mp4") {
                SetupDemoVideo(url: url, title: titles[page])
                    .frame(height: page == 0 ? 230 : 300)
                    .id(name)
            } else { mediaPlaceholder }
            VStack(alignment: .leading, spacing: 12) {
                Text(titles[page]).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text(details[page]).font(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("setup-instruction")
            HStack(spacing: 16) {
                if page > 0 && !actionButton {
                    Button("Previous") { advance(-1) }.buttonStyle(OnboardingSecondaryButtonStyle())
                }
                if page < titles.count - 1 {
                    Button(page == 0 ? "Show me how" : "Next step", systemImage: "arrow.right") { advance(1) }
                        .buttonStyle(OnboardingPrimaryButtonStyle())
                } else if !actionButton {
                    Button("Read again", systemImage: "arrow.counterclockwise") { page = 0 }
                        .buttonStyle(OnboardingSecondaryButtonStyle())
                }
            }
            if page == titles.count - 1 {
                Text("Allow microphone access before trying it. Your first Note is saved normally.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if route == .lockScreen && !isWatch {
                Button(controlCenter ? "Use the Lock Screen instead" : "Use Control Center instead") {
                    controlCenter.toggle(); page = 0
                }.font(.subheadline).foregroundStyle(.white)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(isWatch ? "watch-capture-setup" : "quick-capture-setup")
        .onAppear { onPageChange(page) }
        .onChange(of: page) { _, value in onPageChange(value) }
    }
    private func advance(_ offset: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { page += offset }
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    private var mediaPlaceholder: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(white: 0.055))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(white: 0.25), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
            }
            .overlay {
                VStack(spacing: 8) {
                    Text("Setup demo").font(.headline)
                    Text("Image or short video").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 230)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Setup demo placeholder, step \(page + 1)")
            .accessibilityIdentifier("setup-media-placeholder")
    }
}


private struct SetupDemoVideo: View {
    let url: URL
    let title: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var playing = false
    @State private var replay = 0

    var body: some View {
        SetupDemoPlayer(url: url, playing: playing && scenePhase == .active, replay: replay)
            .overlay(alignment: .bottomTrailing) {
                if !playing {
                Button {
                    replay += 1
                    playing = true
                } label: {
                    Label("Play again", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(.black.opacity(0.7), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityIdentifier("replay-setup-demo")
                .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title + " video demonstration")
            .accessibilityIdentifier("setup-demo-video")
            .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { notification in
                guard let item = notification.object as? AVPlayerItem,
                      let asset = item.asset as? AVURLAsset, asset.url == url else { return }
                playing = false
            }
            .onAppear { playing = !reduceMotion }
            .onDisappear { playing = false }
            .onChange(of: reduceMotion) { _, reduced in if reduced { playing = false } }
    }
}

private struct SetupDemoPlayer: UIViewRepresentable {
    let url: URL
    let playing: Bool
    let replay: Int

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        let player = AVPlayer()
        var replay = 0
        init(url: URL) {
            super.init(frame: .zero)
            backgroundColor = .black
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            player.actionAtItemEnd = .pause
            let playerLayer = layer as! AVPlayerLayer
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspect
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
    func makeUIView(context: Context) -> PlayerView { PlayerView(url: url) }
    func updateUIView(_ view: PlayerView, context: Context) {
        if view.replay != replay {
            view.replay = replay
            view.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        if playing { view.player.play() } else { view.player.pause() }
    }
    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.player.pause()
        view.player.replaceCurrentItem(with: nil)
    }
}
