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
                    Transaction.self, BudgetItem.self, Goal.self, FXRateSnapshot.self
            )
            // Populate default Hebrew categories on the very first launch.
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
