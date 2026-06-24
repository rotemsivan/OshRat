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
/// `profiles` becomes non-empty, and we swap in the dashboard instead.
/// No persistent "did the user onboard?" flag needed — the data itself
/// is the source of truth.
struct ContentView: View {
    @Query private var profiles: [UserProfile]

    var body: some View {
        Group {
            if profiles.isEmpty {
                OnboardingFlowView()
            } else {
                HomeView()
            }
        }
        // Install the global "tap outside a text input to dismiss the
        // keyboard" gesture once the window is live. `OshRatApp.init`
        // runs before any window exists, so we defer this to the first
        // time the root view appears.
        .onAppear { KeyboardDismissTapInstaller.shared.install() }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [UserProfile.self, Account.self, Holding.self, Category.self, Transaction.self, TransactionAttachment.self, BudgetItem.self, Goal.self, FXRateSnapshot.self], inMemory: true)
}
