import SwiftUI

/// "Budget vs. actual" — the merged dashboard card that replaces the old
/// separate *planned budget* and *this month* cards.
///
/// For the current month it lays the plan and reality side by side, one row
/// per bucket (income / needs / wants): the actual amount, the planned amount
/// it's measured against, and a progress bar that fills toward the plan and
/// turns red on an overrun. A banner at the top calls out any budget breach;
/// `HomeView` additionally raises a one-per-session alert (see there).
///
/// All the arithmetic lives in the pure `BudgetVsActual` value type — this
/// view only lays it out — so the same numbers can later feed an Analytics
/// station with no duplication.
struct BudgetVsActualCard: View {
    let report: BudgetVsActual
    /// Tapped via the header pencil. Parent owns the budget-editor sheet.
    let onEdit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Flipped true on appear so the progress bars grow in from empty.
    @State private var revealed = false

    private var code: String { report.currencyCode }

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.md) {
            header

            if report.hasAnyBudget {
                comparison
            } else if report.hasAnyActivity {
                // Activity but nothing to compare against — show the actuals
                // and nudge the user toward setting a budget.
                actualsOnly
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .cardStyle()
        .onAppear { revealed = true }
    }

    // MARK: - Header

    /// Title + month label, with a pencil affordance opposite the label
    /// (always available, even in the empty state, so the user can add lines).
    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("התקציב מול הביצוע")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .textCase(.uppercase)
            Text(Self.currentMonthLabel)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(Theme.Spacing.xs)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("עריכת התקציב"))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - States

    private var emptyState: some View {
        Text("עדיין לא הוגדר תקציב.")
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Full plan-vs-reality layout.
    private var comparison: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.md) {
            if let summary = report.overrunSummary {
                OverrunBanner(summary: summary, code: code)
            }

            BudgetProgressRow(line: report.income, baseColor: Theme.Colors.income,
                              code: code, revealed: revealed, reduceMotion: reduceMotion)

            Divider().overlay(Theme.Colors.separator)

            BudgetProgressRow(line: report.needs, baseColor: Theme.Colors.expense,
                              code: code, revealed: revealed, reduceMotion: reduceMotion)
            BudgetProgressRow(line: report.wants, baseColor: Theme.Colors.wants,
                              code: code, revealed: revealed, reduceMotion: reduceMotion)

            Divider().overlay(Theme.Colors.separator)

            netRow

            scheduledExtrasNote
                .frame(maxWidth: .infinity, alignment: .leading)
            fxFootnote
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Fallback when there's spending but no budget: just the actual totals.
    private var actualsOnly: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.sm) {
            amountRow(title: "הכנסות", amount: report.income.actual, color: Theme.Colors.income)
            amountRow(title: "הוצאות", amount: report.totalActualExpense, color: Theme.Colors.expense)
            netRow

            Label("הגדירו תקציב כדי לראות השוואה לתכנון", systemImage: "slider.horizontal.3")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            fxFootnote
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Rows

    private func amountRow(title: LocalizedStringKey, amount: Decimal, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
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

    /// Actual net is the bottom line; the planned net rides underneath as a
    /// quiet reference so the user sees how the month tracked against plan.
    private var netRow: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
            HStack {
                Text("נטו בפועל")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text(report.actualNet.formattedSignedCurrency(code))
                    .font(Theme.Typography.amount)
                    .foregroundStyle(report.actualNet >= 0 ? Theme.Colors.income : Theme.Colors.expense)
                    .monospacedDigit()
            }
            if report.hasAnyBudget {
                HStack {
                    Text("מתוכנן")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Text(report.plannedNet.formattedSignedCurrency(code))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Footnotes

    @ViewBuilder
    private var scheduledExtrasNote: some View {
        if report.hasScheduledExtras {
            Label("כולל הוצאות מתוכננות לחודש זה", systemImage: "calendar.badge.clock")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    @ViewBuilder
    private var fxFootnote: some View {
        if report.hasCrossCurrency, report.fxUnavailable {
            Text("שערי חליפין לא זמינים — מוצגים רק פריטים ב-\(code).")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private static var currentMonthLabel: String {
        Date.now.formatted(.dateTime.locale(Locale(identifier: "he_IL")).month(.wide))
    }
}

// MARK: - Progress row

/// One bucket's plan-vs-reality line: a coloured dot + label, the actual
/// amount measured against the planned one, and a progress bar that fills
/// toward the plan (and goes red on an overrun or un-budgeted spend).
private struct BudgetProgressRow: View {
    let line: BudgetLine
    /// The bucket's identity colour when on budget; an overrun overrides it.
    let baseColor: Color
    let code: String
    let revealed: Bool
    let reduceMotion: Bool

    /// Overruns (and spending with no budget) read red, consistent with the
    /// banner — a single, unambiguous "over" signal across the card.
    private var barColor: Color {
        (line.isOverBudget || line.isUnbudgetedSpend) ? Theme.Colors.expense : baseColor
    }

    private var amountColor: Color {
        (line.isOverBudget || line.isUnbudgetedSpend) ? Theme.Colors.expense : Theme.Colors.textPrimary
    }

    /// Bar fill, clamped to the track: full when over (it can't show >100%),
    /// and full for un-budgeted spend so the red bar reads as "off-plan".
    private var fillFraction: Double {
        if let progress = line.progress { return min(max(progress, 0), 1) }
        return line.actual > 0 ? 1 : 0
    }

    private var percentText: String? {
        guard let progress = line.progress else { return nil }
        return progress.formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
            HStack {
                Circle().fill(baseColor).frame(width: 8, height: 8)
                Text(LocalizedStringKey(line.bucket.hebrewLabel))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer(minLength: Theme.Spacing.sm)
                amounts
            }

            HStack(spacing: Theme.Spacing.sm) {
                BudgetProgressBar(fillFraction: fillFraction, color: barColor,
                                  revealed: revealed, reduceMotion: reduceMotion)
                if let percentText {
                    Text(percentText)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(line.isOverBudget ? Theme.Colors.expense : Theme.Colors.textSecondary)
                        .monospacedDigit()
                        .frame(width: 44, alignment: .leading)
                }
            }

            if line.isOverBudget {
                Text("חריגה של \(line.overAmount.formattedCurrency(code))")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.expense)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    /// Actual amount, then the planned figure it's measured against — or a
    /// "not budgeted" note when there was no plan for this bucket.
    @ViewBuilder
    private var amounts: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(line.actual.formattedCurrency(code))
                .font(Theme.Typography.amount)
                .foregroundStyle(amountColor)
                .monospacedDigit()
            if line.planned > 0 {
                Text("מתוך \(line.planned.formattedCurrency(code))")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .monospacedDigit()
            } else if line.isUnbudgetedSpend {
                Text("לא תוקצב")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.expense)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var accessibilityLabel: String {
        let label = line.bucket.hebrewLabel
        let actual = line.actual.formattedCurrency(code)
        if line.planned > 0 {
            let planned = line.planned.formattedCurrency(code)
            let base = "\(label): בפועל \(actual), מתוך \(planned) מתוכננים"
            return line.isOverBudget ? "\(base), חריגה של \(line.overAmount.formattedCurrency(code))" : base
        }
        if line.isUnbudgetedSpend {
            return "\(label): בפועל \(actual), ללא תקציב"
        }
        return "\(label): \(actual)"
    }
}

/// A single-value progress bar that fills from the leading (RTL: right) edge
/// to `fillFraction`, growing in once the card appears (unless Reduce Motion
/// is on, where it's drawn at its final width immediately).
private struct BudgetProgressBar: View {
    let fillFraction: Double
    let color: Color
    let revealed: Bool
    let reduceMotion: Bool
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(revealed || reduceMotion ? fillFraction : 0))
            }
            .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.85), value: revealed)
        }
        .frame(height: height)
    }
}

// MARK: - Overrun banner

/// The persistent in-card warning shown whenever the month is over budget.
/// Honest about *what* is over: the total expense plan, or a specific
/// category when the total still has room.
private struct OverrunBanner: View {
    let summary: OverrunSummary
    let code: String

    private var message: String {
        if summary.isTotalOver {
            return "חריגה מהתקציב החודשי — \(summary.totalOverAmount.formattedCurrency(code))"
        }
        // No total breach, so name the category/categories that are over.
        let names = summary.lines.map(\.bucket.hebrewLabel).joined(separator: " ו")
        return "חריגה ב\(names)"
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .font(Theme.Typography.body)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.Colors.expense)
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(Theme.Colors.expense.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("On budget") {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        BudgetVsActualCard(
            report: BudgetVsActual(
                currencyCode: "ILS",
                income: BudgetLine(bucket: .income, planned: 9000, actual: 8200),
                needs: BudgetLine(bucket: .needs, planned: 4000, actual: 3100),
                wants: BudgetLine(bucket: .wants, planned: 2000, actual: 1100),
                hasAnyBudget: true,
                hasAnyActivity: true,
                fxUnavailable: false,
                hasCrossCurrency: false,
                hasScheduledExtras: false
            ),
            onEdit: {}
        )
        .padding(Theme.Spacing.lg)
    }
}

#Preview("Over budget") {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        BudgetVsActualCard(
            report: BudgetVsActual(
                currencyCode: "ILS",
                income: BudgetLine(bucket: .income, planned: 9000, actual: 9300),
                needs: BudgetLine(bucket: .needs, planned: 4000, actual: 4300),
                wants: BudgetLine(bucket: .wants, planned: 2000, actual: 1100),
                hasAnyBudget: true,
                hasAnyActivity: true,
                fxUnavailable: false,
                hasCrossCurrency: false,
                hasScheduledExtras: true
            ),
            onEdit: {}
        )
        .padding(Theme.Spacing.lg)
    }
}
