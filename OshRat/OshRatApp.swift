import SwiftUI
import SwiftData

@main
struct OshRatApp: App {
    /// The on-device database. It either opened (`.ready`) or the app shows
    /// `StoreRecoveryView` instead of crashing — see `PersistentStore`.
    @State private var store: PersistentStore

    init() {
        // Push our Heebo font into the UIKit-backed UI chrome (nav bars,
        // tab bars, text fields, etc.). Must run before any of those views
        // are constructed, so we do it here in `init` rather than in `body`.
        Theme.applyGlobalAppearance()

        let store = PersistentStore()
        #if DEBUG
        if case .ready(let container) = store.state {
            Self.applyDemoLaunchArguments(in: container.mainContext)
        }
        #endif
        _store = State(initialValue: store)
    }

    #if DEBUG
    /// Command-line hooks for the demo data, so a scenario can be deployed
    /// without tapping through the admin panel:
    ///
    /// ```
    /// xcrun simctl launch booted com.oshrat.app.dev -demoScenario saver -demoMonths 24
    /// xcrun simctl launch booted com.oshrat.app.dev -resetStore
    /// xcrun simctl launch booted com.oshrat.app.dev -demoEquip item-hat-propeller-red
    /// xcrun simctl launch booted com.oshrat.app.dev -hideAdmin
    /// xcrun simctl launch booted com.oshrat.app.dev -demoPayment "42.90,ILS,SHUFERSAL DEAL,Visa 1234"
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
    /// Runs here, before any window exists, so the first frame already shows
    /// the seeded store rather than flashing the old one. Useful for
    /// screenshots and for `simctl`-driven checks, where no gesture can be
    /// driven (see the simulator note in CLAUDE.md).
    private static func applyDemoLaunchArguments(in context: ModelContext) {
        let arguments = CommandLine.arguments

        if arguments.contains("-resetStore") {
            DemoDataService.wipe(in: context)
        }

        if let flagIndex = arguments.firstIndex(of: "-demoScenario"),
           arguments.index(after: flagIndex) < arguments.endIndex,
           let scenario = DemoScenario(rawValue: arguments[arguments.index(after: flagIndex)]) {
            var months: Int?
            if let monthsIndex = arguments.firstIndex(of: "-demoMonths"),
               arguments.index(after: monthsIndex) < arguments.endIndex {
                months = Int(arguments[arguments.index(after: monthsIndex)])
            }
            DemoDataService.deploy(scenario, monthsOverride: months, in: context)
        }

        // Comma-separated, so a whole look can be put on at once:
        // `-demoEquip item-hat-cowboy-brown,item-outfit-denim-blue`.
        if let flagIndex = arguments.firstIndex(of: "-demoEquip"),
           arguments.index(after: flagIndex) < arguments.endIndex {
            let ids = arguments[arguments.index(after: flagIndex)].split(separator: ",")
            let config = WardrobeService.config(in: context)
            for item in ids.compactMap({ WardrobeItem.withID(String($0)) }) {
                config.setEquippedID(item.id, for: item.slot)
            }
            try? context.save()
        }

        if let flagIndex = arguments.firstIndex(of: "-demoPayment"),
           arguments.index(after: flagIndex) < arguments.endIndex {
            let fields = arguments[arguments.index(after: flagIndex)]
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            func field(_ index: Int) -> String? {
                fields.indices.contains(index) && !fields[index].isEmpty ? fields[index] : nil
            }
            IncomingPaymentRouter.shared.receive(PaymentPrefill(
                amount: field(0).flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) },
                currencyCode: field(1),
                merchant: field(2),
                cardName: field(3)
            ))
        }
    }
    #endif

    var body: some Scene {
        WindowGroup {
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
}
