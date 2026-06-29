import SwiftUI
import SwiftData

/// Whether the enclosing roadmap station has scrolled into view and
/// finished its reveal. Bars and figures read this to grow in sync with
/// the station instead of animating off-screen. Defaults to `true` so a
/// station's content shown outside the roadmap (previews, etc.) is fully
/// drawn.
private struct StationRevealedKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var stationRevealed: Bool {
        get { self[StationRevealedKey.self] }
        set { self[StationRevealedKey.self] = newValue }
    }
}

/// The analytics screen — a vertical, gamified "financial journey".
///
/// The page is laid out as a roadmap: a central thread of numbered
/// medallions, with content cards swinging to alternating sides as the
/// user scrolls down. It reads *gradually*, from the basics at the top
/// (this month, this year) toward richer insight further down
/// (month-over-month comparison, spending by category, needs vs wants,
/// personal records, and finally the asset mix).
///
/// All the number-crunching lives in `AnalyticsReport`; this view just
/// feeds the right slice of it into each station and animates them in.
struct AnalyticsView: View {
    // Live rows only — soft-deleted accounts/transactions (see
    // `TrashService`) are excluded from every analytic.
    @Query(filter: #Predicate<Transaction> { $0.deletedAt == nil }, sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]
    @Query(filter: #Predicate<Account> { $0.deletedAt == nil }, sort: \Account.name)
    private var accounts: [Account]
    @Query private var profiles: [UserProfile]
    @Query(sort: \FXRateSnapshot.fetchedAt, order: .reverse) private var fxSnapshots: [FXRateSnapshot]

    /// The month/year the roadmap is scoped to. Defaults to the current
    /// month; the selector at the top steps it and toggles month ⇄ year.
    @State private var period = AnalyticsPeriod.current()

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            let report = makeReport()
            if report.hasAnyData {
                roadmap(report)
            } else {
                AnalyticsEmptyStateView()
            }
        }
        .navigationTitle(Text("תובנות"))
        .navigationBarTitleDisplayMode(.large)
    }

    /// Build the report from the current query results for the selected
    /// period. Cheap to recompute — this is a hand-entered ledger, not a bank
    /// feed — so we don't cache, and it just re-runs when `period` changes.
    private func makeReport() -> AnalyticsReport {
        AnalyticsReport(
            transactions: transactions,
            accounts: accounts,
            preferredCurrency: profiles.first?.preferredCurrencyCode ?? "ILS",
            fxSnapshot: fxSnapshots.first,
            period: period
        )
    }

    // MARK: - Roadmap

    private func roadmap(_ report: AnalyticsReport) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                AnalyticsHeaderView(report: report)
                    .padding(.bottom, Theme.Spacing.md)

                AnalyticsPeriodSelector(period: $period)
                    .padding(.bottom, Theme.Spacing.lg)

                stations(report)

