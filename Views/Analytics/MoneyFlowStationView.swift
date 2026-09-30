import SwiftUI

/// "לאורך זמן" — income against spending (needs and wants stacked) for every
/// month or every year, as an interactive bar chart.
///
/// Follows the period picked at the top of the screen: its scope sets the
/// granularity, and its month (or year) is the one whose figures show and
/// that the chart opens on. The station's own month/year switch looks at the
/// same date the other way, and tapping a bar shows that period instead —
/// until the period at the top changes, which resets both.
struct MoneyFlowStationView: View {
    let monthly: MoneyFlowSeries
    let yearly: MoneyFlowSeries
    let period: AnalyticsPeriod
    let currencyCode: String

    @State private var granularity: MoneyFlowSeries.Granularity
    /// The raw date under the finger, from the chart's selection.
    @State private var selectedDate: Date?

    init(monthly: MoneyFlowSeries, yearly: MoneyFlowSeries, period: AnalyticsPeriod, currencyCode: String) {
        self.monthly = monthly
        self.yearly = yearly
        self.period = period
        self.currencyCode = currencyCode
        self._granularity = State(initialValue: Self.granularity(for: period.scope))
    }

    private var series: MoneyFlowSeries {
        granularity == .month ? monthly : yearly
    }

    /// The selected bar's period, or else the one picked at the top.
    private var shownPoint: MoneyFlowSeries.Point? {
        series.summary(for: selectedDate ?? period.anchor)
    }

    var body: some View {
        StationCard(title: "לאורך זמן") {
            if !series.points.isEmpty, let shownPoint {
                Picker("תצוגה", selection: $granularity) {
                    Text("חודשים").tag(MoneyFlowSeries.Granularity.month)
                    Text("שנים").tag(MoneyFlowSeries.Granularity.year)
                }
                .pickerStyle(.segmented)

                MoneyFlowSummary(point: shownPoint, granularity: granularity, currencyCode: currencyCode)

                MoneyFlowChart(
                    series: series,
                    currencyCode: currencyCode,
                    focusDate: period.anchor,
                    highlightedStart: shownPoint.start,
                    selectedDate: $selectedDate
                )
                // A fresh chart whenever what it should open on changes, so
                // its scroll position jumps to the picked period rather than
                // staying where the last one left it. (Not on a tap: that
                // would yank the chart out from under the finger.)
                .id(ChartFocus(granularity: granularity, period: period))
            } else {
                StationEmptyText("עדיין אין תנועות להציג לאורך זמן.")
            }
        }
        .onChange(of: granularity, clearSelection)
        .onChange(of: period, followPeriod)
    }

    private func clearSelection() {
        selectedDate = nil
    }

    /// A new period at the top wins over a tapped bar and over the station's
    /// own switch.
    private func followPeriod() {
        selectedDate = nil
        granularity = Self.granularity(for: period.scope)
    }

    private static func granularity(for scope: AnalyticsPeriod.Scope) -> MoneyFlowSeries.Granularity {
        scope == .month ? .month : .year
    }
}

/// What the chart opens on — its identity, so a change re-creates it.
private struct ChartFocus: Hashable {
    let granularity: MoneyFlowSeries.Granularity
    let anchor: Date

    init(granularity: MoneyFlowSeries.Granularity, period: AnalyticsPeriod) {
        self.granularity = granularity
        self.anchor = period.anchor
    }
}
