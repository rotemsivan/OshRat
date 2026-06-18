import SwiftUI

/// Reusable `Form` section that captures *when* a budget line happens.
///
/// The primary "תזמון" picker keeps the common cases one tap away — every
/// month, every year, or a one-off date — plus **התאמה אישית** (custom),
/// which reveals a frequency editor (a unit segment + a count stepper) so the
/// user can dial in any "every N days / weeks / months / years". Shared by
/// the income and expense editors so scheduling looks and behaves identically
/// wherever a budget line is created.
///
/// `allowsSubMonthlyCadence` decides whether the custom editor offers the
/// averaged day/week units (expenses only — a barber every 3 weeks, daily
/// coffee). Income hides them, since a salary doesn't arrive "every few days".
///
/// The picker drives the model's two cadence dimensions — `schedule.isOneTime`
/// and the `schedule.unit` + `count` recurrence. Sub-monthly units are
/// averaged into a monthly figure; month and year units land their full amount
/// on the months they occur.
struct BudgetScheduleSection: View {
    @Binding var schedule: BudgetSchedule
    let allowsSubMonthlyCadence: Bool
    let currencyCode: String
    let plannedAmount: Decimal

    /// The top-level selection. Kept as its own state (rather than derived on
    /// the fly) so that, while editing a custom cadence, dialling the count
    /// down to "every 1 month" doesn't snap the picker back to the preset and
    /// yank the custom controls out from under the user. Seeded from the
    /// schedule the editor opens with.
    @State private var mode: ScheduleMode

    init(
        schedule: Binding<BudgetSchedule>,
        allowsSubMonthlyCadence: Bool,
        currencyCode: String,
        plannedAmount: Decimal
    ) {
        self._schedule = schedule
        self.allowsSubMonthlyCadence = allowsSubMonthlyCadence
        self.currencyCode = currencyCode
        self.plannedAmount = plannedAmount
        self._mode = State(initialValue: ScheduleMode(for: schedule.wrappedValue))
    }

