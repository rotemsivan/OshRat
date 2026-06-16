import SwiftUI

/// Reusable `Form` section that captures *when* a budget line happens:
/// every month (optionally pinned to a day), every year (in a chosen
/// month), or once on a specific date. Shared by the income and expense
/// editors so scheduling looks and behaves identically wherever a budget
/// line is created.
///
/// `allowsWeeklyCadence` adds the legacy "every X weeks" option (expenses
/// only — e.g. a barber every 3 weeks). Income lines never use it, so they
/// pass `false` together with constant frequency bindings.
struct BudgetScheduleSection: View {
    @Binding var schedule: BudgetSchedule
    @Binding var frequencyKind: BudgetFrequencyKind
    @Binding var frequencyWeeks: Int
    let allowsWeeklyCadence: Bool
    let currencyCode: String
    let plannedAmount: Decimal

    var body: some View {
        Section {
            Picker("תזמון", selection: $schedule.kind) {
                ForEach(BudgetScheduleKind.allCases) { kind in
                    Label(kind.hebrewLabel, systemImage: kind.systemImage).tag(kind)
                }
            }

            cadenceRows

            // Recurring lines can be capped ("until January 2028"); a
            // one-off is already bounded to its single date.
            if schedule.kind != .oneTime {
                Toggle("תאריך סיום", isOn: $schedule.hasEndDate)
                if schedule.hasEndDate {
                    DatePicker("עד", selection: $schedule.endDate, displayedComponents: .date)
                }
            }
        } header: {
            Text("מתי")
        } footer: {
            Text(footerText)
        }
    }

    // MARK: - Cadence-specific rows

    @ViewBuilder
    private var cadenceRows: some View {
        switch schedule.kind {
        case .recurringMonthly:
            monthlyRows
        case .recurringYearly:
            yearlyRows
        case .oneTime:
            DatePicker(
                "תאריך",
                selection: $schedule.oneTimeDate,
                displayedComponents: .date
            )
        }
    }

    @ViewBuilder
    private var monthlyRows: some View {
        if allowsWeeklyCadence {
            Picker("תדירות", selection: $frequencyKind) {
                ForEach(BudgetFrequencyKind.allCases) { kind in
                    Text(kind.hebrewLabel).tag(kind)
                }
            }

            if frequencyKind == .everyXWeeks {
                Stepper(value: $frequencyWeeks, in: 1...52) {
                    HStack {
                        Text("כל")
                        Text("\(frequencyWeeks)")
                            .font(.body.monospacedDigit())
                        Text("שבועות")
                    }
                }
                .contentTransition(.numericText(value: Double(frequencyWeeks)))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: frequencyWeeks)

                LabeledContent("שווי חודשי משוער") {
                    Text(monthlyEquivalentPreview.formatted(.currency(code: currencyCode)))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                dayRows
            }
        } else {
            dayRows
        }
    }

    @ViewBuilder
    private var yearlyRows: some View {
        Picker("חודש", selection: $schedule.month) {
            ForEach(1...12, id: \.self) { month in
                Text(Self.hebrewMonthName(month)).tag(month)
            }
        }
        .pickerStyle(.menu)

        dayRows
    }

    /// Optional day-of-month picker, shared by the monthly and yearly
    /// cadences. Off by default — "every February" needs no day, "salary
    /// on the 10th" turns it on.
    @ViewBuilder
    private var dayRows: some View {
        Toggle("ביום מסוים בחודש", isOn: $schedule.usesSpecificDay)
        if schedule.usesSpecificDay {
            Picker("יום בחודש", selection: $schedule.dayOfMonth) {
                ForEach(1...31, id: \.self) { day in
                    Text("\(day)").tag(day)
                }
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: - Helpers

    private var footerText: String {
        switch schedule.kind {
        case .recurringMonthly:
            return "ייכנס לתקציב בכל חודש."
        case .recurringYearly:
            return "ייכנס לתקציב פעם בשנה, רק בחודש שנבחר."
        case .oneTime:
            return "ייכנס לתקציב רק בחודש של התאריך שנבחר."
        }
    }

    /// Mirrors `BudgetItem.monthlyEquivalent` so the editor preview never
    /// disagrees with the dashboard's roll-up.
    private var monthlyEquivalentPreview: Decimal {
        switch frequencyKind {
        case .monthly:
            return plannedAmount
        case .everyXWeeks:
            let weeks = max(frequencyWeeks, 1)
            return plannedAmount * (Decimal(30) / Decimal(weeks * 7))
        }
    }

    private static func hebrewMonthName(_ month: Int) -> String {
        var comps = DateComponents()
        comps.year = 2000
        comps.month = month
        comps.day = 1
        let date = Calendar.current.date(from: comps) ?? .now
        return date.formatted(.dateTime.locale(Locale(identifier: "he_IL")).month(.wide))
    }
}
