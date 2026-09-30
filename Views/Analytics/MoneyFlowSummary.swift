import SwiftUI

/// The figures for one period of the trend chart — the selected bar, or the
/// latest period. Its coloured dots double as the chart's legend.
struct MoneyFlowSummary: View {
    let point: MoneyFlowSeries.Point
    let granularity: MoneyFlowSeries.Granularity
    let currencyCode: String

    /// "מרץ 2026" / "2026", in the Gregorian calendar the series is cut in.
    private var periodLabel: String {
        var format: Date.FormatStyle = granularity == .month
            ? .dateTime.month(.wide).year()
            : .dateTime.year()
        format.locale = Locale(identifier: "he_IL")
        format.calendar = MoneyFlowSeries.calendar
        return point.start.formatted(format)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(periodLabel)
                .font(Theme.Typography.amount)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.numericText())

            AnalyticsAmountRow(title: "הכנסות", amount: point.income, code: currencyCode, dotColor: Theme.Colors.income)
            AnalyticsAmountRow(title: "צרכים", amount: point.needs, code: currencyCode, dotColor: Theme.Colors.expense)
            AnalyticsAmountRow(title: "מותרות", amount: point.wants, code: currencyCode, dotColor: Theme.Colors.wants)
            NetRow(net: point.net, code: currencyCode)
        }
        .accessibilityElement(children: .combine)
    }
}
