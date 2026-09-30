import Foundation
import Observation

/// Carries the widget's "new transaction" link from `ContentView`, which
/// receives every URL, to `HomeView`, which opens the sheet.
///
/// The URL can arrive while `HomeView` doesn't exist yet — behind the login
/// screen on a cold launch — so it's parked here rather than handled where it
/// lands, the same way `IncomingPaymentRouter` parks a card payment.
@MainActor
@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    /// A new-transaction link is waiting for `HomeView` to open the sheet.
    var isNewTransactionPending = false

    private init() {}
}
