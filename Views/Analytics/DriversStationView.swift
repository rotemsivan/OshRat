import SwiftUI

// MARK: - Station · What's behind the change

/// The station right after "מול החודש הקודם", explaining its numbers with as
/// few words as possible: the bottom-line change for expenses and income, the
/// categories that moved most, how the count and the average purchase moved,
/// and any one-off purchase big enough to matter. Everything comes from
/// `PeriodDrivers`, over the same like-for-like windows as the comparison.
struct DriversStationView: View {
    let report: AnalyticsReport

    /// Movers shown — enough to account for most months, few enough to scan.
    private static let moverCount = 4

    private var drivers: PeriodDrivers { report.drivers }
    private var code: String { drivers.currencyCode }

    var body: some View {
        StationCard(title: "מה עומד מאחורי השינוי", subtitle: report.comparisonSubtitle) {
            if !drivers.hasBaseline {
                StationEmptyText(report.scope == .month ? "אין חודש קודם להשוואה." : "אין שנה קודמת להשוואה.")
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    HStack(spacing: Theme.Spacing.sm) {
                        BottomLineTile(title: "הוצאות", delta: drivers.expense.delta,
                                       improvesWhenLower: true, code: code)
                        BottomLineTile(title: "הכנסות", delta: drivers.income.delta,
                                       improvesWhenLower: false, code: code)
                    }

                    let movers = Array(drivers.expense.categories.prefix(Self.moverCount))
                    if !movers.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            SectionLabel(title: "מה הזיז את ההוצאות")
                            ForEach(movers) { entry in
                                MoverRow(entry: entry, code: code)
                            }
                        }
                    }

                    if drivers.expense.currentCount > 0, drivers.expense.previousCount > 0 {
                        HabitsRow(side: drivers.expense, code: code)
                    }

                    if !drivers.notableExpenses.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            SectionLabel(title: "רכישות חריגות")
                            ForEach(drivers.notableExpenses.prefix(2)) { expense in
                                AmountRow(symbolName: expense.symbolName, colorHex: expense.colorHex,
                                          name: expense.title,
                                          amount: expense.amount.formattedCurrency(code, whole: true),
                                          tint: Theme.Colors.textPrimary)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Bottom line

/// The change in one direction of money, as one big signed figure. Green when
/// it moved the good way (less spent, more earned), red otherwise.
private struct BottomLineTile: View {
    let title: LocalizedStringKey
    let delta: Decimal
    let improvesWhenLower: Bool
    let code: String

    private var tint: Color {
        if delta == 0 { return Theme.Colors.textPrimary }
        return (delta < 0) == improvesWhenLower ? Theme.Colors.income : Theme.Colors.expense
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(delta.formattedSignedCurrency(code, whole: true))
                .font(Theme.Typography.amount)
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.button).fill(tint.opacity(0.08)))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Movers

/// One category's change: glyph, name, signed amount. An increase in spending
/// is red, a decrease green — the sign and colour say it, no bar needed.
private struct MoverRow: View {
    let entry: CategoryDelta
    let code: String

    var body: some View {
        AmountRow(
            symbolName: entry.symbolName,
            colorHex: entry.colorHex,
            name: entry.name,
            amount: entry.delta.formattedSignedCurrency(code, whole: true),
            tint: entry.delta > 0 ? Theme.Colors.expense : Theme.Colors.income
        )
    }
}

// MARK: - Habits

/// How the spending changed rather than where: the number of expenses and the
/// average one, each with its change beside it.
private struct HabitsRow: View {
    let side: PeriodDrivers.Side
    let code: String

    var body: some View {
        let countDelta = side.currentCount - side.previousCount
        let averageDelta = (side.currentAverage ?? 0) - (side.previousAverage ?? 0)
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            HabitStat(
                title: "מספר הוצאות",
                value: side.currentCount.formatted(),
                // Sign isolated and logically last, so RTL puts it on the
                // left as `formattedSignedCurrency` does.
                change: countDelta == 0 ? nil : "\(abs(countDelta))\u{2066}\(countDelta > 0 ? "+" : "-")\u{2069}",
                isUp: countDelta > 0
            )
            HabitStat(
                title: "הוצאה ממוצעת",
                value: (side.currentAverage ?? 0).formattedCurrency(code, whole: true),
                change: averageDelta == 0 ? nil : averageDelta.formattedSignedCurrency(code, whole: true),
                isUp: averageDelta > 0
            )
        }
    }
}

private struct HabitStat: View {
    let title: LocalizedStringKey
    let value: String
    let change: String?
    let isUp: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text(value)
                    .font(Theme.Typography.amount)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let change {
                    Text(change)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(isUp ? Theme.Colors.expense : Theme.Colors.income)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Shared bits

/// A quiet heading inside a station.
struct SectionLabel: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Glyph, name, and a figure on the far side — the one row shape both
/// deep-dive stations use.
struct AmountRow: View {
    let symbolName: String
    let colorHex: String
    let name: String
    let amount: String
    let tint: Color

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            CategoryGlyph(symbolName: symbolName, colorHex: colorHex)
            Text(name)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.sm)
            Text(amount)
                .font(Theme.Typography.amount)
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

/// A category's symbol in its own colour, at a fixed column width so names
/// line up down a list.
struct CategoryGlyph: View {
    let symbolName: String
    let colorHex: String

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(hex: colorHex))
            .frame(width: 22)
            .accessibilityHidden(true)
    }
}
