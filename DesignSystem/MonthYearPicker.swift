import SwiftUI

/// Two side-by-side wheels — month and year — for jumping a month-grid
/// calendar straight to any date instead of paging one month at a time.
/// Shared by the budget calendar and the transactions date-range filter,
/// which both reveal it when the user taps the month/year header.
///
/// It reads and writes a single `Date` pinned to the first of the chosen
/// month, so the host calendar can keep driving everything off its existing
/// `visibleMonth` state.
struct MonthYearPicker: View {
    @Binding var month: Date

    /// Inclusive span of years offered in the wheel. Defaults to a wide
    /// window around now so both old ledgers and forward planning are
    /// reachable.
    private let yearRange: ClosedRange<Int>

    /// Gregorian + Hebrew locale so the month names read in Hebrew and the
    /// arithmetic matches the rest of the app's calendars.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "he_IL")
        return calendar
    }()

    init(month: Binding<Date>, yearRange: ClosedRange<Int>? = nil) {
        _month = month
        let currentYear = Calendar.current.component(.year, from: .now)
        self.yearRange = yearRange ?? (currentYear - 20)...(currentYear + 20)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Month on the leading edge (the visual right under RTL), year
            // trailing — the natural Hebrew "חודש שנה" reading order.
            Picker("חודש", selection: monthSelection) {
                ForEach(1...12, id: \.self) { monthIndex in
                    Text(monthName(monthIndex)).tag(monthIndex)
                }
            }
            .pickerStyle(.wheel)

            Picker("שנה", selection: yearSelection) {
                ForEach(Array(yearRange), id: \.self) { year in
                    Text(verbatim: String(year)).tag(year)
                }
            }
            .pickerStyle(.wheel)
        }
        .labelsHidden()
        .frame(height: 150)
    }

    // MARK: - Component bindings

    /// Spinning either wheel rebuilds `month` from the (month, year) pair,
    /// so the host's `visibleMonth` follows the selection live.
    private var monthSelection: Binding<Int> {
        Binding(
            get: { calendar.component(.month, from: month) },
            set: { set(month: $0, year: calendar.component(.year, from: month)) }
        )
    }

    private var yearSelection: Binding<Int> {
        Binding(
            get: { calendar.component(.year, from: month) },
            set: { set(month: calendar.component(.month, from: month), year: $0) }
        )
    }

    private func set(month newMonth: Int, year newYear: Int) {
        if let date = calendar.date(from: DateComponents(year: newYear, month: newMonth, day: 1)) {
            month = date
        }
    }

    private func monthName(_ index: Int) -> String {
        calendar.monthSymbols[index - 1]
    }
}

#Preview {
    @Previewable @State var month = Date.now
    return MonthYearPicker(month: $month)
}
