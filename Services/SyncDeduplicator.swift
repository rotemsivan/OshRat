import Foundation
import SwiftData

/// Merges the duplicates iCloud sync can produce.
///
/// Each device creates some rows for itself before it has heard from the
/// others: the default categories on first launch, a `UserProgress` and a
/// `MascotConfig` on first use, an FX snapshot on its daily refresh, a
/// month's `BudgetMonthCommitment`. When sync brings two devices' stores
/// together they arrive side by side, and each is meant to exist once.
/// CloudKit has no unique constraints to prevent that, so it's resolved
/// here instead — after the fact, the same way on every device, so they
/// converge:
///
/// - **Categories:** `SeedData.prepareCategories` (merge by name, kind and
///   nature, re-pointing transactions and budget lines).
/// - **UserProfile:** the oldest is kept. Every screen reads profiles sorted
///   by `createdAt`, so it's also the one already shown.
/// - **UserProgress:** the oldest is kept and the others folded into it
///   (`UserProgress.absorb`), so no XP, streak or award is lost.
/// - **MascotConfig:** the oldest is kept.
/// - **FXRateSnapshot:** the newest is kept — it's only a cache.
/// - **BudgetMonthCommitment:** one per month, the oldest kept and lowered
///   to the smaller of each bucket (the tighten-only rule).
///
/// Runs when the store opens, whenever the app comes to the front, and after
/// sync imports changes from another device.
///
/// **Categories are only merged when the store opens** (cold launch), not on
/// coming to the front or after an import: merging hard-deletes a category,
/// and a sheet left open could be holding that very row (the hard-delete trap
/// in CLAUDE.md). Menus hide same-named twins meanwhile (`semanticallyUnique`).
/// The other rows here are only ever read through live queries, so they're
/// safe to merge whenever.
@MainActor
enum SyncDeduplicator {

    static func run(in context: ModelContext, includingCategories: Bool = true) {
        if includingCategories {
            SeedData.prepareCategories(in: context)
        }
        var changed = false
        changed = dedupeProfiles(in: context) || changed
        changed = dedupeProgress(in: context) || changed
        changed = keepOne(MascotConfig.self, sortedBy: SortDescriptor(\.createdAt), in: context) || changed
        changed = keepOne(FXRateSnapshot.self, sortedBy: SortDescriptor(\.fetchedAt, order: .reverse), in: context) || changed
        changed = dedupeCommitments(in: context) || changed
        if changed { try? context.save() }
    }

    private static func dedupeProfiles(in context: ModelContext) -> Bool {
        keepOne(UserProfile.self, sortedBy: SortDescriptor(\.createdAt), in: context)
    }

    private static func dedupeProgress(in context: ModelContext) -> Bool {
        let rows = (try? context.fetch(FetchDescriptor<UserProgress>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        guard let kept = rows.first, rows.count > 1 else { return false }
        for extra in rows.dropFirst() {
            kept.absorb(extra)
            context.delete(extra)
        }
        return true
    }

    private static func dedupeCommitments(in context: ModelContext) -> Bool {
        let rows = (try? context.fetch(FetchDescriptor<BudgetMonthCommitment>(sortBy: [SortDescriptor(\.capturedAt)]))) ?? []
        var kept: [YearMonth: BudgetMonthCommitment] = [:]
        var changed = false
        for row in rows {
            guard let first = kept[row.yearMonth] else {
                kept[row.yearMonth] = row
                continue
            }
            // Both are this month's commitment: the lower of each bucket is
            // the one the user was held to, whichever device wrote it.
            if first.currencyCode == row.currencyCode {
                let merged = PlannedSpend(needs: first.plannedNeeds, wants: first.plannedWants)
                    .tightened(by: PlannedSpend(needs: row.plannedNeeds, wants: row.plannedWants))
                first.plannedNeeds = merged.needs
                first.plannedWants = merged.wants
            }
            context.delete(row)
            changed = true
        }
        return changed
    }

    /// Keeps the first row in `order` and deletes the rest.
    private static func keepOne<T: PersistentModel>(
        _ type: T.Type,
        sortedBy order: SortDescriptor<T>,
        in context: ModelContext
    ) -> Bool {
        let rows = (try? context.fetch(FetchDescriptor<T>(sortBy: [order]))) ?? []
        guard rows.count > 1 else { return false }
        rows.dropFirst().forEach(context.delete)
        return true
    }
}
