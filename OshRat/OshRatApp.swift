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
                    Goal.self, FXRateSnapshot.self
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
        } catch {
            fatalError("Could not create the SwiftData container: \(error)")
        }
    }

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
