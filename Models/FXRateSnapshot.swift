import Foundation
import SwiftData

/// A snapshot of FX reference rates fetched from Frankfurter.dev.
///
/// We keep at most one snapshot alive at a time — the dashboard reads
/// the latest to convert per-currency totals into the user's preferred
/// currency. The data is *public reference data* (ECB rates), not
/// anything tied to the user, so it doesn't violate the privacy spirit
/// of CLAUDE.md (see the "FX rates (network exception)" section there).
@Model
final class FXRateSnapshot {
    /// ISO code that all rates in `rates` are quoted against. We pin
    /// this to "EUR" because Frankfurter is ECB-sourced and EUR is
    /// its natural base.
    var base: String = "EUR"

    /// When this snapshot was fetched. The dashboard surfaces this as
    /// "מומר משער של DATE" so the user knows how fresh the conversion is.
    var fetchedAt: Date = Date.now

    /// JSON-encoded `[String: Double]` of currency code → rate against
    /// `base`. Stored as `Data` because SwiftData's transformable
    /// storage for dictionaries has been historically flaky;
    /// hand-rolling JSON is more portable and CloudKit-friendly.
    var rateData: Data = Data()

    init(
        base: String = "EUR",
        fetchedAt: Date = .now,
        rates: [String: Double] = [:]
    ) {
        self.base = base
        self.fetchedAt = fetchedAt
        self.rateData = (try? JSONEncoder().encode(rates)) ?? Data()
    }

    /// Decoded rates dictionary. Recomputed per access — we expect a
    /// handful of reads per render, not a tight loop, so this is fine.
    /// Failure to decode (e.g. corrupted blob) degrades gracefully to
    /// an empty dictionary; callers then fall through to "FX unavailable".
    var rates: [String: Double] {
        (try? JSONDecoder().decode([String: Double].self, from: rateData)) ?? [:]
    }
}
