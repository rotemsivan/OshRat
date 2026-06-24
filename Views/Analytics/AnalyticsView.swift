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

    /// Build the report from the current query results. Cheap to recompute
    /// — this is a hand-entered ledger, not a bank feed — so we don't cache.
    private func makeReport() -> AnalyticsReport {
        AnalyticsReport(
            transactions: transactions,
            accounts: accounts,
            preferredCurrency: profiles.first?.preferredCurrencyCode ?? "ILS",
            fxSnapshot: fxSnapshots.first
        )
    }

    // MARK: - Roadmap

    private func roadmap(_ report: AnalyticsReport) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                AnalyticsHeaderView(report: report)
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
    }

    /// The ordered list of stations. Kept explicit (rather than a
    /// data-driven loop) because each station feeds on a different slice
    /// of the report and renders a different card — the index/symbol it's
    /// given here is what drives its medallion number and the side its
    /// card swings to.
    private func stations(_ report: AnalyticsReport) -> some View {
        VStack(spacing: 0) {
            RoadmapStationView(index: 0, total: Self.stationCount, symbol: "calendar") {
                MonthlyStationView(report: report)
            }
            RoadmapStationView(index: 1, total: Self.stationCount, symbol: "chart.bar.fill") {
                YearlyStationView(report: report)
            }
            RoadmapStationView(index: 2, total: Self.stationCount, symbol: "arrow.left.arrow.right") {
                ComparisonStationView(report: report)
            }
            RoadmapStationView(index: 3, total: Self.stationCount, symbol: "chart.pie.fill") {
                CategoryStationView(report: report)
            }
            RoadmapStationView(index: 4, total: Self.stationCount, symbol: "scalemass.fill") {
                NeedsWantsStationView(report: report)
            }
            RoadmapStationView(index: 5, total: Self.stationCount, symbol: "trophy.fill") {
                RecordsStationView(report: report)
            }
            RoadmapStationView(index: 6, total: Self.stationCount, symbol: "building.columns.fill") {
                AssetsStationView(report: report)
            }
        }
    }

    private static let stationCount = 7

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
                .padding(isLeading ? .trailing : .leading, Self.cardSwing)
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
