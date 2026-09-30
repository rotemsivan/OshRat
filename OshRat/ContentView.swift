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
///
/// A returning user starts on `LoginView`, the brand screen, and enters the
/// dashboard from there. That's per launch (plain `@State`), not remembered.
/// The login is skipped when the app was opened to *do* something — the
/// widget's quick add, or an Apple Pay payment to log — since stopping at a
/// front door on the way would only get in the way.
struct ContentView: View {
    @Query private var profiles: [UserProfile]
    @Environment(\.scenePhase) private var scenePhase

    @State private var hasEntered = Self.skipsLoginAtLaunch

    private let paymentRouter = IncomingPaymentRouter.shared
    private let linkRouter = DeepLinkRouter.shared

    var body: some View {
        Group {
            if profiles.isEmpty {
                OnboardingFlowView()
            } else if hasEntered {
                HomeView()
                    .transition(.opacity)
            } else {
                LoginView(onEnter: enter)
                    .transition(.opacity)
            }
        }
        // The one place URLs arrive. The widget's link is parked in the router
        // for `HomeView` and goes straight past the login. Before onboarding
        // there's no account to log against, so it's ignored.
        .onOpenURL(perform: handleURL)
        // A card payment from the Wallet automation, likewise. `initial`
        // catches one that arrived on a cold launch, before this view existed.
        .onChange(of: paymentRouter.pending?.id, initial: true) { _, pendingID in
            enterForPayment(pendingID)
        }
        // Coming back from a payment notification: the payment was saved by
        // the action while the app sat in the background.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshPayments() }
        }
        // Finishing the wizard (or a DEBUG demo deploy from the onboarding
        // screen) lands on the dashboard — the user is already in.
        .onChange(of: profiles.isEmpty) { wasEmpty, isEmpty in
            enterAfterOnboarding(wasEmpty: wasEmpty, isEmpty: isEmpty)
        }
        // Install the global "tap outside a text input to dismiss the
        // keyboard" gesture once the window is live. `OshRatApp.init`
        // runs before any window exists, so we defer this to the first
        // time the root view appears.
        .onAppear { KeyboardDismissTapInstaller.shared.install() }
    }

    private func enter() {
        withAnimation(.easeInOut(duration: 0.4)) {
            hasEntered = true
        }
    }

    /// Picks up what the background action saved, and deletes (with their
    /// notifications) payments that waited past `PaymentPrefill.freshness`.
    private func refreshPayments() {
        paymentRouter.reload()
        paymentRouter.removeExpired().forEach(PaymentNotifier.clear)
    }

    private func handleURL(_ url: URL) {
        guard DeepLink.isNewTransaction(url), !profiles.isEmpty else { return }
        linkRouter.isNewTransactionPending = true
        hasEntered = true
    }

    private func enterForPayment(_ pendingID: UUID?) {
        guard pendingID != nil, !profiles.isEmpty else { return }
        hasEntered = true
    }

    private func enterAfterOnboarding(wasEmpty: Bool, isEmpty: Bool) {
        if wasEmpty && !isEmpty { hasEntered = true }
    }

    /// DEBUG: the screenshot hooks that open on a particular screen
    /// (`-demoTab`, `-demoWardrobe`) skip the login, as does `-skipLogin`.
    private static var skipsLoginAtLaunch: Bool {
        #if DEBUG
        ["-skipLogin", "-demoTab", "-demoWardrobe"].contains(where: LaunchArguments.contains)
        #else
        false
        #endif
    }
}

#Preview {
    ContentView()
        .modelContainer(for: OshRatSchema.models, inMemory: true)
}
