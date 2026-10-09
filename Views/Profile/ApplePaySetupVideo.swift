import AVFoundation
import SwiftUI

/// The Apple Pay setup, shown rather than told: a looping, muted video of the
/// whole automation being built on an iPhone, with the current step's text
/// under it in sync. `ApplePaySetupView` puts it where the numbered list used
/// to be.
///
/// **Two cuts, one per iPhone language.** The app itself is Hebrew-only, but
/// the Shortcuts app follows the *phone's* language — someone with an English
/// iPhone sees "Run Immediately", not "הפעלה מיידית". So the video comes in a
/// Hebrew-iPhone and an English-iPhone version, toggled by the picker above it.
/// It starts on whichever matches the device (`Locale.preferredLanguages`
/// reports the phone's languages even though the app is pinned to Hebrew) and
/// remembers a manual choice. The step captions stay the app's own Hebrew
/// `stepTexts`, which already name both languages ("**הבא** (Next)").
///
/// **The video carries no text of its own**, so the caption is real text:
/// Dynamic Type, VoiceOver, and one source of truth with the check card's
/// step numbers. Tapping a step's number jumps the video there.
///
/// The videos are rendered from the Remotion project in
/// claude-code-video-toolkit (`projects/oshrat-applepay-shortcut`,
/// compositions `AppEmbed-he` / `AppEmbed-en`). `stepStarts` comes from that
/// project's timeline (`node scripts/chapters.ts`) — re-render both videos and
/// update it together if a step changes.
struct ApplePaySetupVideo: View {
    /// `ApplePaySetupView.stepTexts` — one caption per step.
    let steps: [LocalizedStringKey]

    /// Seconds into either video where each step begins. Both cuts share one
    /// timeline, so switching language keeps the place.
    static let stepStarts: [Double] = [0, 5.33, 8.27, 15.67, 23.2, 28.7, 37.47, 41.0]