                if report.fxUnavailable {
                    fxFootnote
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            // Clear the floating bottom bar + the home button that pops out
            // of its notch, same reservation the dashboard scroll uses.
            .padding(.bottom, HomeBottomBar.barHeight + HomeBottomBar.homeButtonDiameter + Theme.Spacing.lg)
        }
        .scrollIndicators(.hidden)
        // The roadmap mascot — a rat that perches on the lowest visible card and
        // hops to the next as you scroll — is fully implemented but currently
        // hidden from the app. Flip `showsRoadmapMascot` to bring it back.
        // (When shown, each card publishes its bounds via an anchor and the
        // overlay resolves them into the ScrollView's space to place the rat.)
        .overlayPreferenceValue(StationBoundsKey.self) { anchors in
            GeometryReader { proxy in
                if Self.showsRoadmapMascot {
                    let frames = anchors.reduce(into: [Int: CGRect]()) { result, entry in
                        result[entry.key] = proxy[entry.value]
                    }
                    RoadmapMascot(
                        cardFrames: frames,
                        viewportHeight: proxy.size.height,
                        stationCount: Self.stationCount
                    )
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// The roadmap mascot (`RoadmapMascot`) is implemented but hidden for now —
    /// set this to `true` to show the rat that hops between the station cards.
    private static let showsRoadmapMascot = false

    /// The ordered list of stations. Kept explicit (rather than a
    /// data-driven loop) because each station feeds on a different slice
    /// of the report and renders a different card — the index/symbol it's
    /// given here is what drives its medallion number and the side its
    /// card swings to.
    private func stations(_ report: AnalyticsReport) -> some View {
        VStack(spacing: 0) {
            RoadmapStationView(index: 0, total: Self.stationCount, symbol: "chart.pie.fill") {
                CategoryStationView(report: report)
            }
            RoadmapStationView(index: 1, total: Self.stationCount, symbol: "scalemass.fill") {
                NeedsWantsStationView(report: report)
            }
            RoadmapStationView(index: 2, total: Self.stationCount, symbol: "arrow.up.arrow.down") {
                IncomeExpenseStationView(report: report)
            }
            RoadmapStationView(index: 3, total: Self.stationCount, symbol: "arrow.left.arrow.right") {
                ComparisonStationView(report: report)
            }
            // Full width (no swing): record rows carry a title *and* an amount
            // side by side, so they need the extra room to both stay legible.
            RoadmapStationView(index: 4, total: Self.stationCount, symbol: "trophy.fill", swing: 0) {
                RecordsStationView(report: report)
            }
            RoadmapStationView(index: 5, total: Self.stationCount, symbol: "building.columns.fill") {
                AssetsStationView(report: report)
            }
        }
    }

    private static let stationCount = 6

    private var fxFootnote: some View {
        Text("חלק מהסכומים לא הומרו — שערי חליפין לא זמינים כרגע.")
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Spacing.md)
    }
}

// MARK: - Station container

/// One stop on the roadmap: a centred numbered medallion threaded onto the
/// vertical path, with its content card swinging to an alternating side.
///
/// Each station reveals itself with a spring as it scrolls into view
/// (`onScrollVisibilityChange`), which gives the page its game-like
/// "unlocking the next level" feel. The reveal collapses to a plain fade
/// when *Reduce Motion* is on.
private struct RoadmapStationView<Content: View>: View {
    let index: Int
    let total: Int
    let symbol: String
    /// Override for how far the card swings off-centre. `nil` uses the default
    /// alternating swing; pass `0` for a station whose content needs the full
    /// width (e.g. the records list, where each row carries a title *and* an
    /// amount side by side).
    var swing: CGFloat? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// Even stations swing to the leading edge (visual right under RTL),
    /// odd ones to the trailing edge — that alternation is what makes the
    /// path read as a winding road instead of a flat list.
    private var isLeading: Bool { index.isMultiple(of: 2) }
    private var isFirst: Bool { index == 0 }
    private var isLast: Bool { index == total - 1 }

    /// How far the card is pushed away from centre. Big enough to read as
    /// a deliberate swing, small enough that the card stays comfortably
    /// wide for amounts and bars. Computed (not stored) because Swift
    /// doesn't allow static stored properties on a generic type.
    private static var cardSwing: CGFloat { 44 }

    private var shown: Bool { appeared || reduceMotion }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            StationMedallion(
                number: index + 1,
                symbol: symbol,
                showConnector: !isFirst,
                highlighted: shown
            )

            content()
                .frame(maxWidth: .infinity)
                // Report the *card's* on-screen rect (measured here, before the
                // swing padding, so it's the real card surface) keyed by index,
                // so the mascot overlay can perch on this card.
                .anchorPreference(key: StationBoundsKey.self, value: .bounds) { [index: $0] }
                .padding(isLeading ? .trailing : .leading, swing ?? Self.cardSwing)
                // Let bars/figures inside the card grow in step with the
                // station's reveal rather than the moment the ScrollView
                // eagerly built them off-screen.
                .environment(\.stationRevealed, shown)
        }
        .padding(.bottom, isLast ? 0 : Theme.Spacing.lg)
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown ? 1 : 0.94, anchor: .top)
        .offset(y: shown ? 0 : 28)
        .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.82), value: appeared)
        .onScrollVisibilityChange(threshold: 0.12) { visible in
            // Latch to true on first sighting so the reveal plays once and
            // the station doesn't flicker as the user scrolls back past it.
            if visible { appeared = true }
        }
    }
}

