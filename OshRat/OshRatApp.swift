import SwiftUI
import SwiftData

@main
struct OshRatApp: App {
    /// The SwiftData container — this is our on-device database.
    /// Every @Model type the app uses must be listed here.
    let container: ModelContainer

    init() {
        // Push our Heebo font into the UIKit-backed UI chrome (nav bars,
        // tab bars, text fields, etc.). Must run before any of those views
        // are constructed, so we do it here in `init` rather than in `body`.
        Theme.applyGlobalAppearance()

        do {
            container = try ModelContainer(
                for: UserProfile.self, Account.self, Holding.self, Category.self,
                    Transaction.self, TransactionAttachment.self, BudgetItem.self,
                    Goal.self, FXRateSnapshot.self, UserProgress.self,
                    DepositTranche.self, MascotConfig.self
            )
            // Clean up any duplicate category rows left over from earlier
            // dev resets BEFORE topping up the default set — otherwise
            // the idempotent seed would see "name already present" and
            // skip while a duplicate still lurked in the database.
            SeedData.dedupeCategoriesIfNeeded(in: container.mainContext)
            // Now safe to top up. Idempotent — adds only categories the
            // store doesn't already have, so it runs every launch
            // without growing the table.
            SeedData.seedDefaultCategoriesIfNeeded(in: container.mainContext)
            #if DEBUG
            Self.applyDemoLaunchArguments(in: container.mainContext)
            #endif
        } catch {
            fatalError("Could not create the SwiftData container: \(error)")
        }
    }

    #if DEBUG
    /// Command-line hooks for the demo data, so a scenario can be deployed
    /// without tapping through the admin panel:
    ///
    /// ```
    /// xcrun simctl launch booted com.rotem.OshRat -demoScenario saver -demoMonths 24
    /// xcrun simctl launch booted com.rotem.OshRat -resetStore
    /// xcrun simctl launch booted com.rotem.OshRat -demoEquip item-hat-propeller-red
    /// ```
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
    }
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                // App-wide default font. Any `Text(...)` that doesn't set
                // an explicit `.font(...)` will inherit Heebo from here.
                .font(Theme.Typography.body)
        }
        .modelContainer(container)
    }
}
