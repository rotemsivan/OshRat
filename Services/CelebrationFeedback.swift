import AVFoundation
import CoreHaptics

/// The app's celebration sounds and the haptic patterns that go with them.
///
/// Four moments, rising in size: a new transaction gets one warm tone, an
/// achievement a two-note steel-drum phrase (a sibling phrase for gold), a
/// level-up four plucked-string notes. The sounds are CC0
/// assets by Kenney, prepared by `Scripts/prepare_sounds.py` (credits in
/// `Scripts/SOUNDS_CREDITS.md`) — an earlier, synthesised set came out thin
/// and sharp. Each haptic taps exactly on its sound's notes; the script prints
/// the note onsets, so a new sound means re-timing `taps` to match.
///
/// Gentle by construction:
/// - **Ambient audio session.** The chimes obey the ring/silent switch, and
///   mix with whatever is already playing instead of pausing someone's music.
/// - **Crisp taps, never a buzz.** Every haptic is a short transient on a
///   note, building to a clearly stronger final tap — the shape of Apple's
///   own "success" feedback and Apple Pay's confirmation. No continuous
///   events: a long, low-sharpness vibration is what a cheap buzzer motor
///   does, and that's exactly how the previous swell felt.
/// - **No haptics hardware, no vibration** — silently, not as an error.
///
/// There's no mute toggle yet; one is on the planned Settings list (see
/// CLAUDE.md). Until then the silent switch is the off switch for the sound.
@MainActor
final class CelebrationFeedback {

    static let shared = CelebrationFeedback()

    enum Moment: CaseIterable {
        case transactionLogged
        /// Bronze and silver patches, and the batch toast.
        case achievement
        /// Gold patches — the rarest, so they get their own phrase.
        case goldAchievement
        case levelUp

        fileprivate var soundName: String {
            switch self {
            case .transactionLogged: return "celebration-transaction"
            case .achievement:       return "celebration-achievement"
            case .goldAchievement:   return "celebration-achievement-gold"
            case .levelUp:           return "celebration-levelup"
            }
        }

        /// One tap per note: (seconds from start, intensity, sharpness).
        /// Times are the note onsets `Scripts/prepare_sounds.py` prints.
        fileprivate var taps: [(time: TimeInterval, intensity: Float, sharpness: Float)] {
            switch self {
            case .transactionLogged:
                // One firm, clean tap — like pressing a good physical button.
                return [(0.00, 0.80, 0.60)]
            case .achievement:
                // Light, then strong: the "success" rhythm.
                return [(0.00, 0.55, 0.50), (0.13, 1.00, 0.70)]
            case .goldAchievement:
                // The same rhythm, firmer and crisper from the first tap.
                return [(0.00, 0.70, 0.60), (0.14, 1.00, 0.85)]
            case .levelUp:
                // Climbing with the notes to a decisive last tap.
                return [(0.00, 0.45, 0.45), (0.13, 0.60, 0.50), (0.25, 0.75, 0.60), (0.36, 1.00, 0.75)]
            }
        }
    }

    private var players: [Moment: AVAudioPlayer] = [:]
    private var hapticEngine: CHHapticEngine?
    private var isPrepared = false

    private init() {}

    /// Play a moment's sound and haptic together. Cheap to call; the first
    /// call sets things up.
    func play(_ moment: Moment) {
        prepareIfNeeded()
        if let player = players[moment] {
            player.currentTime = 0
            player.play()
        }
        playHaptic(for: moment)
    }

    // MARK: - Setup

    private func prepareIfNeeded() {
        guard !isPrepared else { return }
        isPrepared = true

        // `.ambient` is what makes the chimes polite: silenced by the silent
        // switch, and mixed with other audio rather than interrupting it.
        try? AVAudioSession.sharedInstance().setCategory(.ambient)

        for moment in Moment.allCases {
            guard let url = Bundle.main.url(forResource: moment.soundName, withExtension: "caf"),
                  let player = try? AVAudioPlayer(contentsOf: url)
            else { continue }
            player.prepareToPlay()
            players[moment] = player
        }

        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = try? CHHapticEngine()
        else { return }
        engine.playsHapticsOnly = true
        // Lets the engine power down between celebrations; `play` restarts it.
        engine.isAutoShutdownEnabled = true
        // The system can reset the engine (e.g. after the app was
        // backgrounded); restart it so the next pattern still plays.
        engine.resetHandler = { [weak engine] in
            try? engine?.start()
        }
        hapticEngine = engine
    }

    private func playHaptic(for moment: Moment) {
        guard let engine = hapticEngine else { return }
        let events = moment.taps.map { tap in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: tap.intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: tap.sharpness),
                ],
                relativeTime: tap.time
            )
        }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // A haptic that can't play is not worth surfacing — the sound and
            // the toast still carry the moment.
        }
    }
}
