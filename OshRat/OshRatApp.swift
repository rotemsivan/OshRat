import SwiftUI
import SwiftData

@main
struct OshRatApp: App {
    /// The SwiftData container — this is our on-device database.
    /// Every @Model type the app uses must be listed here.
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: UserProfile.self, Account.self, Category.self,
                    Transaction.self, BudgetItem.self, Goal.self
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
                // Force right-to-left for this Hebrew-only app so RTL works
                // immediately. Later, when we add a Hebrew localization, the
                // system can mirror the layout automatically and this can go.
                .environment(\.layoutDirection, .rightToLeft)
        }
        .modelContainer(container)
    }
}
