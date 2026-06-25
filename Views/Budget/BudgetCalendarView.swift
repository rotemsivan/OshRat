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
/// The month grid itself is Apple's native `UICalendarView` (the same one the
/// Calendar and Reminders apps use), wrapped in `BudgetMonthCalendar` below.
/// We adopt it instead of a hand-rolled grid so month navigation, the
/// today/selection styling, and RTL all come straight from the system. The
/// one thing the system can't do — paint per-day budget dots and flag
/// Shabbat / holidays — we add back through its decoration delegate.
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

    /// First day of the month currently on screen. Mirrors the native
    /// calendar's visible month (it drives the header summary and which
    /// month's dots we compute); the calendar owns navigation, this just
    /// follows it.
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
                    calendarCard
                    MonthPlanSummary(
                        income: monthTotals.income,
                        expense: monthTotals.expense,
                        currencyCode: preferredCurrencyCode,
                        fxUnavailable: monthTotals.fxUnavailable
                    )
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

    // MARK: - Calendar

    private var calendarCard: some View {
        BudgetMonthCalendar(
            selectedDay: $selectedDay,
            visibleMonth: $visibleMonth,
            calendar: calendar,
            decorations: decorations
        )
        .frame(maxWidth: .infinity)
        .cardStyle()
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

    /// Budget lines that resolve to the tapped day. Computed from the
    /// selected day's *own* month (not the visible month) so the detail list
    /// stays correct even if the user has paged the calendar elsewhere while
    /// keeping an earlier day selected.
    private var selectedDayItems: [BudgetItem] {
        guard let selectedDay else { return [] }
        let comps = calendar.dateComponents([.month, .year], from: selectedDay)
        let month = comps.month ?? 1
        let year = comps.year ?? 2000
        return budgetItems.filter { item in
            guard let date = item.occurrenceDate(inMonth: month, year: year, calendar: calendar) else { return false }
            return calendar.isDate(date, inSameDayAs: selectedDay)
        }
    }

    private var selectedDayHoliday: IsraeliHoliday? {
        guard let selectedDay else { return nil }
        return IsraeliHolidays.holiday(for: selectedDay)
    }

    /// Per-day decoration data for the native calendar, keyed by start-of-day.
    /// We compute the visible month plus its two neighbours so paging shows
    /// the dots immediately rather than a beat after the month settles. All
    /// the budget/holiday logic stays here in SwiftUI; the wrapper's delegate
    /// just renders dots from this plain dictionary (no SwiftData crosses into
    /// UIKit).
    private var decorations: [Date: CalendarDayDecoration] {
        var result: [Date: CalendarDayDecoration] = [:]

        for offset in -1...1 {
            guard let monthDate = calendar.date(byAdding: .month, value: offset, to: visibleMonth),
                  let interval = calendar.dateInterval(of: .month, for: monthDate) else { continue }
            let comps = calendar.dateComponents([.month, .year], from: monthDate)
            let month = comps.month ?? 1
            let year = comps.year ?? 2000

            // Budget lines that land on a concrete day this month.
            for item in budgetItems {
                guard let date = item.occurrenceDate(inMonth: month, year: year, calendar: calendar) else { continue }
                let day = calendar.startOfDay(for: date)
                result[day, default: CalendarDayDecoration()].dotColors.append(budgetDotColor(for: item))
            }

            // Shabbat + Israeli holidays, day by day.
            var cursor = interval.start
            while cursor < interval.end {
                let day = calendar.startOfDay(for: cursor)
                let isSaturday = calendar.component(.weekday, from: day) == 7
                let holiday = IsraeliHolidays.holiday(for: day)
                if isSaturday || holiday != nil {
                    var decoration = result[day] ?? CalendarDayDecoration()
                    decoration.isHoliday = holiday != nil
                    decoration.isNonBusiness = isSaturday || (holiday?.isRestDay == true)
                    result[day] = decoration
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
        }

        // Cap the budget dots so a busy day's cluster stays tidy under the
        // (small) decoration area.
        for (day, var decoration) in result {
            decoration.dotColors = Array(decoration.dotColors.prefix(3))
            result[day] = decoration
        }
        return result
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

    private var selectedDayLabel: String {
        guard let selectedDay else { return "" }
        return selectedDay.formatted(
            .dateTime.locale(Locale(identifier: "he_IL")).weekday(.wide).day().month(.wide)
        )
    }

    private static func startOfMonth(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }
}

/// Dot colour for a budget line on the calendar: income green, a "want"
/// expense its calmer orange, everything else the expense red. Shared by the
/// month-grid decorations and the selected-day rows so a line reads the same
/// colour wherever it appears.
private func budgetDotColor(for item: BudgetItem) -> Color {
    switch item.kind {
    case .income:
        return Theme.Colors.income
    case .expense:
        return item.category?.nature == .want ? Theme.Colors.wants : Theme.Colors.expense
    }
}

// MARK: - Native month calendar

/// Plain, value-type description of what a single day should show on the
/// calendar — its budget dots plus whether it's a Shabbat / holiday day.
/// Computed in SwiftUI and handed to the UIKit calendar, so no SwiftData
/// model ever crosses into UIKit. `Equatable` so the wrapper can reload only
/// the days whose decoration actually changed.
private struct CalendarDayDecoration: Equatable {
    var dotColors: [Color] = []
    /// A non-business day (Shabbat or a rest-day holiday) — the days the
    /// income business-day shift cares about. Gets the violet marker.
    var isNonBusiness: Bool = false
    /// Any holiday (including the working-day ones like Hanukkah/Purim), so
    /// even a festival that doesn't move a salary still reads as special.
    var isHoliday: Bool = false

    var hasContent: Bool { !dotColors.isEmpty || isNonBusiness || isHoliday }
}

/// SwiftUI wrapper over `UICalendarView`. The calendar owns navigation,
/// selection styling and RTL; we feed it a single selected day, mirror the
/// visible month back out (for the header summary), and supply per-day dots
/// through the decoration delegate.
private struct BudgetMonthCalendar: UIViewRepresentable {
    @Binding var selectedDay: Date?
    @Binding var visibleMonth: Date
    let calendar: Calendar
    let decorations: [Date: CalendarDayDecoration]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = calendar
        view.locale = Locale(identifier: "he_IL")
        view.tintColor = UIColor(Theme.Colors.accent)
        view.delegate = context.coordinator
        // The app is pinned RTL on every device; match it so the weekday
        // columns read right-to-left like the rest of the app, regardless of
        // the device language.
        view.semanticContentAttribute = .forceRightToLeft

        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        selection.setSelected(dayComponents(selectedDay), animated: false)
        view.selectionBehavior = selection

        view.setVisibleDateComponents(monthComponents(visibleMonth), animated: false)
        context.coordinator.lastDecorations = decorations
        return view
    }

    func updateUIView(_ uiView: UICalendarView, context: Context) {
        // Refresh the coordinator's view of the bindings/decorations each pass.
        context.coordinator.parent = self

        // Keep the native selection in step with the binding. We never push
        // the *visible month* in (the calendar owns navigation), so there's
        // no risk of fighting the user's paging.
        if let selection = uiView.selectionBehavior as? UICalendarSelectionSingleDate {
            let desired = dayComponents(selectedDay)
            if !Self.sameDay(selection.selectedDate, desired) {
                selection.setSelected(desired, animated: false)
            }
        }

        // Reload dots only when the data actually changed (a line added/edited,
        // or a neighbouring month scrolled into the precompute window),
        // touching just the affected days so the grid never flashes.
        if context.coordinator.lastDecorations != decorations {
            let changed = Set(context.coordinator.lastDecorations.keys).union(decorations.keys)
            context.coordinator.lastDecorations = decorations
            if !changed.isEmpty {
                uiView.reloadDecorations(forDateComponents: changed.map { dayComponents($0) }, animated: false)
            }
        }
    }

    /// Take the width SwiftUI offers and report the height the calendar needs
    /// at that width. Without this, `UICalendarView`'s large intrinsic width
    /// pushes the whole column wider than the screen (the cards lose their
    /// margins) and its decoration area mis-lays-out (the dots vanish).
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UICalendarView, context: Context) -> CGSize? {
        let proposedWidth = proposal.width ?? uiView.intrinsicContentSize.width
        guard proposedWidth.isFinite, proposedWidth > 0 else { return nil }
        let fitted = uiView.systemLayoutSizeFitting(
            CGSize(width: proposedWidth, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: proposedWidth, height: fitted.height)
    }

    // MARK: Component helpers

    private func monthComponents(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month], from: date)
    }

    private func dayComponents(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day], from: date)
    }

    private func dayComponents(_ date: Date?) -> DateComponents? {
        date.map { dayComponents($0) }
    }

    /// Compares two day selections on year/month/day alone — the calendar may
    /// hand back extra fields, so a full `==` would spuriously differ.
    private static func sameDay(_ a: DateComponents?, _ b: DateComponents?) -> Bool {
        a?.year == b?.year && a?.month == b?.month && a?.day == b?.day
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: BudgetMonthCalendar
        /// Last decoration set handed to the calendar, so `updateUIView` can
        /// reload only when it genuinely changes.
        var lastDecorations: [Date: CalendarDayDecoration] = [:]

        init(_ parent: BudgetMonthCalendar) { self.parent = parent }

        func calendarView(
            _ calendarView: UICalendarView,
            decorationFor dateComponents: DateComponents
        ) -> UICalendarView.Decoration? {
            guard let date = parent.calendar.date(from: dateComponents) else { return nil }
            let day = parent.calendar.startOfDay(for: date)
            guard let decoration = parent.decorations[day], decoration.hasContent else { return nil }
            return .customView { BudgetMonthCalendar.decorationView(decoration) }
        }

        func dateSelection(
            _ selection: UICalendarSelectionSingleDate,
            didSelectDate dateComponents: DateComponents?
        ) {
            guard let dateComponents, let date = parent.calendar.date(from: dateComponents) else {
                parent.selectedDay = nil
                return
            }
            parent.selectedDay = parent.calendar.startOfDay(for: date)
        }

        func calendarView(
            _ calendarView: UICalendarView,
            didChangeVisibleDateComponentsFrom previousDateComponents: DateComponents
        ) {
            guard let date = parent.calendar.date(from: calendarView.visibleDateComponents) else { return }
            let month = parent.calendar.dateInterval(of: .month, for: date)?.start ?? date
            // Defer the binding write out of the layout pass UIKit is in the
            // middle of, so SwiftUI doesn't warn about mutating state mid-update.
            DispatchQueue.main.async {
                if !self.parent.calendar.isDate(self.parent.visibleMonth, equalTo: month, toGranularity: .month) {
                    self.parent.visibleMonth = month
                }
            }
        }
    }

    // MARK: Decoration view

    /// The small dot cluster shown under a day number: a violet dot for a
    /// Shabbat / holiday day, then one dot per budget line (income green,
    /// expense red, want orange), already capped by the host.
    private static func decorationView(_ decoration: CalendarDayDecoration) -> UIView {
        var colors: [UIColor] = []
        if decoration.isNonBusiness || decoration.isHoliday {
            colors.append(UIColor(holidayTint))
        }
        colors.append(contentsOf: decoration.dotColors.map { UIColor($0) })
        return DecorationDotsView(colors: colors)
    }
}

