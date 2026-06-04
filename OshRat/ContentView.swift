//
//  ContentView.swift
//  OshRat
//
//  Created by Rotem Sivan on 04/06/2026.
//

import SwiftUI
import SwiftData

/// Top-level router for the app.
///
/// On the very first launch there is no `UserProfile` in SwiftData, so we
/// show the onboarding flow (welcome screen → setup wizard). Once the
/// wizard finishes and commits a profile, the `@Query` here re-runs,
/// `profiles` becomes non-empty, and we swap in the main app instead.
/// No persistent "did the user onboard?" flag needed — the data itself
/// is the source of truth.
struct ContentView: View {
    @Query private var profiles: [UserProfile]

    var body: some View {
        if profiles.isEmpty {
            OnboardingFlowView()
        } else {
            // Placeholder until the real dashboard is built. Greets the
            // user by name so it's obvious onboarding succeeded.
            HomePlaceholderView(profile: profiles[0])
        }
    }
}

/// Stand-in for the future dashboard. Replaced in the next milestone.
private struct HomePlaceholderView: View {
    let profile: UserProfile

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)

                Text("שלום, \(profile.name)!")
                    .font(.title.bold())

                Text("ההגדרות הראשוניות הושלמו. מסך הבית והדשבורד יבנו בשלב הבא.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
            .navigationTitle(Text("עכבר עו״ש"))
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [UserProfile.self, Account.self, Category.self, Transaction.self, BudgetItem.self, Goal.self], inMemory: true)
        .environment(\.layoutDirection, .rightToLeft)
}
