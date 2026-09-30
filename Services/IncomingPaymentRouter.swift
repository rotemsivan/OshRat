import Foundation
import Observation

/// Carries a card payment from `LogPaymentIntent` to the screen that shows it.
///
/// The intent runs outside the view hierarchy — often on a cold launch, before
/// any view exists — so it can't present a sheet itself. It parks the payment
/// here instead, and `HomeView` picks it up as soon as it's on screen (and
/// removes it, so it's shown once). A payment that waited longer than
/// `PaymentPrefill.freshness` is dropped at that point: `HomeView` doesn't
/// exist until onboarding is finished, and a sheet for a coffee bought before
/// that shouldn't appear out of nowhere afterwards.
@MainActor
@Observable
final class IncomingPaymentRouter {
    static let shared = IncomingPaymentRouter()

    /// Payments waiting to be shown, oldest first. A queue, not one slot: a
    /// second tap while the first payment waits behind a sheet (a split
    /// bill, a second purchase) used to overwrite it, and that purchase went
    /// unlogged without a word.
    private var queue: [PaymentPrefill] = []

    /// The payment `HomeView` will show next, if any.
    var pending: PaymentPrefill? { queue.first }

    private init() {}

    func receive(_ payment: PaymentPrefill) {
        queue.append(payment)
    }

    /// Hands over the oldest payment that's still fresh and removes it,
    /// dropping any stale ones in front of it.
    func take(now: Date = .now) -> PaymentPrefill? {
        while !queue.isEmpty {
            let payment = queue.removeFirst()
            if payment.isFresh(at: now) { return payment }
        }
        return nil
    }
}
