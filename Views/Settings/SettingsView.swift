import SwiftUI
import SwiftData

/// "הגדרות" — pushed from the gear on the profile tab.
///
/// Everything the app used to hard-code or scatter across toolbars, in one
/// place: the personal details from onboarding (now editable), the budget's
/// business-day rule, the Apple Pay shortcut, sounds, exchange rates, iCloud
/// sync's status, and the management screens (categories, Recently Deleted).
///
/// A system `Form` on purpose: settings are the one screen where people
/// expect iOS's own look, and it brings grouped rows, switches and pickers
/// that read correctly under RTL and every text size for free.
struct SettingsView: View {
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    var body: some View {
        Group {
            // There's always a profile here — the profile tab only exists
            // after onboarding created one.
            if let profile = profiles.first {
                SettingsForm(profile: profile)
            }
        }
        .navigationTitle(Text("הגדרות"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The form proper, split out so the profile can be `@Bindable` and the
/// fields bind straight to it — SwiftData saves the edits as they're made.
private struct SettingsForm: View {
    @Bindable var profile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FXRateSnapshot.fetchedAt, order: .reverse) private var fxSnapshots: [FXRateSnapshot]

    @AppStorage(CelebrationFeedback.isEnabledKey) private var soundsEnabled = true
    @AppStorage(DailyReminderService.isEnabledKey) private var eveningReminderEnabled = true
    /// Notification permission, so a reminder that can't be delivered says so.
    @State private var notificationPermission: PaymentNotifier.Permission?

    @State private var isShowingRecentlyDeleted = false
    @State private var fxRefresh: FXRefreshState = .idle
    /// Whether the device is signed into iCloud — `nil` while it's asked.
    @State private var cloudStatus: CloudAccountService.Status?
    /// The name as the screen opened with it — put back if the user leaves
    /// with the field emptied, since a blank name breaks the greeting and the
    /// profile header.
    @State private var nameOnOpen = ""

    /// Kept in step with the account editor's list.
    private static let currencies: [(code: String, label: LocalizedStringKey)] = [
        ("ILS", "₪ שקל"), ("USD", "$ דולר"), ("EUR", "€ אירו")
    ]

    var body: some View {
        Form {
            personalSection
            budgetSection
            reminderSection
            applePaySection
            feedbackSection
            ratesSection
            syncSection
            managementSection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        // The app's accent on icons, links and switches, as everywhere else.
        .tint(Theme.Colors.accent)
        // Rows are interactive nearly to the end, so clear the floating "+".
        .contentMargins(.bottom, HomeBottomBar.floatingButtonClearance, for: .scrollContent)
        .sheet(isPresented: $isShowingRecentlyDeleted) {
            RecentlyDeletedView()
        }
        .onAppear { nameOnOpen = profile.name }
        .task { cloudStatus = await CloudAccountService.status() }
        .task { notificationPermission = await PaymentNotifier.permission() }
        .onDisappear {
            if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                profile.name = nameOnOpen
            }
        }
    }

    // MARK: - Sections

    private var personalSection: some View {
        Section {
            // Label on top, value underneath — a filled field's placeholder is
            // gone, and "רותם" alone doesn't say it's the name.
            labeledField("שם") {
                TextField("שם", text: $profile.name)
                    .textContentType(.givenName)
            }
            labeledField("מקצוע") {
                TextField("לא חובה", text: $profile.profession)
            }
            labeledField("המטרה שלי") {
                TextField("לא חובה", text: $profile.goalsText, axis: .vertical)
                    .lineLimit(1...5)
            }
            Picker(selection: $profile.preferredCurrencyCode) {
                ForEach(Self.currencies, id: \.code) { currency in
                    Text(currency.label).tag(currency.code)
                }
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Text("מטבע מועדף")
                    InfoButton("הדשבורד מסכם את כל החשבונות במטבע המועדף, לפי שערי החליפין.")
                }
            }
        } header: {
            Text("פרטים אישיים")
        }
    }

    /// A small grey caption with its field under it.
    private func labeledField<Field: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder field: () -> Field
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            field()
        }
    }