/// A fixed row of small coloured dots, used as a `UICalendarView` decoration.
/// A hand-laid-out `UIView` rather than a `UIStackView` on purpose: the
/// calendar sizes a custom decoration from its `intrinsicContentSize`, and a
/// stack view reports none — which collapsed the dots to nothing.
private final class DecorationDotsView: UIView {
    private let colors: [UIColor]
    private let dotSize: CGFloat = 6
    private let spacing: CGFloat = 2

    init(colors: [UIColor]) {
        self.colors = colors
        super.init(frame: .zero)
        for color in colors {
            let dot = UIView()
            dot.backgroundColor = color
            dot.layer.cornerRadius = dotSize / 2
            addSubview(dot)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        guard !colors.isEmpty else { return .zero }
        let width = CGFloat(colors.count) * dotSize + CGFloat(colors.count - 1) * spacing
        return CGSize(width: width, height: dotSize)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let y = (bounds.height - dotSize) / 2
        for (index, dot) in subviews.enumerated() {
            dot.frame = CGRect(x: CGFloat(index) * (dotSize + spacing), y: y, width: dotSize, height: dotSize)
        }
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
                .fill(budgetDotColor(for: item))
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
            Transaction.self, TransactionAttachment.self, BudgetItem.self, Goal.self, FXRateSnapshot.self
        ],
        inMemory: true
    )
}
