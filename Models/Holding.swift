import Foundation
import SwiftData

/// A single position inside an investment account: a stock, ETF, bond or
/// any other asset the user is tracking. Like `Account.balance`, both
/// `quantity` and `marketValue` are entered manually by the user — we do
/// NOT derive market value from quantity × current price, because there
/// is no live price feed in the MVP.
///
/// Why store *both* `quantity` and `marketValue` (and not just one)?
///   * `quantity` is what the user actually owns; it only changes when
///     they buy or sell. Useful for future buy/sell tracking.
///   * `marketValue` is the current valuation; it changes daily with
///     the market. This is what the dashboard sums.
/// Letting the user keep both in sync gives the right answer for the
/// dashboard *and* leaves room to add a buy/sell log later without a
/// data migration.
///
/// Like every model in the app, every property has a default — so we
/// stay CloudKit-friendly for when iCloud sync is enabled later.
@Model
final class Holding {
    /// Ticker symbol the user typed in, e.g. "TEVA", "VOO", "TA35.TA".
    /// Free-text — we don't validate against any exchange.
    var symbol: String = ""

    /// Human-readable name, e.g. "טבע" or "Vanguard S&P 500".
    var name: String = ""

    /// Units held (shares, ETF units). May be zero for users who only
    /// track aggregate market value and not a unit count.
    var quantity: Decimal = 0

    /// Current total market value as entered by the user. This is the
    /// source of truth for the dashboard — not derived from quantity.
    var marketValue: Decimal = 0

    /// ISO currency code. Usually matches the parent account, but kept
    /// here too so the holding makes sense on its own.
    var currencyCode: String = "ILS"

    /// When the user last touched this holding's numbers — lets the
    /// dashboard flag stale valuations later.
    var lastUpdated: Date = Date.now

    /// Back-link to the owning account. The inverse is declared on
    /// `Account.holdings` so SwiftData keeps both sides in sync.
    var account: Account?

    init(
        symbol: String = "",
        name: String = "",
        quantity: Decimal = 0,
        marketValue: Decimal = 0,
        currencyCode: String = "ILS",
        lastUpdated: Date = .now
    ) {
        self.symbol = symbol
        self.name = name
        self.quantity = quantity
        self.marketValue = marketValue
        self.currencyCode = currencyCode
        self.lastUpdated = lastUpdated
    }
}