    @AppStorage("applePaySetupVideoLanguage") private var language: PhoneLanguage = .deviceDefault
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var player = SetupVideoPlayer(stepStarts: Self.stepStarts)
    @ScaledMetric(relativeTo: .caption) private var badgeSize: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            languagePicker
            video
            stepStrip
            caption
        }
        .onAppear {
            assert(steps.count == Self.stepStarts.count, "One start time per step")
            player.load(language.fileName)
            // With Reduce Motion on, nothing moves until asked to.
            if !reduceMotion { player.play() }
        }
        .onDisappear { player.pause() }
        .onChange(of: language) { _, new in player.load(new.fileName) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player.pause() }
        }
    }

    // MARK: - Pieces

    private var languagePicker: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("שפת האייפון")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Picker("שפת האייפון", selection: $language) {
                ForEach(PhoneLanguage.allCases) { lang in
                    Text(lang.label).tag(lang)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var video: some View {
        PlayerLayerView(player: player.queue)
            .aspectRatio(4 / 5, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Theme.Colors.videoBackdrop)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(alignment: .bottomLeading) { playPauseButton }
            .onTapGesture { player.togglePlayback() }
            .accessibilityElement()
            .accessibilityLabel(Text("סרטון הדגמה של ההגדרה"))
            .accessibilityValue(Text("שלב \(player.currentStep + 1) מתוך \(steps.count)"))
            .accessibilityAddTraits(.startsMediaSession)
            .accessibilityAction { player.togglePlayback() }
    }

    private var playPauseButton: some View {
        Button {
            player.togglePlayback()
        } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentTransition(.symbolEffect(.replace))
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .padding(Theme.Spacing.sm)
        .accessibilityLabel(Text(player.isPlaying ? "השהיה" : "הפעלה"))
    }

    /// One numbered dot per step; the current one is filled. Tapping jumps there.
    private var stepStrip: some View {
        HStack(spacing: 0) {
            ForEach(steps.indices, id: \.self) { index in
                let isCurrent = index == player.currentStep
                Button {
                    player.seek(toStep: index)
                } label: {
                    Text(index + 1, format: .number)
                        .font(Theme.Typography.caption.weight(.bold))
                        .foregroundStyle(isCurrent ? .white : Theme.Colors.accent)
                        .frame(width: badgeSize, height: badgeSize)
                        .background {
                            Circle()
                                .fill(isCurrent ? Theme.Colors.accent : Theme.Colors.accent.opacity(0.12))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("שלב \(index + 1)"))
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
        .animation(.snappy, value: player.currentStep)
    }

    /// The current step's text. Every caption is laid out (all but one
    /// hidden) so the card is as tall as the longest one and doesn't jump.
    private var caption: some View {
        ZStack(alignment: .topLeading) {
            ForEach(steps.indices, id: \.self) { index in
                Text(steps[index])
                    .font(Theme.Typography.bodySmall)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(index == player.currentStep ? 1 : 0)
                    .accessibilityHidden(index != player.currentStep)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: player.currentStep)
    }
}

// MARK: - Language

/// The language of the user's iPhone — which Shortcuts labels they'll see.
enum PhoneLanguage: String, CaseIterable, Identifiable {
    case hebrew = "he"
    case english = "en"

    var id: Self { self }

    var label: String {
        switch self {
        case .hebrew: "עברית"
        case .english: "English"
        }
    }

    /// Bundled video, in `OshRat/Videos/`.
    var fileName: String { "ApplePaySetup-\(rawValue)" }

    /// Hebrew if the phone's first language is Hebrew, English otherwise.
    static var deviceDefault: PhoneLanguage {
        Locale.preferredLanguages.first?.hasPrefix("he") ?? true ? .hebrew : .english
    }
}

// MARK: - Player

/// A muted, looping player that reports which step is on screen.
///
/// `init` only stores the step times: SwiftUI evaluates a `@State`
/// initialiser every time the parent rebuilds the view and throws all but the
/// first result away, so the AVFoundation objects are made on first use
/// (`queue`), on the one instance that survives.
@Observable
final class SetupVideoPlayer {
    private(set) var isPlaying = false
    private(set) var currentStep = 0

    private let stepStarts: [Double]
    @ObservationIgnored private var player: AVQueuePlayer?
    @ObservationIgnored private var looper: AVPlayerLooper?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var loadedFile: String?
    /// Bumped by every step jump; the time observer stays out of the caption
    /// until the newest jump has landed. Without it, a tick reporting the
    /// position *before* the jump set the old step back for a moment, and the
    /// caption flickered.
    @ObservationIgnored private var seekGeneration = 0
    @ObservationIgnored private var isSeeking = false

    init(stepStarts: [Double]) {
        self.stepStarts = stepStarts
    }

    var queue: AVQueuePlayer {
        if let player { return player }
        let player = AVQueuePlayer()
        // The videos have no sound; muting as well keeps any future cut from
        // talking over the user's music.
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        self.player = player
        return player
    }

    /// Swaps in a language's video, keeping the current position.
    func load(_ file: String) {
        guard file != loadedFile,
              let url = Bundle.main.url(forResource: file, withExtension: "mp4") else { return }
        let resumeAt = loadedFile == nil ? .zero : queue.currentTime()
        loadedFile = file
        looper?.disableLooping()
        queue.removeAllItems()
        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
        if resumeAt > .zero {
            queue.seek(to: resumeAt, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        observeTime()
    }

    func play() {
        queue.play()
        isPlaying = true
    }

    func pause() {
        queue.pause()
        isPlaying = false
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func seek(toStep index: Int) {
        guard stepStarts.indices.contains(index) else { return }
        currentStep = index
        seekGeneration += 1
        let generation = seekGeneration
        isSeeking = true
        let time = CMTime(seconds: stepStarts[index], preferredTimescale: 600)
        queue.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                // A later jump owns the flag now; leave it to that one.
                guard let self, generation == self.seekGeneration else { return }
                self.isSeeking = false
            }
        }
        play()
    }

    /// Four times a second is plenty to keep the caption in step.
    private func observeTime() {
        guard timeObserver == nil else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = queue.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isSeeking else { return }
                let seconds = time.seconds
                let step = self.stepStarts.lastIndex { $0 <= seconds + 0.05 } ?? 0
                if step != self.currentStep { self.currentStep = step }
            }
        }
    }
}

/// An `AVPlayerLayer` without the system controls — the video is an
/// illustration here, not something to scrub through.
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PlayerUIView, context: Context) {}

    final class PlayerUIView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
