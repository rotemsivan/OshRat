import Foundation
import Observation

/// Carries a card payment from `LogPaymentIntent` to the screen that shows it.
///
/// The intent runs outside the view hierarchy — often on a cold launch, before
/// any view exists — so it can't present a sheet itself. It parks the payment
/// here instead, and `HomeView` picks it up as soon as it's on screen (and
/// clears it, so it's shown once). A payment that waited longer than
/// `PaymentPrefill.freshness` is dropped at that point: `HomeView` doesn't
/// exist until onboarding is finished, and a sheet for a coffee bought before
/// that shouldn't appear out of nowhere afterwards.
@MainActor
@Observable
final class IncomingPaymentRouter {
    static let shared = IncomingPaymentRouter()

    private(set) var pending: PaymentPrefill?

    private init() {}

    func receive(_ payment: PaymentPrefill) {
        pending = payment
    }

    /// Hands over the waiting payment, if it's still fresh, and clears it.
    func take(now: Date = .now) -> PaymentPrefill? {
        defer { pending = nil }
        guard let pending, pending.isFresh(at: now) else { return nil }
        return pending
    }
}
