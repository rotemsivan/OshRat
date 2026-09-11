import Foundation

/// Converts monetary amounts between currencies using a cached
/// `FXRateSnapshot`.
///
/// All money math stays in `Decimal` — we only touch `Double` for the
/// source rate, which Frankfurter publishes with ~6 decimal places of
/// precision (well within `Double`'s reliable range, and the result
/// goes straight back into `Decimal` for any further math).
///
/// All methods return `nil` when conversion isn't possible (missing
/// rate, etc.), letting callers fall back to a sensible default.
enum CurrencyConverter {

    /// Converts `amount` from one currency to another. Returns nil
    /// when either side isn't in the snapshot's rate set (and isn't
    /// the snapshot's base currency).
    static func convert(
        _ amount: Decimal,
        from sourceCode: String,
        to targetCode: String,
        using snapshot: FXRateSnapshot
    ) -> Decimal? {
        if sourceCode == targetCode { return amount }
        guard let fromRate = rate(for: sourceCode, in: snapshot),
              let toRate = rate(for: targetCode, in: snapshot) else {
            return nil
        }
        // Cross-rate via the snapshot's base. Going through Double for
        // the ratio is fine here: FX rates have ~6 sig-figs of precision
        // and we round to the cent on display anyway.
        return amount * Decimal(toRate / fromRate)
    }

    // MARK: - Internals

    private static func rate(for code: String, in snapshot: FXRateSnapshot) -> Double? {
        if code == snapshot.base { return 1.0 }
        return snapshot.rates[code]
    }
}
