import SwiftUI

// MARK: - Station · Income & expenses

/// Income vs. expenses for the selected period — the split between them, the
/// resulting net, and how many entries were logged. Period-aware: it follows
/// the month/year the user picks at the top of the screen.
struct IncomeExpenseStationView: View {
    let report: AnalyticsReport

    private var isEmpty: Bool {
        report.periodTransactionCount == 0
    }

    var body: some View {
        StationCard(title: "הכנסות והוצאות", subtitle: report.periodLabel) {
            if isEmpty {
                StationEmptyText("לא נרשמו תנועות בתקופה זו.")
            } else {
                VStack(alignment: .trailing, spacing: Theme.Spacing.sm) {
                    AnalyticsAmountRow(title: "הכנסות", amount: report.periodIncome,
                                       code: report.currencyCode, dotColor: Theme.Colors.income)
                    AnalyticsAmountRow(title: "הוצאות", amount: report.periodExpense,
                                       code: report.currencyCode, dotColor: Theme.Colors.expense)

                    SplitBar(segments: [
                        .init(value: report.periodIncome, color: Theme.Colors.income),
                        .init(value: report.periodExpense, color: Theme.Colors.expense)
                    ])

                    NetRow(net: report.periodNet, code: report.currencyCode)

                    Label("\(report.periodTransactionCount) תנועות בתקופה", systemImage: "list.bullet")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }
}

// MARK: - Station · Period-over-period comparison

/// How the selected period stacks up against the one before it (last month /
/// last year), framed encouragingly — spending less or earning more is good.
struct ComparisonStationView: View {
    let report: AnalyticsReport

    private var hasBaseline: Bool {
        report.prevPeriodIncome > 0 || report.prevPeriodExpense > 0
    }

    var body: some View {
        StationCard(title: title) {
            if !hasBaseline {
                StationEmptyText(noBaselineText)
            } else {
                VStack(alignment: .trailing, spacing: Theme.Spacing.md) {
                    TrendRow(label: "הוצאות", fraction: report.expenseChangeFraction,
                             improvesWhenLower: true)
                    TrendRow(label: "הכנסות", fraction: report.incomeChangeFraction,
                             improvesWhenLower: false)

                    if let message = headline {
                        Text(message)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var isMonth: Bool { report.scope == .month }

    private var title: LocalizedStringKey {
        isMonth ? "מול החודש הקודם" : "מול השנה הקודמת"
    }

    private var noBaselineText: LocalizedStringKey {
        isMonth ? "אין חודש קודם להשוואה." : "אין שנה קודמת להשוואה."
    }

    /// A friendly one-liner about the expense trend — the metric the user
    /// most wants to hear about.
    private var headline: String? {
        guard let change = report.expenseChangeFraction else { return nil }
        let percent = abs(change).formatted(.percent.precision(.fractionLength(0)))
        let fromLabel = isMonth ? "מהחודש הקודם" : "מהשנה הקודמת"
        let toLabel = isMonth ? "לחודש הקודם" : "לשנה הקודמת"
        if change < -0.001 {
            return "כל הכבוד! הוצאת \(percent) פחות \(fromLabel)."
        } else if change > 0.001 {
            return "הוצאת \(percent) יותר \(fromLabel) — שווה לשים לב."
        } else {
            return "ההוצאות שלך כמעט זהות \(toLabel)."
        }
    }
}

// MARK: - Station 4 · Where the money goes

/// The spending-by-field breakdown — clothing, bills, groceries… — over
/// the current year, biggest slice first, each with its category colour.
struct CategoryStationView: View {
    let report: AnalyticsReport

    /// Cap the list so the card stays scannable; the long tail rarely adds
    /// insight and would just make the station tall.
    private static let maxRows = 6

    private var slices: [CategorySlice] {
        Array(report.categoryBreakdown.prefix(Self.maxRows))
    }

    var body: some View {
        StationCard(title: "לאן הולך הכסף", subtitle: report.periodLabel) {
            if slices.isEmpty {
                StationEmptyText("אין הוצאות מסווגות בתקופה זו.")
            } else {
                VStack(alignment: .trailing, spacing: Theme.Spacing.md) {
                    ForEach(slices) { slice in
                        CategoryRow(slice: slice, code: report.currencyCode)
                    }
                }
            }
        }
    }
}

// MARK: - Station 5 · Needs vs wants

/// The needs-versus-wants split — the 50/30-style lens that tells the user
/// how much of their spend is essential versus discretionary.
struct NeedsWantsStationView: View {
    let report: AnalyticsReport

    private var total: Decimal { report.needsTotal + report.wantsTotal }
    private var isEmpty: Bool { total == 0 }

    private var needsPercentText: String {
        guard total > 0 else { return "0%" }
        let fraction = (report.needsTotal as NSDecimalNumber).doubleValue
            / (total as NSDecimalNumber).doubleValue
        return fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        StationCard(title: "צרכים מול רצונות", subtitle: report.periodLabel) {
            if isEmpty {
                StationEmptyText("עדיין אין מספיק הוצאות כדי לפצל לצרכים ורצונות.")
            } else {
                VStack(alignment: .trailing, spacing: Theme.Spacing.md) {
                    SplitBar(segments: [
                        .init(value: report.needsTotal, color: Theme.Colors.expense),
                        .init(value: report.wantsTotal, color: Theme.Colors.wants)
                    ], height: 14)

                    AnalyticsAmountRow(title: "צרכים", amount: report.needsTotal,
                                       code: report.currencyCode, dotColor: Theme.Colors.expense)
                    AnalyticsAmountRow(title: "רצונות", amount: report.wantsTotal,
                                       code: report.currencyCode, dotColor: Theme.Colors.wants)

                    Text("\(needsPercentText) מההוצאות שלך הן צרכים חיוניים.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Station 6 · Records

/// The gamified "trophy cabinet": biggest expense, biggest income, top
/// category, busiest and best-saving months — the personal bests.
struct RecordsStationView: View {
    let report: AnalyticsReport

    var body: some View {
        StationCard(title: "השיאים שלי") {
            if report.records.isEmpty {
                StationEmptyText("עדיין אין שיאים — הם יופיעו ככל שתתעדו יותר.")
            } else {
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(report.records) { record in
                        RecordRow(record: record, code: report.currencyCode)
                    }
                }
            }
        }
    }
}

// MARK: - Station 7 · Assets

/// The journey's destination: total net worth and how it's split across
/// account types (cash, savings, investments…).
struct AssetsStationView: View {
    let report: AnalyticsReport

    private var isEmpty: Bool {
        report.assetAllocation.isEmpty && report.netWorth == 0
    }

    var body: some View {
        StationCard(title: "תמונת הנכסים") {
            if isEmpty {
                StationEmptyText("עדיין לא הוספת חשבונות.")
            } else {
                VStack(alignment: .trailing, spacing: Theme.Spacing.md) {
                    VStack(spacing: Theme.Spacing.xxs) {
                        Text("שווי נקי כולל")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(report.netWorth.formattedCurrency(report.currencyCode))
                            .font(Theme.Typography.screenTitle)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)

                    ForEach(report.assetAllocation) { slice in
                        AllocationRow(slice: slice, code: report.currencyCode)
                    }
                }
            }
        }
    }
}

// MARK: - Shared card chrome

/// The common card shell every station uses: an eyebrow title with an
/// optional trailing subtitle, then the station's own content — all in the
/// app's standard card style and trailing-aligned for RTL.
struct StationCard<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.md) {
            HStack {
                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .textCase(.uppercase)
                Spacer()
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .cardStyle()
    }
}

/// Muted single-line fallback used by every station's empty branch.
struct StationEmptyText: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - Shared rows & bars

/// Coloured-dot + label on the leading side, amount on the trailing side —
/// the row shape shared with the dashboard summary cards.
struct AnalyticsAmountRow: View {
    let title: LocalizedStringKey
    let amount: Decimal
    let code: String
    let dotColor: Color

    var body: some View {
        HStack {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Text(amount.formattedCurrency(code))
                .font(Theme.Typography.amount)
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
        }
    }
}

/// "נטו" row whose amount is signed and tinted by sign — the bottom line of
/// a period.
struct NetRow: View {
    let net: Decimal
    let code: String

    var body: some View {
        HStack {
            Text("נטו")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(net.formattedSignedCurrency(code))
                .font(Theme.Typography.amount)
                .foregroundStyle(net >= 0 ? Theme.Colors.income : Theme.Colors.expense)
                .monospacedDigit()
        }
    }
}

/// One category line: icon + name, amount + share, and a coloured bar that
/// grows in as the station reveals.
struct CategoryRow: View {
    let slice: CategorySlice
    let code: String

    private var color: Color { Color(hex: slice.colorHex) }

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: slice.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 22)
                Text(slice.name)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(slice.amount.formattedCurrency(code))
                    .font(Theme.Typography.amount)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            HStack(spacing: Theme.Spacing.sm) {
                AnalyticsBar(fraction: slice.fraction, color: color)
                Text(slice.fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .monospacedDigit()
                    .frame(width: 38, alignment: .leading)
            }
        }
    }
}

/// A row in the asset-allocation list: type label, amount, share, and bar.
struct AllocationRow: View {
    let slice: AssetSlice
    let code: String

    private var color: Color { Self.tint(for: slice.id) }

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: slice.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 22)
                Text(slice.typeLabel)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(slice.amount.formattedCurrency(code))
                    .font(Theme.Typography.amount)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            AnalyticsBar(fraction: slice.fraction, color: color)
        }
    }

    /// Map each account type onto a distinct palette colour so the bars
    /// read as different buckets at a glance.
    private static func tint(for typeRaw: String) -> Color {
        switch typeRaw {
        case AccountType.current.rawValue:    return Theme.Colors.accent
        case AccountType.savings.rawValue:    return Theme.Colors.income
        case AccountType.investment.rawValue: return Theme.Colors.wants
        default:                              return Theme.Colors.graphite
        }
    }
}

/// One personal-record line — a tinted trophy-ish icon, the record title +
/// detail, and an optional figure.
struct RecordRow: View {
    let record: FinancialRecord
    let code: String

    private var tint: Color {
        switch record.tint {
        case .income:  return Theme.Colors.income
        case .expense: return Theme.Colors.expense
        case .gold:    return Theme.Colors.wants
        case .neutral: return Theme.Colors.accent
        }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: record.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(tint.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(record.detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Spacing.sm)

            if let amount = record.amount {
                Text(amount.formattedCurrency(code))
                    .font(Theme.Typography.amount)
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .lineLimit(1)
                    // Reserve the amount's full width first so it's never
                    // truncated; the title (lower priority) takes the rest and
                    // wraps onto a second line instead.
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
        }
    }
}

/// One trend line for the comparison station: a coloured chevron + percent,
/// green when the change is the "good" direction (less spending, more
/// income), expense-red otherwise.
struct TrendRow: View {
    let label: LocalizedStringKey
    let fraction: Double?
    /// True for metrics where going *down* is the win (expenses).
    let improvesWhenLower: Bool

    private var isImprovement: Bool {
        guard let fraction else { return false }
        return improvesWhenLower ? fraction < 0 : fraction > 0
    }

    private var color: Color {
        guard let fraction, abs(fraction) > 0.001 else { return Theme.Colors.textSecondary }
        return isImprovement ? Theme.Colors.income : Theme.Colors.expense
    }

    private var symbol: String {
        guard let fraction, abs(fraction) > 0.001 else { return "equal" }
        return fraction > 0 ? "arrow.up.right" : "arrow.down.right"
    }

    private var percentText: String {
        guard let fraction else { return "—" }
        return abs(fraction).formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                Text(percentText)
                    .font(Theme.Typography.amount)
                    .monospacedDigit()
            }
            .foregroundStyle(color)
            // Keep the chevron on the visual left of the percent even in RTL.
            .environment(\.layoutDirection, .leftToRight)
        }
    }
}

/// A proportional multi-segment bar (income/expense, needs/wants, …). Each
/// segment's width animates in once the station is revealed.
struct SplitBar: View {
    struct Segment {
        let value: Decimal
        let color: Color
    }

    let segments: [Segment]
    var height: CGFloat = 8

    @Environment(\.stationRevealed) private var revealed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var total: Decimal { segments.reduce(0) { $0 + $1.value } }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: width(for: segment, in: geo.size.width))
                }
            }
            .clipShape(.capsule)
            .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.85), value: revealed)
        }
        .frame(height: height)
    }

    private func width(for segment: Segment, in fullWidth: CGFloat) -> CGFloat {
        guard total > 0, revealed || reduceMotion else { return 0 }
        let share = (segment.value / total) as NSDecimalNumber
        return fullWidth * CGFloat(truncating: share)
    }
}

/// A single-value progress bar that fills from the leading (RTL: right)
/// edge to `fraction`, growing in when the station reveals.
struct AnalyticsBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 10

    @Environment(\.stationRevealed) private var revealed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: CGFloat { CGFloat(min(max(fraction, 0), 1)) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * (revealed || reduceMotion ? clamped : 0))
            }
            .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.85), value: revealed)
        }
        .frame(height: height)
    }
}