// MARK: - Medallion

/// The numbered node on the roadmap thread. A themed SF Symbol inside an
/// accent disc, a small "level" number badge, and a short connector that
/// links it up to the previous station.
private struct StationMedallion: View {
    let number: Int
    let symbol: String
    let showConnector: Bool
    let highlighted: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showConnector {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Theme.Colors.accent.opacity(0.15), Theme.Colors.accent.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 4, height: Theme.Spacing.lg)
            }

            disc
        }
    }

    private var disc: some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(
                Circle().fill(
                    LinearGradient(
                        colors: [Theme.Colors.accent, Theme.Colors.accent.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(
                // Soft halo that brightens once the station has been
                // revealed — a quiet "unlocked" cue.
                Circle().stroke(Theme.Colors.accent.opacity(highlighted ? 0.30 : 0), lineWidth: 6)
            )
            .overlay(alignment: .topTrailing) { numberBadge }
            .shadow(color: Theme.Colors.accent.opacity(0.30), radius: 8, x: 0, y: 4)
            .accessibilityElement()
            .accessibilityLabel(Text("תחנה \(number)"))
    }

    private var numberBadge: some View {
        Text("\(number)")
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.Colors.accent)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Theme.Colors.surface))
            .overlay(Circle().stroke(Theme.Colors.accent.opacity(0.4), lineWidth: 1))
            .offset(x: 4, y: -4)
    }
}

// MARK: - Header

/// Friendly intro at the top of the roadmap: a trophy mascot, a title, and
/// a one-line "how many entries you've logged" stat to set the tone.
private struct AnalyticsHeaderView: View {
    let report: AnalyticsReport

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.Colors.accent, Theme.Colors.accent.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .accessibilityHidden(true)

