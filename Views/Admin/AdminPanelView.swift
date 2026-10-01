import SwiftUI
import SwiftData

#if DEBUG

/// The developer's back room: fill the store with a ready-made life, or empty
/// it and start over.
///
/// Reachable from the dashboard header and from the onboarding screen — the
/// second one matters, because "start from scratch" puts the app back into the
/// wizard and there'd otherwise be no way back to the panel without finishing
/// it by hand.
///
/// Compiled out of release builds entirely, along with `DemoDataService`.
struct AdminPanelView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// History length for the next deploy. `nil` means "whatever the scenario
    /// says", which is the sensible default — each one is tuned to a length
    /// that shows it off.
    @State private var monthsOverride: Int?
    /// The scenario the user tapped, held until they confirm. Item-based so the
    /// dialog always has one to talk about.
    @State private var scenarioPendingDeploy: DemoScenario?
    @State private var isConfirmingWipe = false
    /// Recomputed on appear so the summary below can't go stale.
    @State private var summary = DemoStoreSummary()
    /// Today's standing for the evening reminder, refreshed with the summary.
    @State private var hasActivityToday = false
    @State private var isQuietToday = false
    /// Why the quiet-day card is hidden right now, or `nil` if it shows.
    @State private var promptHiddenReason: String?
    @State private var progressRowCount = 0
    @AppStorage(MascotMoodScenario.storageKey) private var moodScenario = ""

    /// Fired once the store has been rewritten. Lets a presenter that outlives
    /// the change clean up after itself — onboarding uses it to throw away a
    /// half-filled wizard whose drafts point at categories that no longer exist.
    var onDataChanged: (() -> Void)?

    private let monthOptions: [Int?] = [nil, 3, 6, 12, 24, 36, 60]

    var body: some View {
        NavigationStack {
            Form {
                storeSection
                lengthSection
                scenariosSection
                paymentsSection
                eveningReminderSection
                moodSection
                resetSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .font(Theme.Typography.body)
            .navigationTitle(Text("כלי פיתוח"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סגירה") { dismiss() }
                }
            }
        }
        .tint(Theme.Colors.accent)
        .onAppear { refresh() }
        .confirmationDialog(
            Text("להחליף את כל הנתונים?"),
            isPresented: deployDialogBinding,
            titleVisibility: .visible,
            presenting: scenarioPendingDeploy
        ) { scenario in
            Button("טעינת \(scenario.title)", role: .destructive) {
                deploy(scenario)
            }
            Button("ביטול", role: .cancel) {}
        } message: { scenario in
            Text("כל מה שקיים עכשיו יימחק ובמקומו ייטען \(scenario.title) על פני \(months(for: scenario)) חודשים.")
        }
        .confirmationDialog(
            Text("למחוק הכול ולהתחיל מאפס?"),
            isPresented: $isConfirmingWipe,
            titleVisibility: .visible
        ) {
            Button("מחיקת הכול", role: .destructive) { wipe() }
            Button("ביטול", role: .cancel) {}
        } message: {
            Text("הפרופיל, החשבונות, התנועות, התקציב, היעדים והניקוד יימחקו — גם מ-iCloud של גרסת הפיתוח, כשהיא מסונכרנת. הקטגוריות ייטענו מחדש והאפליקציה תחזור למסך ההתחלה.")
        }
    }

    // MARK: - Sections

    /// What's in the store right now — the "are you sure you want to overwrite
    /// this?" context, in numbers.
    private var storeSection: some View {
        Section {
            if summary.isEmpty {
                Text("הסטור ריק — האפליקציה תפתח את אשף ההקמה.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                LabeledContent("פרופיל") { Text(summary.hasProfile ? "קיים" : "אין") }
                countRow("חשבונות", summary.accounts)
                countRow("מתוכם פיקדונות", summary.deposits)
                if summary.depositTranches > 0 {
                    countRow("תת-הפקדות", summary.depositTranches)
                }
                countRow("תנועות", summary.transactions)
                countRow("שורות תקציב", summary.budgetItems)
                countRow("יעדים", summary.goals)
            }
        } header: {
            Text("מה יש עכשיו")
        }
    }

    /// How far back the generated ledger should go. Longer is slower to write
    /// and slower to render, so it's a choice rather than a fixed maximum.
    private var lengthSection: some View {
        Section {
            Picker("אורך ההיסטוריה", selection: $monthsOverride) {
                ForEach(monthOptions, id: \.self) { option in
                    Text(label(for: option)).tag(option)
                }
            }
        } header: {
            Text("אורך ההיסטוריה")
        } footer: {
            Text("כמה חודשים אחורה ייווצרו תנועות. ברירת המחדל משתנה לפי התרחיש — 12 חודשים לתרחיש פשוט, 36 לחוסך עם פיקדונות.")
        }
    }

    private var scenariosSection: some View {
        Section {
            ForEach(DemoScenario.allCases) { scenario in
                Button {
                    scenarioPendingDeploy = scenario
                } label: {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(scenario.title)
                                .font(Theme.Typography.sectionTitle)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer(minLength: Theme.Spacing.sm)
                            Text("\(months(for: scenario)) ח׳")
                                .font(Theme.Typography.captionSmall)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .monospacedDigit()
                        }
                        Text(scenario.summary)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("תרחישים")
        } footer: {
            Text("טעינה מוחקת את מה שקיים וכותבת מחדש: פרופיל, חשבונות, תקציב, יעדים, תנועות, שערי חליפין ונקודות. כל תרחיש נוצר עם אותו זרע אקראי, כך שטעינה חוזרת נותנת בדיוק את אותם נתונים.")
        }
    }

    private var paymentsSection: some View {
        Section {
            Button(action: queuePayments) {
                Label("5 תשלומים ממתינים", systemImage: "creditcard")
            }
        } header: {
            Text("Apple Pay")
        } footer: {
            Text("כאילו שולם חמש פעמים בארנק: שלושה בבתי עסק מוכרים (ירשמו ב״רישום כולם״), אחד בחנות לא מוכרת בלי קטגוריה ואחד בלי סכום. דורש נתונים — טענו תרחיש קודם.")
        }
    }

    private var eveningReminderSection: some View {
        Section {
            LabeledContent("פעילות היום") {
                Text(hasActivityToday ? "יש" : "אין")
            }
            LabeledContent("יום שקט") {
                Text(isQuietToday ? "מסומן" : "לא מסומן")
            }
            LabeledContent("הכרטיס") {
                Text(promptHiddenReason.map { "מוסתר: \($0)" } ?? "מוצג")
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("‎-demoQuietPrompt") {
                Text(QuietDayPrompt.ignoresEvening ? "פעיל" : "כבוי")
            }
            LabeledContent("שורות התקדמות") {
                Text(progressRowCount.formatted())
            }
            Button(action: clearTodaysActivity) {
                Label("יום בלי פעילות", systemImage: "moon.zzz")
            }
        } header: {
            Text("תזכורת ערב")
        } footer: {
            Text("מזיז את הפעילות האחרונה ליום העבודה הקודם ומוריד את סימון היום השקט, כך שהיום נראה כאילו לא נרשם בו כלום — הרצף נשמר. כל טעינת תרחיש רושמת פעילות להיום. עם ‎-demoQuietPrompt הכרטיס מופיע גם לפני 19:00.")
        }
    }

    private var moodSection: some View {
        Section {
            Picker(selection: $moodScenario) {
                Text("לפי הנתונים").tag("")
                ForEach(MascotMoodScenario.allCases) { scenario in
                    Text(verbatim: scenario.title).tag(scenario.rawValue)
                }
            } label: {
                Label("מצב רוח", systemImage: "face.smiling")
            }
            .pickerStyle(.inline)
        } header: {
            Text("העכבר")
        } footer: {
            Text("כופה מצב רוח על העכבר בדשבורד ובפרופיל, עם המשפט שלו בבועה. \"לפי הנתונים\" מחזיר את הכללים האמיתיים. נשמר עד שמשנים אותו.")
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingWipe = true
            } label: {
                Label("מחיקת כל הנתונים", systemImage: "trash")
            }
        } header: {
            Text("להתחיל מאפס")
        } footer: {
            Text("המסך הזה קיים רק בגרסאות פיתוח (DEBUG) ואינו נכלל בגרסה שמותקנת מהחנות.")
        }
    }

    private func countRow(_ title: LocalizedStringKey, _ value: Int) -> some View {
        LabeledContent(title) {
            Text(value.formatted())
                .monospacedDigit()
        }
    }

    // MARK: - Actions

    /// Both actions follow the same shape: **close the sheet, then rewrite the
    /// store.** The panel is presented from the very screen the wipe is about to
    /// pull apart, so it has to be out of the way first — and the work continues
    /// regardless, because an unstructured `Task` isn't tied to the view's
    /// lifetime the way `.task` would be.
    private func deploy(_ scenario: DemoScenario) {
        let months = monthsOverride
        let context = modelContext
        let notify = onDataChanged
        dismiss()
        Task { @MainActor in
            await DemoDataService.prepareForDestructiveWork(in: context)
            DemoDataService.deploy(scenario, monthsOverride: months, in: context)
            notify?()
        }
    }

    /// Closes the panel first: the payments' sheet can only come up once
    /// nothing is presented over the dashboard.
    private func queuePayments() {
        dismiss()
        DemoDataService.queueSamplePayments()
    }

    private func wipe() {
        let context = modelContext
        let notify = onDataChanged
        dismiss()
        Task { @MainActor in
            await DemoDataService.prepareForDestructiveWork(in: context)
            DemoDataService.wipe(in: context)
            notify?()
        }
    }

    private func clearTodaysActivity() {
        DemoDataService.clearTodaysActivity(in: modelContext)
        refresh()
    }

    private func refresh() {
        summary = DemoDataService.summary(in: modelContext)
        // Read, never create: `ProgressService.progress(in:)` would insert a
        // row into an empty store when the panel opens from onboarding.
        let rows = (try? modelContext.fetch(
            FetchDescriptor<UserProgress>(sortBy: [SortDescriptor(\.createdAt)])
        )) ?? []
        let progress = rows.first
        progressRowCount = rows.count
        promptHiddenReason = QuietDayPrompt.hiddenReason(progress: progress, now: .now)
        hasActivityToday = progress.map { ProgressService.hasActivity(on: .now, progress: $0) } ?? false
        isQuietToday = progress.map { ProgressService.isQuietDay(.now, progress: $0) } ?? false
    }

    // MARK: - Derived

    /// `.confirmationDialog(presenting:)` wants a `Binding<Bool>`; bridge it
    /// through the optional scenario so dismissing clears it in one place —
    /// same shape as the deposit prompts on the dashboard.
    private var deployDialogBinding: Binding<Bool> {
        Binding(
            get: { scenarioPendingDeploy != nil },
            set: { if !$0 { scenarioPendingDeploy = nil } }
        )
    }

    private func months(for scenario: DemoScenario) -> Int {
        monthsOverride ?? scenario.defaultMonths
    }

    private func label(for option: Int?) -> String {
        guard let option else { return "לפי התרחיש" }
        return "\(option) חודשים"
    }
}

// MARK: - Entry point

/// The little hammer that opens the panel. Lives in the dashboard header and on
/// the onboarding screen; both are DEBUG-only call sites.
///
/// `-hideAdmin` on the launch line hides it, so a DEBUG build can be recorded
/// for a teaser without a dev tool in the header. Checked here rather than at
/// each call site so both hammers obey it.
struct AdminPanelButton: View {
    /// Passed through to the panel — see `AdminPanelView.onDataChanged`.
    var onDataChanged: (() -> Void)?

    @State private var isPresented = false

    /// Launch arguments can't change while the app runs, so read them once.
    private static let isHidden = LaunchArguments.contains("-hideAdmin")

    var body: some View {
        if !Self.isHidden {
            button
        }
    }

    private var button: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "hammer.circle")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(Theme.Spacing.sm)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("כלי פיתוח"))
        .sheet(isPresented: $isPresented) {
            AdminPanelView(onDataChanged: onDataChanged)
        }
    }
}

#Preview {
    AdminPanelView()
        .modelContainer(for: OshRatSchema.models, inMemory: true)
}

#endif
