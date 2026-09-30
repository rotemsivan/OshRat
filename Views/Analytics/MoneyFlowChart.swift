import SwiftUI
import Charts

/// The bars behind "לאורך זמן": for each month (or year) an income bar beside
/// a spending bar, the spending stacked as needs under wants.
///
/// Scrolls sideways through the history, opening on `focusDate`'s period
/// (the one picked at the top of the screen), and reports the date under a
/// tap or drag through `selectedDate`, which the station turns into that
/// period's figures. `highlightedStart` is the period whose figures are
/// showing, marked behind its bars. Time runs left to right, as on
/// any chart — the axis is pinned `.leftToRight` so the RTL layout doesn't
/// turn the timeline around.
struct MoneyFlowChart: View {
    let series: MoneyFlowSeries
    /// For VoiceOver's reading of each bar.
    let currencyCode: String
    /// A date in the period to open on.
    let focusDate: Date
    /// The start of the period whose figures the station is showing.
    let highlightedStart: Date?
    @Binding var selectedDate: Date?

    @Environment(\.stationRevealed) private var revealed

    private var unit: Calendar.Component {
        series.granularity == .month ? .month : .year
    }

    /// How many periods fit on screen before the chart scrolls.
    private var visibleCount: Int {
        series.granularity == .month ? 6 : 5
    }

    /// The visible window, in seconds (the unit a date axis scrolls in).
    private var visibleLength: TimeInterval {
        let days: Double = series.granularity == .month ? 30.5 : 365.25
        return Double(visibleCount) * days * 24 * 60 * 60
    }

    /// Open with the focused period at the right-hand end of the window (as
    /// the latest data would be), or as near it as the history allows.
    private var initialScrollDate: Date {
        let points = series.points
        guard !points.isEmpty else { return focusDate }
        let focusIndex = points.firstIndex { $0.start == series.summary(for: focusDate)?.start }
            ?? (focusDate < points[0].start ? 0 : points.count - 1)
        let lastStart = max(0, points.count - visibleCount)
        let firstVisible = min(max(0, focusIndex - (visibleCount - 1)), lastStart)
        return points[firstVisible].start
    }

    /// Charts plots `Double`s; money stays `Decimal` until this point.
    private static func double(_ amount: Decimal) -> Double {
        (amount as NSDecimalNumber).doubleValue
    }

    var body: some View {
        Chart(series.points) { point in
            if point.start == highlightedStart {
                // A band as wide as the period itself, so it frames the pair
                // of bars at any granularity (a fixed-width rule was narrower
                // than a year's bars).
                RectangleMark(x: .value("תקופה", point.start, unit: unit))
                    .foregroundStyle(Theme.Colors.accent.opacity(0.12))
            }

            BarMark(
                x: .value("תקופה", point.start, unit: unit),
                y: .value("סכום", revealed ? Self.double(point.income) : 0)
            )
            .foregroundStyle(Theme.Colors.income)
            .position(by: .value("צד", "income"))
            .accessibilityLabel(Text("הכנסות"))
            .accessibilityValue(Text(point.income.formattedCurrency(currencyCode, whole: true)))

            BarMark(
                x: .value("תקופה", point.start, unit: unit),
                y: .value("סכום", revealed ? Self.double(point.needs) : 0)
            )
            .foregroundStyle(Theme.Colors.expense)
            .position(by: .value("צד", "expense"))
            .accessibilityLabel(Text("צרכים"))
            .accessibilityValue(Text(point.needs.formattedCurrency(currencyCode, whole: true)))

            BarMark(
                x: .value("תקופה", point.start, unit: unit),
                y: .value("סכום", revealed ? Self.double(point.wants) : 0)
            )
            .foregroundStyle(Theme.Colors.wants)
            .position(by: .value("צד", "expense"))
            .accessibilityLabel(Text("מותרות"))
            .accessibilityValue(Text(point.wants.formattedCurrency(currencyCode, whole: true)))
        }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: unit)) {
                AxisValueLabel(format: series.granularity == .month
                    ? .dateTime.month(.abbreviated)
                    : .dateTime.year())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount, format: .number.notation(.compactName))
                    }
                }
            }
        }
        .chartScrollableAxes(series.points.count > visibleCount ? .horizontal : [])
        .chartXVisibleDomain(length: visibleLength)
        .chartScrollPosition(initialX: initialScrollDate)
        .chartXSelection(value: $selectedDate)
        .animation(.easeOut(duration: 0.6), value: revealed)
        .frame(height: 200)
        .environment(\.layoutDirection, .leftToRight)
        .environment(\.locale, Locale(identifier: "he_IL"))
        .environment(\.calendar, MoneyFlowSeries.calendar)
    }
}
