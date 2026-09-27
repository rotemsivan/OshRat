import SwiftUI

// MARK: - Station · Against the budget

/// The period's plan against reality, category by category. Leads with the
/// bottom line — what's left, or how far over — then one compact row per
/// budgeted category (overruns first), with unbudgeted spending and income
/// as a row each.
///
/// While the period is running the total bar carries a pace mark at the share
/// of the period gone by — a mark, not a projection, which a rent-on-the-1st
/// category would get wrong.
struct BudgetStationView: View {
    let report: AnalyticsReport

    /// Rows shown before "הצג הכל". Overruns sort first, so they're always in.
    private static let collapsedRows = 4

    @State private var showsAllRows = false

    private var budget: CategoryBudgetBreakdown { report.budget }
    private var code: String { budget.currencyCode }

    var body: some View {
        StationCard(title: "מול התקציב", subtitle: report.periodLabel) {
            if !budget.hasAnyBudget {
                StationEmptyText("עדיין לא הוגדר תקציב.")
            } else if !budget.hasPlanInPeriod && budget.unbudgeted.isEmpty {
                StationEmptyText("אין תקציב לתקופה זו.")
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if budget.plannedExpense > 0 {
                        BudgetBottomLine(budget: budget, isMonth: report.scope == .month)
                    }

                    if !budget.rows.isEmpty {
                        let visible = showsAllRows ? budget.rows : Array(budget.rows.prefix(Self.collapsedRows))
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            HStack {
                                SectionLabel(title: "לפי קטגוריה")
                                if !budget.overruns.isEmpty {
                                    OverrunChip(count: budget.overruns.count)
                                }
                            }
                            ForEach(visible) { row in
                                BudgetRow(
                                    symbolName: row.symbolName, colorHex: row.colorHex, name: row.name,
                                    fraction: row.fraction, color: Self.color(for: row), isOver: row.isOver
                                )
                            }
                            if budget.rows.count > Self.collapsedRows {
                                Button(showsAllRows ? "הצג פחות" : "הצג הכל (\(budget.rows.count))", action: toggleRows)
                                    .font(Theme.Typography.bodySmall)
                                    .foregroundStyle(Theme.Colors.accent)
                                    .frame(minHeight: 44)
                            }
                        }
                    }

                    if !budget.unbudgeted.isEmpty || budget.plannedIncome > 0 {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            if !budget.unbudgeted.isEmpty {
                                AmountRow(symbolName: "questionmark.circle", colorHex: "#9E9E9E",
                                          name: "ללא תקציב",
                                          amount: budget.unbudgetedTotal.formattedCurrency(code, whole: true),
                                          tint: Theme.Colors.textPrimary)
                            }
                            if budget.plannedIncome > 0 {
                                BudgetRow(
                                    symbolName: "arrow.down.left", colorHex: "#2FA36B", name: "הכנסות",
                                    fraction: NSDecimalNumber(decimal: budget.actualIncome / budget.plannedIncome).doubleValue,
                                    color: Theme.Colors.income, isOver: false
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func toggleRows() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showsAllRows.toggle()
        }
    }

    /// Accent with room, orange from 90%, red once over — the transaction
    /// card's budget-bar colours.
    private static func color(for row: CategoryBudgetRow) -> Color {
        if row.isOver { return Theme.Colors.expense }
        return row.fraction >= 0.9 ? Theme.Colors.wants : Theme.Colors.accent
    }
}

// MARK: - Bottom line

/// The one figure that matters — what's left of the plan, or how far past it
/// — with the total bar under it and "spent of planned" as its caption.
private struct BudgetBottomLine: View {
    let budget: CategoryBudgetBreakdown
    let isMonth: Bool

    private var code: String { budget.currencyCode }
    private var isOver: Bool { budget.isTotalOver }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(isOver ? "חריגה" : "נותרו")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(abs(budget.plannedExpense - budget.actualExpense).formattedCurrency(code, whole: true))
                        .font(Theme.Typography.screenTitle)
                        .foregroundStyle(isOver ? Theme.Colors.expense : Theme.Colors.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer()
                Text(budget.expenseFraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(Theme.Typography.amount)
                    .foregroundStyle(isOver ? Theme.Colors.expense : Theme.Colors.textSecondary)
                    .monospacedDigit()
            }
            PacedBudgetBar(
                fraction: budget.expenseFraction,
                color: barColor,
                elapsed: budget.elapsedFraction
            )
            Text(caption)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private var barColor: Color {
        if isOver { return Theme.Colors.expense }
        return budget.expenseFraction >= 0.9 ? Theme.Colors.wants : Theme.Colors.accent
    }

    /// "₪25,059 מתוך ₪22,020", plus how far into the period we are while it
    /// runs — the one word of explanation the pace mark on the bar needs.
    private var caption: String {
        let spent = "\(budget.actualExpense.formattedCurrency(code, whole: true)) מתוך \(budget.plannedExpense.formattedCurrency(code, whole: true))"
        guard let elapsed = budget.elapsedFraction else { return spent }
        let percent = elapsed.formatted(.percent.precision(.fractionLength(0)))
        return isMonth ? "\(spent) · עבר \(percent) מהחודש" : "\(spent) · עברה \(percent) מהשנה"
    }
}

/// "3 בחריגה" in red, beside the category heading.
private struct OverrunChip: View {
    let count: Int

    var body: some View {
        Label("\(count) בחריגה", systemImage: "exclamationmark.triangle.fill")
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.expense)
            .fixedSize()
    }
}

// MARK: - Rows

/// Glyph, name, share of plan, and a thin bar. The percentage turns red past
/// 100%, so the state reads without the colour of the bar.
private struct BudgetRow: View {
    let symbolName: String
    let colorHex: String
    let name: String
    let fraction: Double
    let color: Color
    let isOver: Bool

    @Environment(\.stationRevealed) private var revealed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            AmountRow(
                symbolName: symbolName, colorHex: colorHex, name: name,
                amount: fraction.formatted(.percent.precision(.fractionLength(0))),
                tint: isOver ? Theme.Colors.expense : Theme.Colors.textPrimary
            )
            BudgetProgressBar(
                fillFraction: min(max(fraction, 0), 1),
                color: color,
                revealed: revealed,
                reduceMotion: reduceMotion,
                height: 6
            )
        }
        .accessibilityElement(children: .combine)
    }
}

/// The dashboard's `BudgetProgressBar`, plus a thin mark at how much of the
/// period has gone by. The mark is placed with `visualEffect` (it reads the
/// bar's own width at draw time) rather than a `GeometryReader`; its offset
/// runs from the leading edge, which is the fill's edge in RTL too.
private struct PacedBudgetBar: View {
    let fraction: Double
    let color: Color
    let elapsed: Double?
    private let height: CGFloat = 12

    @Environment(\.stationRevealed) private var revealed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BudgetProgressBar(
            fillFraction: min(max(fraction, 0), 1),
            color: color,
            revealed: revealed,
            reduceMotion: reduceMotion,
            height: height
        )
        .overlay(alignment: .leading) {
            if let elapsed {
                Capsule()
                    .fill(Theme.Colors.textPrimary.opacity(0.55))
                    .frame(width: 2, height: height + 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .visualEffect { content, proxy in
                        content.offset(x: proxy.size.width * min(max(elapsed, 0), 1) - 1)
                    }
            }
        }
    }
}
