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
                    DepositTranche.self
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
    /// ```
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

        guard let flagIndex = arguments.firstIndex(of: "-demoScenario"),
              arguments.index(after: flagIndex) < arguments.endIndex,
              let scenario = DemoScenario(rawValue: arguments[arguments.index(after: flagIndex)])
        else { return }

        var months: Int?
        if let monthsIndex = arguments.firstIndex(of: "-demoMonths"),
           arguments.index(after: monthsIndex) < arguments.endIndex {
            months = Int(arguments[arguments.index(after: monthsIndex)])
        }

        DemoDataService.deploy(scenario, monthsOverride: months, in: context)
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
