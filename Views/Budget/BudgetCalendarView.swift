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
///
/// It's also where scheduled lines become real transactions: a day's rows
/// swipe (visual right → the wallet, which opens the new-transaction sheet
/// pre-filled; visual left → delete), occurrences already logged turn grey,
/// and opening the tab acknowledges today's budget reminder — clearing the
/// badge on the tab bar and marking the rows it was about.
struct BudgetCalendarView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \BudgetItem.name) private var budgetItems: [BudgetItem]
    /// Live transactions that log a budget occurrence — what greys a row.
    /// Filtered in the store so the calendar doesn't scan the whole ledger.
    @Query(filter: #Predicate<Transaction> { $0.deletedAt == nil && $0.budgetOccurrenceDate != nil })
    private var budgetLoggedTransactions: [Transaction]
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

    @State private var editingIncome: IncomeSourceDraft?
    @State private var pendingIncomeItem: BudgetItem?
    @State private var editingExpense: PlannedExpenseDraft?
    @State private var pendingExpenseItem: BudgetItem?
    /// The occurrence the wallet swipe is logging, as an id + day (not the
    /// model — see `CalendarDayEntry`).
    @State private var loggingRequest: BudgetLogRequest?
    /// The row whose delete is awaiting confirmation. A budget line has no
    /// Recently Deleted, and a recurring one takes every month with it, so a
    /// full swipe asks first — the same call `AssetsSummaryCard` makes for
    /// accounts.
    @State private var entryPendingDelete: CalendarDayEntry?
    /// Row height for the day's embedded list, which can't size itself (see
    /// `dayItemsList`). Scaled so larger text sizes don't clip the second line.
    @ScaledMetric(relativeTo: .body) private var dayRowHeight: CGFloat = 64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Scroll anchor for the selected-day card.
    private static let selectedDayAnchor = "selectedDay"

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            ScrollViewReader { proxy in
            ScrollView {
                // The month's plan rides inside the calendar card as one line,
                // so the day's items sit as close under the grid as they can.
                VStack(spacing: Theme.Spacing.lg) {
                    calendarCard
                    selectedDaySection
                        .id(Self.selectedDayAnchor)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                // No top pad — the large navigation title above already
                // separates the calendar card from the chrome.
                .padding(.top, 0)
                // The day card ends in the "הוספת פריט ליום זה" button, so this
                // screen needs the full clearance — the bar *and* the floating
                // "+" — or the last thing on the page is the one thing you
                // can't tap.
                .padding(.bottom, HomeBottomBar.floatingButtonClearance)
            }
            .scrollIndicators(.hidden)
            // A six-week month pushes the day card under the tab bar, so a
            // tapped date scrolls its items up into view. Only on a change:
            // landing on the tab keeps the calendar itself in view.
            .onChange(of: selectedDay) { _, newDay in
                guard newDay != nil else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                    proxy.scrollTo(Self.selectedDayAnchor, anchor: .top)
                }
            }
            }
        }
        .navigationTitle(Text("יומן התקציב"))
        // Large, matching תובנות and תנועות — one title style across the tabs.
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                addMenu {
                    Label("הוספת פריט", systemImage: "plus")
                }
            }
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
        .sheet(item: $loggingRequest) { request in
            if let item = budgetItem(for: request.itemID) {
                NewTransactionSheet(logging: item, occurrenceDay: request.occurrenceDay)
            }
        }
        .alert(
            Text("מחיקת הפריט מהתקציב?"),
            isPresented: deleteAlertBinding,
            presenting: entryPendingDelete
        ) { entry in
            Button("מחיקה", role: .destructive) { delete(entry) }
            Button("ביטול", role: .cancel) {}
        } message: { entry in
            if entry.isRecurring {
                Text("זה פריט קבוע — המחיקה תסיר אותו מכל החודשים, לא רק מהיום הזה.")
            } else {
                Text("לא ניתן לשחזר את הפריט אחרי המחיקה.")
            }
        }
        // Opening the tab *is* seeing today's reminder: stamp today's due lines
        // as acknowledged, which clears the tab-bar badge (and any toast still
        // waiting for them). Keyed on the due set so a line added for today
        // while the tab is open is acknowledged too.
        .task(id: dueTodayIDs) {
            BudgetReminderService.markAcknowledged(dueToday, on: today, in: modelContext)
        }
    }

    // MARK: - Calendar

    private var calendarCard: some View {
        VStack(spacing: Theme.Spacing.sm) {
            BudgetMonthCalendar(
                selectedDay: $selectedDay,
                visibleMonth: $visibleMonth,
                calendar: calendar,
                decorations: decorations
            )
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(height: 1)

            MonthPlanStrip(
                income: monthTotals.income,
                expense: monthTotals.expense,
                currencyCode: preferredCurrencyCode,
                fxUnavailable: monthTotals.fxUnavailable
            )
        }
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

            let entries = selectedDayEntries
            if entries.isEmpty {
                Text("אין פריטים מתוכננים ליום זה.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                dayItemsList(entries)
            }

            addMenu {
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

    /// The day's rows, in a `List` purely for `.swipeActions` (they're
    /// `List`-only) — the same embedded, scroll-disabled, fixed-height list
    /// `AssetsSummaryCard` uses, so the screen's `ScrollView` stays the one
    /// scroller.
    ///
    /// Directions follow the other lists under RTL: the **trailing** edge
    /// (visual left, reached by swiping right) holds delete, and a full swipe
    /// fires it; the **leading** edge (visual right, swiping left) holds the
    /// wallet, which logs the occurrence. An occurrence already logged loses
    /// the wallet — logging it twice would count the money twice; deleting
    /// that transaction brings the wallet back.
    private func dayItemsList(_ entries: [CalendarDayEntry]) -> some View {
        List {
            ForEach(entries) { entry in
                CalendarItemRow(entry: entry)
                    .contentShape(.rect)
                    .onTapGesture { edit(entry) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(Text("הקש לעריכה"))
                    .contextMenu {
                        if !entry.isLogged {
                            Button("רישום כתנועה", systemImage: "wallet.bifold") { log(entry) }
                        }
                        Button("עריכה", systemImage: "pencil") { edit(entry) }
                        Button("מחיקה", systemImage: "trash", role: .destructive) {
                            entryPendingDelete = entry
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .frame(height: dayRowHeight)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            entryPendingDelete = entry
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel(Text("מחיקה"))
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if !entry.isLogged {
                            Button {
                                log(entry)
                            } label: {
                                Image(systemName: "wallet.bifold")
                            }
                            .tint(entry.kind == .income ? Theme.Colors.income : Theme.Colors.expense)
                            .accessibilityLabel(Text("רישום כתנועה"))
                        }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .frame(height: CGFloat(entries.count) * dayRowHeight)
    }

    // MARK: - Actions

    /// The "add a line" control: income / expense, in a `Menu` anchored to
    /// whichever button opened it.
    ///
    /// It replaces a `confirmationDialog`, which detaches from its source and
    /// surfaced away from the button that summoned it — the two choices
    /// belong *at* the button the user just pressed, not adrift on the screen.
    /// A `Menu` pops from its own label, so both entry points (the toolbar and
    /// the card's "הוספת פריט ליום זה") each open their options in place.
    private func addMenu<Content: View>(@ViewBuilder label: () -> Content) -> some View {
        Menu {
            Button("הכנסה", systemImage: "arrow.down.left", action: addIncome)
            Button("הוצאה", systemImage: "arrow.up.right", action: addExpense)
        } label: {
            label()
        }
    }

    private func addIncome() {
        pendingIncomeItem = nil
        editingIncome = IncomeSourceDraft(currencyCode: preferredCurrencyCode, schedule: seededSchedule())
    }

    private func addExpense() {
        pendingExpenseItem = nil
        editingExpense = PlannedExpenseDraft(currencyCode: preferredCurrencyCode, schedule: seededSchedule())
    }

    private func edit(_ entry: CalendarDayEntry) {
        guard let item = budgetItem(for: entry.id) else { return }
        switch item.kind {
        case .income:
            pendingIncomeItem = item
            editingIncome = IncomeSourceDraft(from: item)
        case .expense:
            pendingExpenseItem = item
            editingExpense = PlannedExpenseDraft(from: item)
        }
    }

    private func log(_ entry: CalendarDayEntry) {
        loggingRequest = BudgetLogRequest(itemID: entry.id, occurrenceDay: entry.occurrenceDay)
    }

    /// A hard delete, so the rows render from `CalendarDayEntry` values: the
    /// outgoing row keeps being drawn while it animates away, and reading a
    /// deleted model then traps (see CLAUDE.md, "Soft delete vs hard delete").
    private func delete(_ entry: CalendarDayEntry) {
        guard let item = budgetItem(for: entry.id) else { return }
        withAnimation {
            modelContext.delete(item)
            // A deleted line changes the month's plan; the budget
            // achievements need to know even though the row is gone.
            ProgressService.recordBudgetLineDeleted(in: modelContext)
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
    ///
    /// Reads `selectedDay` directly. There used to be a separate `addSeedDate`
    /// stamped when the add flow began, which only existed because the
    /// confirmation dialog put a step between the tap and the choice; the menu
    /// fires its action immediately, so the selected day *is* the seed.
    private func seededSchedule() -> BudgetSchedule {
        let addSeedDate = selectedDay ?? .now
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

    /// The tapped day's rows, as value snapshots. Resolved through
    /// `BudgetReminderService.occurrence(of:on:)` — the selected day's *own*
    /// month, not the visible one, so the list stays right if the user pages
    /// away while keeping an earlier day selected — and through the same
    /// service the reminder uses, so "due today" can't mean two things.
    private var selectedDayEntries: [CalendarDayEntry] {
        guard let selectedDay else { return [] }
        let logged = loggedOccurrences
        let isToday = calendar.isDate(selectedDay, inSameDayAs: today)
        return budgetItems.compactMap { item in
            guard let occurrence = BudgetReminderService.occurrence(of: item, on: selectedDay) else { return nil }
            let isLogged = logged.contains(occurrence)
            return CalendarDayEntry(
                id: item.persistentModelID,
                occurrenceDay: occurrence.day,
                title: item.displayTitle,
                schedule: item.scheduleDescription,
                amount: item.plannedAmount,
                currencyCode: item.currencyCode,
                kind: item.kind,
                dotColor: budgetDotColor(for: item),
                isRecurring: !item.isOneTime,
                isLogged: isLogged,
                isDueToday: isToday && !isLogged
            )
        }
    }

    private var loggedOccurrences: Set<BudgetOccurrence> {
        BudgetReminderService.loggedOccurrences(from: budgetLoggedTransactions)
    }

    private var today: Date { calendar.startOfDay(for: .now) }

    /// Today's lines that nothing has logged yet — what the reminder is about.
    private var dueToday: [BudgetItem] {
        BudgetReminderService.dueItems(on: today, in: budgetItems, logged: loggedOccurrences)
    }

    private var dueTodayIDs: [PersistentIdentifier] {
        dueToday.map(\.persistentModelID)
    }

    /// Looks a row's line back up from the live query. A line deleted in the
    /// meantime is simply absent, rather than a model that traps on read.
    private func budgetItem(for id: PersistentIdentifier) -> BudgetItem? {
        budgetItems.first { $0.persistentModelID == id }
    }

    /// `.alert(presenting:)` wants a `Binding<Bool>`; bridge it through the
    /// optional entry, like `HomeView`'s auto-payout alert.
    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { entryPendingDelete != nil },
            set: { if !$0 { entryPendingDelete = nil } }
        )
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
        let logged = loggedOccurrences

        for offset in -1...1 {
            guard let monthDate = calendar.date(byAdding: .month, value: offset, to: visibleMonth),
                  let interval = calendar.dateInterval(of: .month, for: monthDate) else { continue }
            let comps = calendar.dateComponents([.month, .year], from: monthDate)
            let month = comps.month ?? 1
            let year = comps.year ?? 2000

            // Budget lines that land on a concrete day this month. A logged
            // occurrence's dot goes grey, matching its row below.
            for item in budgetItems {
                guard let date = item.occurrenceDate(inMonth: month, year: year, calendar: calendar) else { continue }
                let day = calendar.startOfDay(for: date)
                let isLogged = logged.contains(BudgetOccurrence(itemID: item.persistentModelID, day: day))
                result[day, default: CalendarDayDecoration()].dotColors.append(
                    isLogged ? loggedTint : budgetDotColor(for: item)
                )
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

/// Colour of an occurrence that has already been logged — its dot on the
/// grid and its row in the day list. Grey reads as "done, nothing to do".
private let loggedTint = Theme.Colors.textSecondary.opacity(0.6)

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

/// What one row of the day list shows, captured as plain values.
///
/// The rows are built from these rather than from `BudgetItem`: deleting a
/// line is a hard delete, and SwiftUI keeps drawing the outgoing row while it
/// animates away — a row still reading the model then traps (CLAUDE.md,
/// "Soft delete vs hard delete"). Anything that needs the model looks it up by
/// `id` at the moment it acts.
private struct CalendarDayEntry: Identifiable {
    let id: PersistentIdentifier
    /// Start of the scheduled day — which occurrence the row stands for.
    let occurrenceDay: Date
    let title: String
    let schedule: String
    let amount: Decimal
    let currencyCode: String
    let kind: TransactionKind
    let dotColor: Color
    let isRecurring: Bool
    /// A live transaction already logs this occurrence — the row turns grey.
    let isLogged: Bool
    /// Today's, and not yet logged: what the budget reminder is about.
    let isDueToday: Bool
}

/// Asks the calendar to open the new-transaction sheet for one occurrence.
/// An id rather than the model, for the same reason as `CalendarDayEntry`.
struct BudgetLogRequest: Identifiable, Hashable {
    let itemID: PersistentIdentifier
    let occurrenceDay: Date

    var id: Self { self }
}

/// A scheduled-line row inside the selected-day list: a kind/nature dot,
/// the line's name + cadence, and its amount. Logged occurrences are drawn in
/// grey with a check; today's unlogged ones carry the reminder's bell and an
/// accent wash, which is how opening the tab "marks" what it reminded about.
private struct CalendarItemRow: View {
    let entry: CalendarDayEntry

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(entry.isLogged ? loggedTint : entry.dotColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(entry.isLogged ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                    .lineLimit(1)
                statusLine
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.sm)

            Text(entry.amount.formatted(.currency(code: entry.currencyCode)))
                .font(Theme.Typography.amount)
                .foregroundStyle(entry.isLogged ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .frame(maxHeight: .infinity)
        .background {
            if entry.isDueToday {
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(Theme.Colors.accent.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                            .strokeBorder(Theme.Colors.accent.opacity(0.35), lineWidth: 1)
                    }
            }
        }
        .padding(.vertical, Theme.Spacing.xxs)
    }

    /// The cadence, prefixed by the occurrence's state when it has one.
    @ViewBuilder
    private var statusLine: some View {
        if entry.isLogged {
            Label {
                Text("נרשם כתנועה · \(entry.schedule)")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .labelStyle(CompactLabelStyle())
        } else if entry.isDueToday {
            Label {
                Text("להיום · החליקו לרישום")
            } icon: {
                Image(systemName: "bell.fill")
                    .foregroundStyle(Theme.Colors.accent)
            }
            .labelStyle(CompactLabelStyle())
        } else {
            Text(entry.schedule)
        }
    }
}

/// Icon and title tight together, for a caption-sized status line.
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            configuration.icon
            configuration.title
        }
    }
}

// MARK: - Month plan strip

/// The visible month's planned income, expense and net as one line along the
/// bottom of the calendar card — icons in place of the words, the same arrows
/// the add menu uses for income and expense. It used to be a card of its own,
/// which cost the day's items a screen's worth of room.
///
/// Whole shekels: three full amounts with agorot don't fit one phone-width
/// line, and a plan is an estimate anyway. At large text sizes the three
/// stack instead of squeezing.
private struct MonthPlanStrip: View {
    let income: Decimal
    let expense: Decimal
    let currencyCode: String
    let fxUnavailable: Bool

    private var net: Decimal { income - expense }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.md) {
                figures
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                figures
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var figures: some View {
        figure(
            symbol: "arrow.down.left",
            color: Theme.Colors.income,
            text: rounded(income),
            spoken: "הכנסות מתוכננות"
        )
        figure(
            symbol: "arrow.up.right",
            color: Theme.Colors.expense,
            text: rounded(expense),
            spoken: "הוצאות מתוכננות"
        )
        figure(
            symbol: "equal",
            color: net >= 0 ? Theme.Colors.income : Theme.Colors.expense,
            text: signedRounded(net),
            spoken: "נטו"
        )
        if fxUnavailable {
            Image(systemName: "exclamationmark.triangle")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityLabel(Text("חלק מהסכומים לא הומרו — שערי חליפין לא זמינים."))
        }
    }

    private func figure(symbol: String, color: Color, text: String, spoken: LocalizedStringKey) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: symbol)
                .font(Theme.Typography.caption.weight(.bold))
                .foregroundStyle(color)
            Text(text)
                .font(Theme.Typography.bodySmall.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
        }
        // Icons carry no words, so VoiceOver gets the name back.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
        .accessibilityValue(Text(text))
    }

    private func rounded(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: currencyCode).precision(.fractionLength(0)))
    }

    /// Same bidi-isolated trailing sign as `formattedSignedCurrency`, so the
    /// "+" / "-" stays on the visual left under RTL (see CLAUDE.md).
    private func signedRounded(_ amount: Decimal) -> String {
        let body = rounded(Swift.abs(amount))
        guard amount != 0 else { return body }
        return "\(body)\u{2066}\(amount > 0 ? "+" : "-")\u{2069}"
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
