import SwiftUI
import SwiftData
import UserNotifications

@main
struct OshRatApp: App {
    init() {
        // Push our Heebo font into the UIKit-backed UI chrome (nav bars,
        // text fields, etc.). Must run before any of those views
        // are constructed, so we do it here in `init` rather than in `body`.
        Theme.applyGlobalAppearance()

        // Set before the app finishes launching, so a tap on a payment
        // notification that launched the app is delivered to it.
        UNUserNotificationCenter.current().delegate = PaymentNotifier.shared
        DailyReminderService.registerCategories()
        // Deliberately no store here: a background launch for the Apple Pay
        // action has no window and must stay light — see
        // `PersistentStore.shared`.
    }

    /// The on-device database, opened when the first window is built (the
    /// `WindowGroup`'s content isn't evaluated in a windowless background
    /// launch). It either opened (`.ready`) or the app shows
    /// `StoreRecoveryView` instead of crashing — see `PersistentStore`.
    private static let store: PersistentStore = {
        let store = PersistentStore.shared
        #if DEBUG
        if case .ready(let container) = store.state {
            applyDemoLaunchArguments(in: container.mainContext)
        }
        #endif
        return store
    }()

    #if DEBUG
    /// Command-line hooks for the demo data, so a scenario can be deployed
    /// without tapping through the admin panel:
    ///
    /// ```
    /// xcrun simctl launch booted com.oshrat.app.dev -demoScenario saver -demoMonths 24
    /// xcrun simctl launch booted com.oshrat.app.dev -resetStore
    /// xcrun simctl launch booted com.oshrat.app.dev -demoEquip item-hat-propeller-red
    /// xcrun simctl launch booted com.oshrat.app.dev -demoScenario saver -demoLevel 25
    /// xcrun simctl launch booted com.oshrat.app.dev -hideAdmin
    /// xcrun simctl launch booted com.oshrat.app.dev -demoPayment "42.90,ILS,SHUFERSAL DEAL,Visa 1234"
    /// xcrun simctl launch booted com.oshrat.app.dev -demoPendingPayments
    /// ```
    ///
    /// `-demoPayment` stands in for the Wallet automation calling
    /// `LogPaymentIntent`: amount, currency, merchant, card, comma-separated,
    /// any of them empty (`",,Cafe Nero,"` is a payment with no amount).
    ///
    /// (`-hideAdmin` is read by `AdminPanelButton` itself, not here.)
    ///
    /// `-demoEquip` runs after any deploy (which starts the rat bare), so the
    /// two combine. The item still has to be unlocked at the store's level to
    /// show — `UserAvatar` hides anything the level hasn't reached.
    ///
    /// Runs as the store opens, before the first window's content is built,
    /// so the first frame already shows the seeded store rather than
    /// flashing the old one. Useful for
    /// screenshots and for `simctl`-driven checks, where no gesture can be
    /// driven (see the simulator note in CLAUDE.md).
    private static func applyDemoLaunchArguments(in context: ModelContext) {
        if LaunchArguments.contains("-resetStore") {
            DemoDataService.wipe(in: context)
        }

        if let scenario = LaunchArguments.value(after: "-demoScenario").flatMap(DemoScenario.init(rawValue:)) {
            let months = LaunchArguments.value(after: "-demoMonths").flatMap { Int($0) }
            DemoDataService.deploy(scenario, monthsOverride: months, in: context)
        }

        // After the deploy, which writes the scenario's own XP: lifts the store
        // to a level, e.g. `-demoLevel 25` to unlock the whole wardrobe. Sets
        // the total straight onto the row, as the deploy does, and drops any
        // queued toasts so the jump doesn't announce itself. Achievements are
        // evaluated first: otherwise the dashboard's own pass pays their XP on
        // top and the store lands a level or two higher, with a toast.
        if let level = LaunchArguments.value(after: "-demoLevel").flatMap({ Int($0) }) {
            ProgressService.evaluateAchievements(in: context)
            let progress = ProgressService.progress(in: context)
            progress.totalXP = XPRules.totalXP(toReach: min(max(level, 1), XPRules.maxLevel))
            progress.pendingLevelUpLevel = nil
            progress.pendingCelebrations = []
            try? context.save()
        }

        // Renames the profile, e.g. `-demoName עמית`, for screenshots with a
        // name other than the scenario's. Oldest profile first, as every
        // profile `@Query` reads it.
        if let name = LaunchArguments.value(after: "-demoName"), !name.isEmpty {
            let descriptor = FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)])
            if let profile = try? context.fetch(descriptor).first {
                profile.name = name
                try? context.save()
            }
        }

        // Comma-separated, so a whole look can be put on at once:
        // `-demoEquip item-hat-cowboy-brown,item-outfit-denim-blue`.
        if let ids = LaunchArguments.value(after: "-demoEquip")?.split(separator: ",") {
            let config = WardrobeService.config(in: context)
            for item in ids.compactMap({ WardrobeItem.withID(String($0)) }) {
                config.setEquippedID(item.id, for: item.slot)
            }
            try? context.save()
        }

        // After a deploy, which stamps today's activity: today looks untouched,
        // so the evening reminder and the quiet-day prompt can be tried.
        if LaunchArguments.contains("-demoInactiveToday") {
            DemoDataService.clearTodaysActivity(in: context)
        }

        if LaunchArguments.contains("-demoReminder") {
            Task { await DailyReminderService.postDemoReminder() }
        }

        if LaunchArguments.contains("-demoPendingPayments") {
            DemoDataService.queueSamplePayments()
        }

        if let payment = LaunchArguments.value(after: "-demoPayment") {
            let fields = payment
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            func field(_ index: Int) -> String? {
                fields.indices.contains(index) && !fields[index].isEmpty ? fields[index] : nil
            }
            // Through the same parser the real action uses.
            let parsed = PaymentPrefill.parseAmount(field(0))
            IncomingPaymentRouter.shared.receive(PaymentPrefill(
                amount: parsed?.amount,
                currencyCode: field(1) ?? parsed?.currencyCode,
                merchant: field(2),
                cardName: field(3),
                rawAmount: field(0)
            ))
        }
    }
    #endif

    var body: some Scene {
        WindowGroup {
            StoreGate(store: Self.store)
        }
    }
}

/// The app's root: the app itself once the store opened, the recovery screen
/// if it didn't. A view rather than a `switch` in the scene, so it re-renders
/// when `StoreRecoveryView`'s retry changes `store.state` (a view's `body`
/// tracks the `@Observable` reads).
private struct StoreGate: View {
    let store: PersistentStore

    var body: some View {
        switch store.state {
        case .ready(let container):
            ContentView()
                // App-wide default font. Any `Text(...)` that doesn't set
                // an explicit `.font(...)` will inherit Heebo from here.
                .font(Theme.Typography.body)
                .modelContainer(container)
        case .failed(let details):
            StoreRecoveryView(store: store, details: details)
                .font(Theme.Typography.body)
        }
    }
}
