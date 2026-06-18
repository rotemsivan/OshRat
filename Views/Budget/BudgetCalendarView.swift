import SwiftUI
import SwiftData

/// Soft violet used to flag Israeli holidays on the calendar — distinct from
/// the accent (today / selected) and the income / expense dot colours.
private let holidayTint = Color(light: Color(hex: "7E57C2"), dark: Color(hex: "B39DDB"))

/// A month calendar for *planning* the budget. Scheduled budget lines —
/// salary on the 10th, rent on the 2nd, a yearly car test, a one-off gift —
/// show as coloured dots on the days they land. Tapping a day reveals what's
/// planned for it and lets the user add more; the header rolls the whole
/// month into planned income / expense / net.
///
/// Adding and editing reuse the very same income/expense editor sheets as
/// the dashboard budget editor (now schedule-aware), so a line created here
/// behaves identically to one created during onboarding.
struct BudgetCalendarView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \BudgetItem.name) private var budgetItems: [BudgetItem]
    @Query(sort: \Category.name) private var categories: [Category]
    @Query private var profiles: [UserProfile]
    @Query(sort: \FXRateSnapshot.fetchedAt, order: .reverse) private var fxSnapshots: [FXRateSnapshot]

    /// First day of the month currently on screen.
    @State private var visibleMonth: Date = Self.startOfMonth(for: .now)
    /// Day the user has tapped (start-of-day), if any.
    @State private var selectedDay: Date? = Calendar.current.startOfDay(for: .now)

    /// Date a newly-added line is seeded around (the tapped day).
    @State private var addSeedDate: Date = .now
    @State private var isChoosingKind = false

    @State private var editingIncome: IncomeSourceDraft?
    @State private var pendingIncomeItem: BudgetItem?
    @State private var editingExpense: PlannedExpenseDraft?
    @State private var pendingExpenseItem: BudgetItem?

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    monthHeader
                    MonthPlanSummary(
                        income: monthTotals.income,
                        expense: monthTotals.expense,
                        currencyCode: preferredCurrencyCode,
                        fxUnavailable: monthTotals.fxUnavailable
                    )
                    calendarCard
                    selectedDaySection
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, HomeBottomBar.barHeight + HomeBottomBar.homeButtonDiameter + Theme.Spacing.lg)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(Text("יומן התקציב"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("הוספת פריט", systemImage: "plus", action: beginAddForSelectedDay)
            }
        }
        .confirmationDialog("הוספת פריט לתקציב", isPresented: $isChoosingKind, titleVisibility: .visible) {
            Button("הכנסה", action: addIncome)
            Button("הוצאה", action: addExpense)
            Button("ביטול", role: .cancel) {}
        }
        .sheet(item: $editingIncome) { draft in
            IncomeSourceEditorSheet(
                draft: draft,
                isNew: pendingIncomeItem == nil,
                onSave: saveIncome,
                onCancel: {}
            )
        }
        .sheet(item: $editingExpense) { draft in
            PlannedExpenseEditorSheet(
                categories: categories,
                draft: draft,
                isNew: pendingExpenseItem == nil,
                onSave: saveExpense,
                onCancel: {}
            )
        }
    }

    // MARK: - Header

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.backward")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(Theme.Colors.accent)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("החודש הקודם"))

            Spacer()

            VStack(spacing: 2) {
                Text(monthYearLabel)
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if !isViewingCurrentMonth {
                    Button("חזרה להיום", action: jumpToToday)
                        .font(Theme.Typography.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Colors.accent)
                }
            }

            Spacer()

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.forward")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(Theme.Colors.accent)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("החודש הבא"))
        }
    }

    // MARK: - Calendar grid

    private var calendarCard: some View {
        VStack(spacing: Theme.Spacing.sm) {
            weekdayHeader
            LazyVGrid(columns: Self.columns, spacing: Theme.Spacing.xs) {
                ForEach(gridDays, id: \.self) { day in
                    CalendarDayCell(
                        date: day,
                        isInMonth: calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month),
                        isToday: calendar.isDateInToday(day),
                        isSelected: selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false,
                        isSaturday: calendar.component(.weekday, from: day) == 7,
                        items: itemsByDay[calendar.startOfDay(for: day)] ?? [],
                        holiday: holidaysByDay[calendar.startOfDay(for: day)]
                    )
                    .onTapGesture { select(day) }
                }
            }
        }
        .cardStyle()
    }

    private var weekdayHeader: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(orderedWeekdays, id: \.symbol) { weekday in
                Text(weekday.symbol)
                    .font(Theme.Typography.caption)
                    // Saturday matches the grid's non-business tint.
                    .foregroundStyle(weekday.isSaturday ? holidayTint : Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Selected-day detail

    private var selectedDaySection: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.md) {
            Text(selectedDayLabel)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .trailing)

            if let selectedDayHoliday {
                Label(selectedDayHoliday.name, systemImage: "sparkles")
                    .font(Theme.Typography.body)
                    .foregroundStyle(holidayTint)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if selectedDayItems.isEmpty {
                Text("אין פריטים מתוכננים ליום זה.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                ForEach(selectedDayItems) { item in
                    CalendarItemRow(item: item)
                        .contentShape(.rect)
                        .onTapGesture { edit(item) }
                        .contextMenu {
                            Button("עריכה", systemImage: "pencil") { edit(item) }
                            Button("מחיקה", systemImage: "trash", role: .destructive) { delete(item) }
                        }
                }
            }

            Button(action: beginAddForSelectedDay) {
                Label("הוספת פריט ליום זה", systemImage: "plus.circle.fill")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.accent)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .cardStyle()
    }

    // MARK: - Actions

    private func select(_ day: Date) {
        // Tapping a spill-over day from an adjacent month flips the visible
        // month to that day's month, so the user can plan straight across
        // the month boundary.
        if !calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month) {
            visibleMonth = Self.startOfMonth(for: day, calendar: calendar)
        }
        selectedDay = calendar.startOfDay(for: day)
    }

    private func shiftMonth(by delta: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: delta, to: visibleMonth) else { return }
        visibleMonth = Self.startOfMonth(for: shifted, calendar: calendar)
    }

    private func jumpToToday() {
        visibleMonth = Self.startOfMonth(for: .now, calendar: calendar)
        selectedDay = calendar.startOfDay(for: .now)
    }

    private func beginAddForSelectedDay() {
        addSeedDate = selectedDay ?? .now
        isChoosingKind = true
    }

    private func addIncome() {
        pendingIncomeItem = nil
        editingIncome = IncomeSourceDraft(currencyCode: preferredCurrencyCode, schedule: seededSchedule())
    }

    private func addExpense() {
        pendingExpenseItem = nil
        editingExpense = PlannedExpenseDraft(currencyCode: preferredCurrencyCode, schedule: seededSchedule())
    }

    private func edit(_ item: BudgetItem) {
        switch item.kind {
        case .income:
            pendingIncomeItem = item
            editingIncome = IncomeSourceDraft(from: item)
        case .expense:
            pendingExpenseItem = item
            editingExpense = PlannedExpenseDraft(from: item)
        }
    }

    private func delete(_ item: BudgetItem) {
        withAnimation {
            modelContext.delete(item)
            try? modelContext.save()
        }
    }

    private func saveIncome(_ draft: IncomeSourceDraft) {
        if let existing = pendingIncomeItem {
            draft.apply(to: existing)
        } else {
            let item = BudgetItem(kind: .income)
            draft.apply(to: item)
            modelContext.insert(item)
        }
        pendingIncomeItem = nil
        try? modelContext.save()
    }

    private func saveExpense(_ draft: PlannedExpenseDraft) {
        if let existing = pendingExpenseItem {
            draft.apply(to: existing)
        } else {
            let item = BudgetItem(kind: .expense)
            draft.apply(to: item)
            modelContext.insert(item)
        }
        pendingExpenseItem = nil
        try? modelContext.save()
    }

    /// Seed a fresh line as a one-off on the tapped day, but pre-fill the
    /// day/month too so switching it to monthly ("every month on the 22nd")
    /// or yearly keeps the date the user already picked.
    private func seededSchedule() -> BudgetSchedule {
        let comps = calendar.dateComponents([.day, .month, .year], from: addSeedDate)
        return BudgetSchedule(
            isOneTime: true,
            dayOfMonth: comps.day ?? 1,
            usesSpecificDay: true,
            month: comps.month ?? 1,
            anchorYear: comps.year ?? Calendar.current.component(.year, from: .now),
            oneTimeDate: addSeedDate
        )
    }

    // MARK: - Derived data

    private var preferredCurrencyCode: String {
        profiles.first?.preferredCurrencyCode ?? "ILS"
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "he_IL")
        return calendar
    }

    private var visibleMonthComponents: (month: Int, year: Int) {
        let comps = calendar.dateComponents([.month, .year], from: visibleMonth)
        return (comps.month ?? 1, comps.year ?? 2000)
    }

    private var isViewingCurrentMonth: Bool {
        calendar.isDate(visibleMonth, equalTo: .now, toGranularity: .month)
    }

    /// Scheduled lines that resolve to a concrete day in the visible month,
    /// bucketed by that day. Undated recurring lines (a plain monthly budget)
    /// aren't pinned to a day, so they don't appear on the grid — they still
    /// roll into the month total below.
    private var itemsByDay: [Date: [BudgetItem]] {
        let (month, year) = visibleMonthComponents
        var buckets: [Date: [BudgetItem]] = [:]
        for item in budgetItems {
            guard let date = item.occurrenceDate(inMonth: month, year: year, calendar: calendar) else { continue }
            buckets[calendar.startOfDay(for: date), default: []].append(item)
        }
        return buckets
    }

    private var selectedDayItems: [BudgetItem] {
        guard let selectedDay else { return [] }
        return itemsByDay[calendar.startOfDay(for: selectedDay)] ?? []
    }

    /// Israeli holidays falling on the visible grid, keyed by day, so the
    /// same lookup drives both the grid tint and the detail header.
    private var holidaysByDay: [Date: IsraeliHoliday] {
        var map: [Date: IsraeliHoliday] = [:]
        for day in gridDays {
            if let holiday = IsraeliHolidays.holiday(for: day) {
                map[calendar.startOfDay(for: day)] = holiday
            }
        }
        return map
    }

    private var selectedDayHoliday: IsraeliHoliday? {
        guard let selectedDay else { return nil }
        return holidaysByDay[calendar.startOfDay(for: selectedDay)]
    }

    /// Planned income / expense for the whole visible month, converted into
    /// the preferred currency. Mirrors the dashboard card's drop-if-can't-
    /// convert behaviour and reports whether anything was dropped.
    private var monthTotals: (income: Decimal, expense: Decimal, fxUnavailable: Bool) {
        let (month, year) = visibleMonthComponents
        var income = Decimal(0)
        var expense = Decimal(0)
        var fxUnavailable = false
        for item in budgetItems {
            let amount = item.plannedAmount(inMonth: month, year: year)
            guard amount != 0 else { continue }
            guard let converted = convertToPreferred(amount, from: item.currencyCode) else {
                fxUnavailable = true
                continue
            }
            switch item.kind {
            case .income:  income += converted
            case .expense: expense += converted
            }
        }
        return (income, expense, fxUnavailable)
    }

    private func convertToPreferred(_ amount: Decimal, from currency: String) -> Decimal? {
        if currency == preferredCurrencyCode { return amount }
        guard let snapshot = fxSnapshots.first else { return nil }
        return CurrencyConverter.convert(amount, from: currency, to: preferredCurrencyCode, using: snapshot)
    }

    /// Six weeks of days starting from the first day of the grid's first
    /// week, so the grid height stays constant from month to month.
    private var gridDays: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)
        else { return [] }
        var days: [Date] = []
        var cursor = firstWeek.start
        for _ in 0..<42 {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    /// Weekday header symbols in display order, each flagged if it's
    /// Saturday (weekday 7), so the header can tint it like the grid.
    private var orderedWeekdays: [(symbol: String, isSaturday: Bool)] {
        let symbols = calendar.veryShortWeekdaySymbols   // index 0 == Sunday
        let offset = calendar.firstWeekday - 1
        return (0..<7).map { position in
            let weekdayIndex = (offset + position) % 7
            return (symbols[weekdayIndex], weekdayIndex == 6)
        }
    }

    private var monthYearLabel: String {
        visibleMonth.formatted(.dateTime.locale(Locale(identifier: "he_IL")).month(.wide).year())
    }

    private var selectedDayLabel: String {
        guard let selectedDay else { return "" }
        return selectedDay.formatted(
            .dateTime.locale(Locale(identifier: "he_IL")).weekday(.wide).day().month(.wide)
        )
    }

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs), count: 7)

    private static func startOfMonth(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }
}