            Text("המסע הפיננסי שלי")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("כל הסיפור שמאחורי המספרים — תחנה אחר תחנה.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            if report.totalTransactions > 0 {
                Label("\(report.totalTransactions) תנועות תועדו", systemImage: "checkmark.seal.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Capsule().fill(Theme.Colors.accent.opacity(0.12)))
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Period selector

/// The scope control at the top of the roadmap: a segmented חודש/שנה toggle
/// plus a ‹ label › stepper to move between periods. The chevrons are
/// direction-aware (`backward`/`forward`), so they mirror correctly under RTL;
/// stepping forward stops at the live period — there's no data in the future.
private struct AnalyticsPeriodSelector: View {
    @Binding var period: AnalyticsPeriod

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Picker("תקופה", selection: $period.scope) {
                ForEach(AnalyticsPeriod.Scope.allCases) { scope in
                    Text(scope.hebrewLabel).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 240)

            HStack(spacing: Theme.Spacing.lg) {
                stepButton(systemImage: "chevron.backward", label: "התקופה הקודמת") {
                    period = period.previous(calendar)
                }

                Text(period.label(calendar))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .monospacedDigit()
                    .frame(minWidth: 150)

                let canForward = period.canStepForward(calendar: calendar)
                stepButton(systemImage: "chevron.forward", label: "התקופה הבאה") {
                    period = period.next(calendar)
                }
                .disabled(!canForward)
                .opacity(canForward ? 1 : 0.3)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: period)
    }

    private func stepButton(
        systemImage: String,
        label: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Scroll companion

/// Lets every station card publish its bounds (keyed by station index) so the
/// mascot overlay can read the cards' live on-screen positions as they scroll.
private struct StationBoundsKey: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The rat mascot that *perches on the station cards* and hops between them.
///
/// It sits on the top-right corner of the lowest card currently on screen.
/// While that stays the active card the rat rides along, glued to the corner as
/// the card scrolls; the moment the next card scrolls into view the rat springs
/// across to it — a discrete card-to-card hop, down when scrolling down, up when
/// scrolling up. It starts on the first card and ends on the last (the assets
/// summary). Each hop also plays a little performance via `keyframeAnimator`:
/// legs tuck then splay, head nods, tail flicks, body squashes-and-stretches.
///
/// `cardFrames` are the cards' rects already resolved into the scroll
/// viewport's coordinate space, so they update continuously as the user scrolls.
///
/// Purely decorative: `allowsHitTesting(false)` is set by the caller and the
/// rig is hidden from VoiceOver.
private struct RoadmapMascot: View {
    let cardFrames: [Int: CGRect]
    let viewportHeight: CGFloat
    let stationCount: Int

    /// The card the rat is perched on. Changing it fires the hop.
    @State private var activeStation = 0

    /// Tuned to perch on a card corner without burying its content. The
    /// full-body art is 360×660, so height follows from the width.
    private let width: CGFloat = 52
    private var height: CGFloat { width * (660.0 / 360.0) }

    var body: some View {
        rig
            .position(perch)
            // Hidden until the cards' frames are known, so it doesn't flash at
            // the origin on first layout.
            .opacity(cardFrames.isEmpty ? 0 : 1)
            // Only the card *change* springs (the hop). While the active card
            // merely scrolls, `perch` tracks it directly with no animation, so
            // the rat stays glued to the corner.
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: activeStation)
            .onChange(of: lowestVisibleStation) { _, newStation in
                activeStation = newStation
            }
    }

    /// The rig plus its in-place hop choreography (legs / head / tail / squash),
    /// replayed each time `activeStation` changes. The magic numbers are tuning
    /// knobs — bump the angles or squash factors to taste.
    private var rig: some View {
        Color.clear
            .frame(width: width, height: height)
            .keyframeAnimator(initialValue: HopState(), trigger: activeStation) { _, hop in
                RatRig(legTuck: hop.legTuck, headTilt: hop.headTilt, tailFlick: hop.tailFlick)
                    .frame(width: width, height: height)
                    .scaleEffect(x: hop.squashX, y: hop.squashY, anchor: .bottom)
                    .shadow(color: .black.opacity(0.16), radius: 5, x: 0, y: 3)
                    .accessibilityHidden(true)
            } keyframes: { _ in
                KeyframeTrack(\.squashY) {
                    CubicKeyframe(0.84, duration: 0.10)   // crouch
                    CubicKeyframe(1.12, duration: 0.16)   // stretch up
                    CubicKeyframe(0.92, duration: 0.16)   // land squash
                    SpringKeyframe(1.0, duration: 0.30)
                }
                KeyframeTrack(\.squashX) {
                    CubicKeyframe(1.12, duration: 0.10)
                    CubicKeyframe(0.92, duration: 0.16)
                    CubicKeyframe(1.05, duration: 0.16)
                    SpringKeyframe(1.0, duration: 0.30)
                }
                KeyframeTrack(\.legTuck) {
                    CubicKeyframe(-24, duration: 0.18)    // tuck for the leap
                    CubicKeyframe(14, duration: 0.16)     // splay to land
                    SpringKeyframe(0, duration: 0.30)
                }
                KeyframeTrack(\.headTilt) {
                    CubicKeyframe(9, duration: 0.18)
                    CubicKeyframe(-5, duration: 0.18)
                    SpringKeyframe(0, duration: 0.30)
                }
                KeyframeTrack(\.tailFlick) {
                    CubicKeyframe(20, duration: 0.22)
                    SpringKeyframe(0, duration: 0.40)
                }
            }
    }

    /// The card the rat should be perched on: the highest-index card whose top
    /// has risen above the trigger line (so it's substantially in view). When
    /// the last card's bottom comes on screen we lock onto it, so the journey
    /// always *ends* on the assets card even if it's short.
    private var lowestVisibleStation: Int {
        let lastIndex = stationCount - 1
        if let last = cardFrames[lastIndex], last.maxY <= viewportHeight + 1 {
            return lastIndex
        }
        let triggerLine = viewportHeight * 0.6
        let reached = cardFrames.filter { $0.value.minY < triggerLine }.keys
        return reached.max() ?? 0
    }

    /// Centre point that perches the rat on the active card's top-right corner,
    /// feet just onto the card top, clamped to stay within the viewport.
    private var perch: CGPoint {
        let rect = cardFrames[activeStation] ?? .zero
        // A fixed offset from *this* card's own top-left corner, identical for
        // every card — so the corner moves with the card (wider/narrower, swung
        // either way) but the rat always lands the same distance in from it.
        // Key point: we pin the rat's *edge* (not its centre) a fixed distance
        // inside the corner, so it never drifts into the margin on the inset
        // cards. (RTL ⇒ the card's visual-left edge is `maxX`; +Y is downward.)
        //   • insetIntoCard  — the rat's left edge, this far inside the corner
        //   • centreAboveTop — the rat's centre, this far above the top edge
        let insetIntoCard: CGFloat = 8
        let centreAboveTop: CGFloat = 14
        let centerX = rect.maxX - insetIntoCard - width / 2
        let centerY = rect.minY - centreAboveTop
        return CGPoint(x: centerX, y: centerY)
    }
}

/// The interpolated state of a single hop. Angles are in degrees; the squash
/// factors are multipliers around 1.0.
private struct HopState {
    var legTuck: Double = 0
    var headTilt: Double = 0
    var tailFlick: Double = 0
    var squashX: CGFloat = 1
    var squashY: CGFloat = 1
}

/// The articulated rat: its body parts are separate layers, each drawn on the
/// shared 360×660 canvas so they stack pixel-perfect, rotated around their own
/// joints. Anchors are the joint positions as fractions of the canvas — hips
/// for the legs, the neck for the head, the base for the tail.
private struct RatRig: View {
    /// Hip rotation in degrees; applied with opposite sign per leg so they
    /// tuck/splay symmetrically.
    var legTuck: Double = 0
    /// Head nod/tilt in degrees, pivoting at the neck.
    var headTilt: Double = 0
    /// Tail sway in degrees, pivoting at its base.
    var tailFlick: Double = 0

    var body: some View {
        ZStack {
            part("rat-part-tail")
                .rotationEffect(.degrees(tailFlick), anchor: UnitPoint(x: 0.556, y: 0.706))
            part("rat-part-leg-left")
                .rotationEffect(.degrees(-legTuck), anchor: UnitPoint(x: 0.458, y: 0.659))
            part("rat-part-leg-right")
                .rotationEffect(.degrees(legTuck), anchor: UnitPoint(x: 0.542, y: 0.659))
            part("rat-part-body")
            part("rat-part-head")
                .rotationEffect(.degrees(headTilt), anchor: UnitPoint(x: 0.556, y: 0.382))
        }
    }

    private func part(_ name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
    }
}

// MARK: - Empty state

/// Shown to a brand-new user who hasn't entered anything yet — there's
/// nothing to analyse, so we nudge them toward adding data.
private struct AnalyticsEmptyStateView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "chart.line.flattrend.xyaxis")
                .font(.system(size: 44))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("עוד אין מספיק נתונים")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("הוסיפו חשבונות ותנועות כדי לפתוח את מסלול התובנות.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        AnalyticsView()
    }
    .environment(\.layoutDirection, .rightToLeft)
    .modelContainer(
        for: [
            UserProfile.self, Account.self, Holding.self, Category.self,
            Transaction.self, TransactionAttachment.self, BudgetItem.self, Goal.self, FXRateSnapshot.self
        ],
        inMemory: true
    )
}