    var body: some View {
        Section {
            Picker("תזמון", selection: modeBinding) {
                ForEach(ScheduleMode.allCases) { mode in
                    Label(mode.hebrewLabel, systemImage: mode.systemImage).tag(mode)
                }
            }

            cadenceRows

            // Recurring lines can be capped ("until January 2028"); a
            // one-off is already bounded to its single date.
            if !schedule.isOneTime {
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

    // MARK: - Mode selection

    /// Writes a top-level choice onto both `mode` and the schedule. Switching
    /// into a preset pins the exact recurrence; switching into custom seeds a
    /// sensible starting interval (kept only when *entering* custom, so an
    /// existing custom line keeps its own values).
    private var modeBinding: Binding<ScheduleMode> {
        Binding {
            mode
        } set: { newMode in
            mode = newMode
            switch newMode {
            case .everyMonth:
                schedule.isOneTime = false
                schedule.unit = .month
                schedule.count = 1
            case .everyYear:
                schedule.isOneTime = false
                schedule.unit = .year
                schedule.count = 1
            case .oneTime:
                schedule.isOneTime = true
            case .custom:
                schedule.isOneTime = false
                schedule.unit = allowsSubMonthlyCadence ? .week : .month
                schedule.count = 2
            }
        }
    }

    // MARK: - Cadence-specific rows

    @ViewBuilder
    private var cadenceRows: some View {
        switch mode {
        case .everyMonth:
            dayRows
        case .everyYear:
            monthPicker(label: "בחודש")
            dayRows
        case .oneTime:
            DatePicker("תאריך", selection: $schedule.oneTimeDate, displayedComponents: .date)
        case .custom:
            customRows
        }
    }

    /// The custom frequency editor: pick a unit, then a count. Landing units
    /// (months/years) also get an anchor month + optional day; averaged units
    /// (days/weeks) get the monthly-equivalent preview instead.
    @ViewBuilder
    private var customRows: some View {
        Picker("יחידה", selection: customUnit) {
            ForEach(customUnits) { unit in
                Text(Self.unitPluralLabel(unit)).tag(unit)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        countStepper

        if schedule.unit.isAveraged {
            averagedPreview
        } else {
            // The anchor month only matters when the line lands on select
            // months (yearly, or every N>1 months); a plain monthly line skips it.
            if schedule.unit == .year || schedule.count > 1 {
                monthPicker(label: schedule.unit == .year ? "בחודש" : "מתחיל בחודש")
            }
            dayRows
        }
    }

    /// "כל [N] שבועות/חודשים/…" stepper, bound to the unit's sensible range.
    private var countStepper: some View {
        Stepper(value: $schedule.count, in: countRange(for: schedule.unit)) {
            Text(BudgetSchedule.everyPhrase(count: schedule.count, unit: schedule.unit))
                .contentTransition(.numericText(value: Double(schedule.count)))
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: schedule.count)
    }

    /// Averaged cadences (days/weeks) roll into a monthly figure, so show the
    /// user what that works out to.
    private var averagedPreview: some View {
        LabeledContent("שווי חודשי משוער") {
            Text(monthlyEquivalentPreview.formatted(.currency(code: currencyCode)))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    /// Month-of-year picker used to anchor the landing cadences (yearly, and
    /// every N months with N>1).
    private func monthPicker(label: LocalizedStringKey) -> some View {
        Picker(label, selection: $schedule.month) {
            ForEach(1...12, id: \.self) { month in
                Text(Self.hebrewMonthName(month)).tag(month)
            }
        }
        .pickerStyle(.menu)
    }

    /// Optional day-of-month picker for landing cadences. Off by default —
    /// "every February" needs no day, "salary on the 10th" turns it on.
    @ViewBuilder
    private var dayRows: some View {
        Toggle("ביום מסוים בחודש", isOn: $schedule.usesSpecificDay)
        if schedule.usesSpecificDay {
            Picker("יום בחודש", selection: $schedule.dayOfMonth) {
                ForEach(1...31, id: \.self) { day in
                    Text("\(day)").tag(day)
                }
            }
            .pickerStyle(.wheel)
            // A full-height wheel eats ~200pt of the form. Cap it to a few
            // visible rows and clip the spillover (same trick as the
            // currency wheel in `BigAmountField`) so it stays compact while
            // keeping the spinnable feel.
            .frame(height: 100)
            .clipped()
        }
    }

    // MARK: - Helpers

    /// Units offered in the custom editor. Income hides the averaged
    /// sub-monthly units, leaving only months and years.
    private var customUnits: [RecurrenceUnit] {
        allowsSubMonthlyCadence ? [.day, .week, .month, .year] : [.month, .year]
    }

    /// Bridges the unit segment onto `schedule.unit`, clamping the count into
    /// the new unit's range (so switching week→year can't leave count at 40).
    private var customUnit: Binding<RecurrenceUnit> {
        Binding {
            schedule.unit
        } set: { newUnit in
            schedule.unit = newUnit
            let range = countRange(for: newUnit)
            schedule.count = min(max(schedule.count, range.lowerBound), range.upperBound)
        }
    }

    private func countRange(for unit: RecurrenceUnit) -> ClosedRange<Int> {
        switch unit {
        case .day:   return 1...90
        case .week:  return 1...52
        case .month: return 1...24
        case .year:  return 1...10
        }
    }

    private var footerText: String {
        switch mode {
        case .everyMonth:
            return "ייכנס לתקציב בכל חודש."
        case .everyYear:
            return "הסכום המלא ייכנס פעם בשנה, רק בחודש שנבחר."
        case .oneTime:
            return "ייכנס לתקציב רק בחודש של התאריך שנבחר."
        case .custom:
            if schedule.unit.isAveraged {
                return "מתחלק לתקציב של כל חודש לפי השווי החודשי המשוער."
            }
            if schedule.unit == .month, schedule.count == 1 {
                return "ייכנס לתקציב בכל חודש."
            }
            return "הסכום המלא ייכנס רק בחודשים שבהם זה חוזר."
        }
    }

    /// Mirrors `BudgetItem.monthlyEquivalent` for averaged cadences so the
    /// editor preview never disagrees with the dashboard's roll-up.
    private var monthlyEquivalentPreview: Decimal {
        let n = Decimal(max(schedule.count, 1))
        switch schedule.unit {
        case .day:   return plannedAmount * (Decimal(30) / n)
        case .week:  return plannedAmount * (Decimal(30) / (n * 7))
        case .month, .year: return plannedAmount
        }
    }

    /// Count-independent unit label for the custom segment ("ימים", "שבועות"…).
    private static func unitPluralLabel(_ unit: RecurrenceUnit) -> String {
        switch unit {
        case .day:   return "ימים"
        case .week:  return "שבועות"
        case .month: return "חודשים"
        case .year:  return "שנים"
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

// MARK: - ScheduleMode

/// The top-level "תזמון" choice: the three common presets plus a catch-all
/// custom mode. Presets pin an exact recurrence; `custom` covers everything
/// else (every N days/weeks, or every N months/years). Derived from a
/// schedule via `init(for:)`, then held as view state.
private enum ScheduleMode: String, CaseIterable, Identifiable {
    case everyMonth  // כל חודש
    case everyYear   // כל שנה
    case oneTime     // חד־פעמי
    case custom      // התאמה אישית

    var id: String { rawValue }

    /// Which mode best represents an existing schedule when the editor opens.
    /// The plain "every month" / "every year" presets win their exact match;
    /// anything else (averaged, or a multi-step interval) is custom.
    init(for schedule: BudgetSchedule) {
        if schedule.isOneTime {
            self = .oneTime
        } else if schedule.unit == .month, schedule.count == 1 {
            self = .everyMonth
        } else if schedule.unit == .year, schedule.count == 1 {
            self = .everyYear
        } else {
            self = .custom
        }
    }

    var hebrewLabel: String {
        switch self {
        case .everyMonth: return "כל חודש"
        case .everyYear:  return "כל שנה"
        case .oneTime:    return "חד־פעמי"
        case .custom:     return "התאמה אישית"
        }
    }

    var systemImage: String {
        switch self {
        case .everyMonth: return "arrow.clockwise"
        case .everyYear:  return "calendar.circle"
        case .oneTime:    return "1.circle"
        case .custom:     return "slider.horizontal.3"
        }
    }
}
