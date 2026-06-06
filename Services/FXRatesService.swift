import Foundation
import SwiftData

/// Fetches and caches FX reference rates from Frankfurter.dev.
///
/// Per CLAUDE.md's "FX rates (network exception)" section, this is the
/// only network call the MVP makes. Public data, no auth, no user
/// identifiers in the request. The dashboard reads from the cached
/// `FXRateSnapshot`; this service only writes.
///
/// Designed as a `@MainActor enum` (rather than an instance) because
/// it has no state of its own — the SwiftData cache *is* the state —
/// and being main-actor isolated avoids the cross-actor dance with
/// `ModelContext`.
@MainActor
enum FXRatesService {
    /// How long a cached snapshot is considered fresh. Frankfurter
    /// updates once per business day, so 24h is a reasonable refresh
    /// cadence — small enough to feel current, large enough to stay
    /// well within Frankfurter's gentle public-good usage.
    static let cacheLifetimeSeconds: TimeInterval = 24 * 3600

    /// We always pull rates relative to EUR — Frankfurter is ECB-
    /// sourced and EUR is its natural base. Conversion math (EUR-USD,
    /// EUR-ILS, etc.) is done in `CurrencyConverter` via cross-rates.
    static let baseCurrency = "EUR"

    /// If the cache is stale (or missing), fetch fresh rates and
    /// replace the cached snapshot. Silent on network failure: the
    /// rest of the app falls back to whatever cache exists, or to a
    /// "FX unavailable" display.
    static func refreshIfNeeded(in context: ModelContext) async {
        let descriptor = FetchDescriptor<FXRateSnapshot>(
            sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)]
        )
        let snapshots = (try? context.fetch(descriptor)) ?? []

        if let latest = snapshots.first, !isStale(latest) {
            return
        }

        do {
            let fresh = try await fetchFresh()
            // Keep only the freshest row. We never need history here —
            // the dashboard always shows "today's rates".
            for old in snapshots {
                context.delete(old)
            }
            context.insert(fresh)
            try? context.save()
        } catch {
            #if DEBUG
            print("FX fetch failed: \(error)")
            #endif
        }
    }

    // MARK: - Internals

    private static func isStale(_ snapshot: FXRateSnapshot) -> Bool {
        Date.now.timeIntervalSince(snapshot.fetchedAt) > cacheLifetimeSeconds
    }

    private static func fetchFresh() async throws -> FXRateSnapshot {
        var components = URLComponents(string: "https://api.frankfurter.dev/v1/latest")!
        components.queryItems = [URLQueryItem(name: "base", value: baseCurrency)]

        var request = URLRequest(url: components.url!)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 8

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
        return FXRateSnapshot(
            base: payload.base,
            fetchedAt: .now,
            rates: payload.rates
        )
    }

    /// Minimal decoder for Frankfurter's `/v1/latest` payload. We only
    /// need `base` and `rates`; the `date` field is parsed but unused
    /// (we use our own `fetchedAt` so the cache key matches what we did,
    /// not what the upstream said).
    private struct FrankfurterResponse: Decodable {
        let base: String
        let date: String
        let rates: [String: Double]
    }
}
