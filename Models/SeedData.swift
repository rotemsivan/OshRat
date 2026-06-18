import Foundation
import SwiftData

/// Creates a starter set of Hebrew categories the first time the app launches,
/// so the user isn't faced with an empty list. Runs only when none exist yet.
///
/// Each expense category is tagged as a *need* (צרכים) or a *want* (רצונות)
/// so the budget builder during onboarding — and the dashboard later — can
/// visually distinguish "must-pay" lines from discretionary spending.
/// Income categories use `.neutral`.
enum SeedData {
    /// Idempotent seed: insert any default categories that aren't
    /// already in the store, keyed by `(name, kind)`. The old
    /// implementation skipped the entire pass if *any* category
    /// existed, which made it easy to end up with a partial set after
    /// a debug reset (e.g. user added one custom category, then reset
    /// killed everything → next launch saw "non-empty" and skipped).
    /// This version is safe to call every launch.
    static func seedDefaultCategoriesIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        // A composite key — same name on income vs expense (e.g.
        // "מתנות") should not collide.
        var existingKeys: Set<String> = []
        for category in existing {
            existingKeys.insert(Self.key(for: category))
        }

        var inserted = false
        for category in defaultCategories() where !existingKeys.contains(Self.key(for: category)) {
            context.insert(category)
            existingKeys.insert(Self.key(for: category))
            inserted = true
        }
        if inserted {
            try? context.save()
        }
    }

    /// One-time clean-up pass: if two rows share the same
    /// `(name, kind, nature)` triple, keep one and reassign anything
    /// pointing at the duplicates over to it before deletion. Without
    /// the re-pointing step we'd silently nuke transactions' and
    /// budget items' category links on the duplicate row.
    static func dedupeCategoriesIfNeeded(in context: ModelContext) {
        guard let existing = try? context.fetch(FetchDescriptor<Category>()),
              !existing.isEmpty
        else { return }

        // Bucket every category by its semantic identity. The first
        // one we see for a given key becomes canonical; the rest are
        // marked for re-pointing + deletion.
        var canonical: [String: Category] = [:]
        var duplicates: [Category] = []
        for category in existing {
            let key = Self.key(for: category)
            if let _ = canonical[key] {
                duplicates.append(category)
            } else {
                canonical[key] = category
            }
        }
        guard !duplicates.isEmpty else { return }

        // Re-point transactions whose category link points at one of
        // the duplicates. The inverse relationship on `Category` gives
        // us the transactions directly — no fetch needed.
        for duplicate in duplicates {
            let canonicalForThis = canonical[Self.key(for: duplicate)]
            for tx in duplicate.transactions {
                tx.category = canonicalForThis
            }
        }

        // BudgetItem has no inverse on Category, so we have to fetch
        // the full set and rewrite any links pointing at duplicates.
        let duplicateIDs = Set(duplicates.map { $0.persistentModelID })
        if let budgetItems = try? context.fetch(FetchDescriptor<BudgetItem>()) {
            for item in budgetItems {
                guard let linked = item.category,
                      duplicateIDs.contains(linked.persistentModelID)
                else { continue }
                item.category = canonical[Self.key(for: linked)]
            }
        }

        for duplicate in duplicates {
            context.delete(duplicate)
        }
        try? context.save()
    }

    /// Composite identity key used by both the idempotent seed and
    /// the dedupe pass, so they agree on what counts as "the same
    /// category". `nature` is included so we don't collapse income's
    /// neutral "מתנות" into expense's "wants" version of the same
    /// name (different role in the budget).
    private static func key(for category: Category) -> String {
        "\(category.name)|\(category.kind.rawValue)|\(category.natureRaw)"
    }

    /// Returns a fresh batch of the starter categories. Pulled out so the
    /// dev "reset" flow can re-seed without going through the
    /// "only if empty" gate above.
    static func defaultCategories() -> [Category] {
        return [
            // NEEDS — צרכים
            Category(name: "כלכלת בית",              kind: .expense, colorHex: "#E57373", symbolName: "cart",            nature: .need),
            Category(name: "שכירות",            kind: .expense, colorHex: "#64B5F6", symbolName: "house",           nature: .need),
            Category(name: "חשבונות",           kind: .expense, colorHex: "#BA68C8", symbolName: "doc.text",        nature: .need),
            Category(name: "ביטוחים",           kind: .expense, colorHex: "#9575CD", symbolName: "shield",          nature: .need),
            Category(name: "לימודים",           kind: .expense, colorHex: "#7986CB", symbolName: "graduationcap",   nature: .need),
            Category(name: "תחבורה ציבורית",   kind: .expense, colorHex: "#FFB74D", symbolName: "bus",             nature: .need),
            Category(name: "הוצאות רכב",        kind: .expense, colorHex: "#FF8A65", symbolName: "car",             nature: .need),
            Category(name: "בריאות",            kind: .expense, colorHex: "#F06292", symbolName: "cross.case",      nature: .need),

            // WANTS — רצונות
            Category(name: "בילויים",                 kind: .expense, colorHex: "#4DB6AC", symbolName: "ticket",     nature: .want),
            Category(name: "חופשות",                 kind: .expense, colorHex: "#4d83b6", symbolName: "airplane",     nature: .want),
            Category(name: "מסעדות ובתי קפה",       kind: .expense, colorHex: "#81C784", symbolName: "fork.knife", nature: .want),
            Category(name: "אופנה וביגוד",            kind: .expense, colorHex: "#F48FB1", symbolName: "tshirt",      nature: .want),
            Category(name: "מתנות",                    kind: .expense, colorHex: "#FFB74D", symbolName: "gift",       nature: .want),
            Category(name: "טיפוח",                    kind: .expense, colorHex: "#CE93D8", symbolName: "scissors",   nature: .want),
            Category(name: "כושר גופני",                 kind: .expense, colorHex: "#A1887F", symbolName: "figure.run",  nature: .want),

            // INCOME — הכנסות
            Category(name: "משכורת",      kind: .income, colorHex: "#81C784", symbolName: "banknote",    nature: .neutral),
            Category(name: "הכנסה נוספת", kind: .income, colorHex: "#AED581", symbolName: "plus.circle", nature: .neutral),
        ]
    }
}