    private var budgetSection: some View {
        Section {
            Toggle(isOn: $profile.shiftsIncomeToBusinessDay) {
                // The i inside the label's title, not beside the whole Label,
                // so the row keeps the icon's usual gap.
                Label {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("הכנסות ביום עסקים")
                        InfoButton("הכנסה קבועה שחלה בשבת או בחג תוצג ביום העסקים הבא, כמו משכורת שנכנסת לבנק. הוצאות נשארות בתאריך שלהן.")
                    }
                } icon: {
                    Image(systemName: "calendar.badge.clock")
                }
            }
        } header: {
            Text("תקציב")
        }
    }

    /// The evening reminder's switch. Turning it off takes the pending
    /// reminders down (`HomeView` reschedules on the stored value); turning it
    /// on asks for permission if it never was.
    private var reminderSection: some View {
        Section {
            Toggle(isOn: $eveningReminderEnabled) {
                Label {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("תזכורת ערב")
                        InfoButton("ב-19:00 בימים א׳–ה׳, אם עוד לא נרשמה תנועה באותו יום. לא בשבת, בחג ובערב חג. ביום בלי תנועות אפשר לסמן יום שקט ולשמור על הרצף, עד פעמיים בשבוע.")
                    }
                } icon: {
                    Image(systemName: "bell")
                }
            }
            .onChange(of: eveningReminderEnabled) { _, isOn in
                guard isOn else { return }
                Task {
                    if await PaymentNotifier.permission() == .notAsked {
                        notificationPermission = await PaymentNotifier.requestPermission()
                    }
                    await DailyReminderService.reschedule(in: modelContext)
                }
            }
            if eveningReminderEnabled, notificationPermission == .denied,
               let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                Link(destination: url) {
                    Label("ההתראות כבויות — פתיחת הגדרות", systemImage: "bell.slash")
                }
            }
        }
    }

    /// The whole shortcut in one place: what it does (behind the i), the
    /// step-by-step guide, and a way into Shortcuts.
    private var applePaySection: some View {
        Section {
            NavigationLink {
                ApplePaySetupView()
            } label: {
                // The live check's verdict, so a broken automation shows here
                // without the user going looking for it.
                LabeledContent {
                    applePayStatus
                } label: {
                    Label("הוראות הגדרה", systemImage: "list.number")
                }
            }
            Link(destination: URL(string: "shortcuts://")!) {
                Label("פתיחת קיצורים", systemImage: "arrow.up.forward.app")
            }
        } header: {
            HStack(spacing: Theme.Spacing.xs) {
                Text("רישום מ-Apple Pay")
                InfoButton("אחרי תשלום בארנק, עכבר עו״ש נפתח עם תנועה שכבר מולאו בה הסכום ובית העסק. דורש הגדרה חד־פעמית באפליקציית קיצורים.")
            }
        }
    }

    /// "פועל" / "דורש תיקון" from the last payment the automation delivered;
    /// nothing until one has.
    @ViewBuilder
    private var applePayStatus: some View {
        switch IncomingPaymentRouter.shared.lastReceived?.setupVerdict {
        // Colour on the icon only: green and orange text would fall below
        // 4.5:1 on the row's background.
        case .working:
            Label {
                Text("פועל")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Colors.income)
            }
        case .missing, .empty:
            Label {
                Text("דורש תיקון")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.Colors.wants)
            }
        case nil:
            EmptyView()
        }
    }

    private var feedbackSection: some View {
        Section {
            Toggle(isOn: $soundsEnabled) {
                Label {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text("צלילים ורטט")
                        InfoButton("צליל ורטט קצרים ברישום תנועה, בצבירת נקודות ובהישגים. מתג ההשתקה של הטלפון משתיק את הצליל בכל מקרה.")
                    }
                } icon: {
                    Image(systemName: "speaker.wave.2")
                }
            }
        }
    }

    private var ratesSection: some View {
        Section {
            LabeledContent("עדכון אחרון") {
                if let fetchedAt = fxSnapshots.first?.fetchedAt {
                    Text(fetchedAt, format: .relative(presentation: .named))
                } else {
                    Text("עדיין לא עודכן")
                }
            }
            Button {
                Task { await refreshRates() }
            } label: {
                HStack {
                    Label("רענון עכשיו", systemImage: "arrow.clockwise")
                    Spacer()
                    if fxRefresh == .running {
                        ProgressView()
                    }
                }
            }
            .disabled(fxRefresh == .running)
            if fxRefresh == .failed {
                Text("לא הצלחנו לעדכן — בדקו את החיבור לאינטרנט.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.expense)
            }
        } header: {
            HStack(spacing: Theme.Spacing.xs) {
                Text("שערי חליפין")
                InfoButton("השערים היציגים של הבנק המרכזי האירופי, מתעדכנים פעם ביום, בלי שום פרט אישי. מלבד הסנכרון עם ה-iCloud שלך, זו הפנייה היחידה של האפליקציה לאינטרנט.")
            }
        }
    }

    /// Sync is always on when the device is signed into iCloud; this only
    /// says whether it is, and never blocks anything — signed out, the app
    /// works the same, on the device alone.
    private var syncSection: some View {
        Section {
            Label {
                Text(syncStatusText)
            } icon: {
                Image(systemName: cloudStatus == .available ? "checkmark.icloud" : "icloud.slash")
            }
        } header: {
            HStack(spacing: Theme.Spacing.xs) {
                Text("iCloud")
                InfoButton("החשבונות, התנועות, התקציב וההתקדמות נשמרים גם ב-iCloud הפרטי שלך ומסתנכרנים בין המכשירים עם אותו Apple ID. רק לך יש אליהם גישה. תשלומים שממתינים לרישום והעדפות כמו צלילים נשארים במכשיר.")
            }
        }
    }

    private var syncStatusText: LocalizedStringKey {
        switch cloudStatus {
        case .available:   "מסונכרן עם iCloud"
        case .unavailable: "לא מחובר ל-iCloud — הנתונים נשמרים רק במכשיר"
        case .unknown:     "לא ניתן לבדוק את iCloud כרגע"
        case nil:          "בודק…"
        }
    }

    private var managementSection: some View {
        Section {
            NavigationLink {
                CategoriesView()
            } label: {
                Label("הקטגוריות שלי", systemImage: "tag")
            }
            Button {
                isShowingRecentlyDeleted = true
            } label: {
                Label("נמחקו לאחרונה", systemImage: "trash")
            }
            NavigationLink {
                ExportView()
            } label: {
                Label("ייצוא נתונים", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("ניהול")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("גרסה", value: Self.versionText)
        } header: {
            Text("אודות")
        }
    }

    // MARK: - Behaviour

    private func refreshRates() async {
        fxRefresh = .running
        let succeeded = await FXRatesService.refreshNow(in: modelContext)
        fxRefresh = succeeded ? .idle : .failed
    }

    /// "1.0 (3)": the marketing version and the build number.
    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }
}

private enum FXRefreshState {
    case idle, running, failed
}

/// A small "i" that opens its explanation in a bubble beside it — so the
/// settings read as a short list, with the why one tap away rather than
/// under every row.
///
/// Borderless so that inside a `Form` row it takes only its own taps (a
/// plain button would claim the whole row), and each owns its popover flag
/// so the bubble anchors to the icon that was tapped.
struct InfoButton: View {
    let text: LocalizedStringKey
    @State private var isShowing = false

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Button {
            isShowing = true
        } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundStyle(Theme.Colors.accent)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("מידע נוסף"))
        .popover(isPresented: $isShowing) {
            Text(text)
                .font(Theme.Typography.bodySmall)
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260, alignment: .leading)
                .padding(Theme.Spacing.md)
                // A bubble on iPhone too, not a sheet — it's two sentences.
                .presentationCompactAdaptation(.popover)
                .environment(\.layoutDirection, .rightToLeft)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: OshRatSchema.models, inMemory: true)
    .environment(\.layoutDirection, .rightToLeft)
}