// MARK: - Day cell

/// One day in the month grid. Highlights today with an accent ring and the
/// selected day with a filled accent disc, and shows up to three coloured
/// dots for the budget lines that land on it.
private struct CalendarDayCell: View {
    let date: Date
    let isInMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let isSaturday: Bool
    let items: [BudgetItem]
    let holiday: IsraeliHoliday?

    private var isHoliday: Bool { holiday != nil }

    /// Saturday and rest-day holidays are non-business days — they get the
    /// stronger "violet disc" treatment; working-day holidays only tint the
    /// number, so a day off still reads differently from a working festival.
    private var isNonBusiness: Bool { isSaturday || (holiday?.isRestDay == true) }

    private var dayNumber: String {
        date.formatted(.dateTime.locale(Locale(identifier: "he_IL")).day())
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(dayNumber)
                .font(Theme.Typography.body)
                .monospacedDigit()
                .foregroundStyle(numberColor)
                .frame(width: 30, height: 30)
                .background(numberBackground)
                .overlay(numberRing)

            dots
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .opacity(isInMonth ? 1 : 0.35)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var dots: some View {
        HStack(spacing: 3) {
            ForEach(Array(dotColors.enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
            }
        }
        // Reserve the dot row's height even when empty so every cell is the
        // same height and the grid rows stay aligned.
        .frame(height: 6)
    }

    @ViewBuilder
    private var numberBackground: some View {
        if isSelected {
            Circle().fill(Theme.Colors.accent)
        } else if isNonBusiness {
            // Faint violet disc marks a non-business day (Shabbat or a rest
            // holiday) without competing with the accent disc/ring.
            Circle().fill(holidayTint.opacity(0.18))
        }
    }

    @ViewBuilder
    private var numberRing: some View {
        // Only show the "today" ring when nothing else fills the disc.
        if isToday && !isSelected && !isNonBusiness {
            Circle().stroke(Theme.Colors.accent, lineWidth: 1.5)
        }
    }

    // Priority: selected (white on accent) > non-business / holiday (violet)
    // > today (accent) > normal.
    private var numberColor: Color {
        if isSelected { return .white }
        if isNonBusiness || isHoliday { return holidayTint }
        if isToday { return Theme.Colors.accent }
        return Theme.Colors.textPrimary
    }

    /// Up to three dots, one per line, coloured by kind/nature.
    private var dotColors: [Color] {
        items.prefix(3).map { Self.dotColor(for: $0) }
    }

    private static func dotColor(for item: BudgetItem) -> Color {
        switch item.kind {
        case .income:
            return Theme.Colors.income
        case .expense:
            return item.category?.nature == .want ? Theme.Colors.wants : Theme.Colors.expense
        }
    }

    private var accessibilityText: String {
        var parts = [date.formatted(.dateTime.locale(Locale(identifier: "he_IL")).day().month(.wide))]
        if let holiday { parts.append(holiday.name) }
        if !items.isEmpty {
            // Localized so VoiceOver reads a grammatical count (פריט אחד / N פריטים).
            parts.append(String(localized: "\(items.count) פריטים"))
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Item rows

/// A scheduled-line row inside the selected-day list: a kind/nature dot,
/// the line's name + cadence, and its amount.
private struct CalendarItemRow: View {
    let item: BudgetItem

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(item.scheduleDescription)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.sm)

            Text(item.plannedAmount.formatted(.currency(code: item.currencyCode)))
                .font(Theme.Typography.amount)
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private var dotColor: Color {
        switch item.kind {
        case .income:
            return Theme.Colors.income
        case .expense:
            return item.category?.nature == .want ? Theme.Colors.wants : Theme.Colors.expense
        }
    }

    private var title: String {
        switch item.kind {
        case .income:
            return item.name.isEmpty ? "הכנסה" : item.name
        case .expense:
            let categoryName = item.category?.name ?? "ללא קטגוריה"
            let note = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return note.isEmpty ? categoryName : "\(categoryName) — \(note)"
        }
    }
}

// MARK: - Month plan summary

/// Compact roll-up of the visible month's planned income, expense and net,
/// in the preferred currency. The first thing the user sees when they land
/// on a month.
private struct MonthPlanSummary: View {
    let income: Decimal
    let expense: Decimal
    let currencyCode: String
    let fxUnavailable: Bool

    private var net: Decimal { income - expense }

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.sm) {
            row(title: "הכנסות מתוכננות", amount: income, color: Theme.Colors.income)
            row(title: "הוצאות מתוכננות", amount: expense, color: Theme.Colors.expense)

            HStack {
                Text("נטו")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text(net.formattedSignedCurrency(currencyCode))
                    .font(Theme.Typography.amount)
                    .foregroundStyle(net >= 0 ? Theme.Colors.income : Theme.Colors.expense)
                    .monospacedDigit()
            }

            if fxUnavailable {
                Text("חלק מהסכומים לא הומרו — שערי חליפין לא זמינים.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .cardStyle()
    }

    private func row(title: LocalizedStringKey, amount: Decimal, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Text(amount.formatted(.currency(code: currencyCode)))
                .font(Theme.Typography.amount)
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
        }
    }
}

#Preview {
    NavigationStack {
        BudgetCalendarView()
    }
    .environment(\.layoutDirection, .rightToLeft)
    .modelContainer(
        for: [
            UserProfile.self, Account.self, Holding.self, Category.self,
            Transaction.self, BudgetItem.self, Goal.self, FXRateSnapshot.self
        ],
        inMemory: true
    )
}
