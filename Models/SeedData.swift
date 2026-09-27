import Foundation
import SwiftData

/// Keeps the default Hebrew categories in the store, so the user is never
/// faced with an empty list.
///
/// Each expense category is tagged as a *need* (צרכים) or a *want* (מותרות)
/// so the budget builder during onboarding — and the dashboard later — can
/// visually distinguish "must-pay" lines from discretionary spending.
/// Income categories use `.neutral`.
///
/// The defaults are **immutable** (`Category.isUserCreated` is false for
/// them; the manager can't edit or delete them), which is what makes a plain
/// top-up by name on every launch safe: nothing the user did can be undone by
/// it.
enum SeedData {

    /// Defaults that were renamed, old name → new. Applied before the top-up,
    /// so an existing user's row is renamed **in place** — its transactions
    /// and budget lines come with it — rather than a second, empty category
    /// appearing beside it under the new name.
    static let renamedDefaults: [(old: String, new: String)] = [
        ("שכירות", "דיור"),
        ("לימודים", "חינוך והשכלה")
    ]

    /// Renames any default still under an old name, then inserts every default
    /// the store doesn't have (keyed by name and kind). Idempotent, so it runs
    /// every launch — and a new default added to `defaultCategories()` reaches
    /// existing users without any extra step. A **rename** does need an entry
    /// in `renamedDefaults`, or the old row would be kept and a new empty one
    /// added beside it.
    static func seedDefaultCategoriesIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        var changed = false

        for (old, new) in renamedDefaults {
            let hasNew = existing.contains { $0.kind == .expense && $0.name == new }
            // Only a default is renamed; a category the user made is theirs.
            if !hasNew, let legacy = existing.first(where: {
                $0.kind == .expense && $0.name == old && !$0.isUserCreated
            }) {
                legacy.name = new
                changed = true
            }
        }

        // Name and kind, not nature: a user's own "מינויים" filed as a need
        // still means the default "מינויים" is already there.
        var present = Set(existing.map { "\($0.name)|\($0.kind.rawValue)" })
        for category in defaultCategories() {
            let key = "\(category.name)|\(category.kind.rawValue)"
            guard !present.contains(key) else { continue }
            context.insert(category)
            present.insert(key)
            changed = true
        }

        if changed {
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
    /// dev "reset" flow can re-seed directly. Adding a category here is all
    /// it takes; **renaming** one also needs an entry in `renamedDefaults`.
    static func defaultCategories() -> [Category] {
        return [
            // NEEDS — צרכים
            Category(name: "כלכלת בית",              kind: .expense, colorHex: "#E57373", symbolName: "cart",            nature: .need),
            Category(name: "דיור",              kind: .expense, colorHex: "#64B5F6", symbolName: "house",           nature: .need),
            Category(name: "חשבונות",           kind: .expense, colorHex: "#BA68C8", symbolName: "doc.text",        nature: .need),
            Category(name: "ביטוחים",           kind: .expense, colorHex: "#9575CD", symbolName: "shield",          nature: .need),
            Category(name: "חינוך והשכלה",      kind: .expense, colorHex: "#7986CB", symbolName: "graduationcap",   nature: .need),
            Category(name: "תחבורה ציבורית",   kind: .expense, colorHex: "#FFB74D", symbolName: "bus",             nature: .need),
            Category(name: "הוצאות רכב",        kind: .expense, colorHex: "#FF8A65", symbolName: "car",             nature: .need),
            Category(name: "בריאות",            kind: .expense, colorHex: "#F06292", symbolName: "cross.case",      nature: .need),

            // WANTS — מותרות
            Category(name: "בילויים",                 kind: .expense, colorHex: "#4DB6AC", symbolName: "ticket",     nature: .want),
            Category(name: "חופשות",                 kind: .expense, colorHex: "#4d83b6", symbolName: "airplane",     nature: .want),
            Category(name: "מסעדות ובתי קפה",       kind: .expense, colorHex: "#81C784", symbolName: "fork.knife", nature: .want),
            Category(name: "אופנה וביגוד",            kind: .expense, colorHex: "#F48FB1", symbolName: "tshirt",      nature: .want),
            Category(name: "מתנות",                    kind: .expense, colorHex: "#FFB74D", symbolName: "gift",       nature: .want),
            Category(name: "טיפוח",                    kind: .expense, colorHex: "#CE93D8", symbolName: "scissors",   nature: .want),
            Category(name: "כושר גופני",                 kind: .expense, colorHex: "#A1887F", symbolName: "figure.run",  nature: .want),
            // Netflix, Spotify, iCloud… — small, recurring and easy to forget.
            Category(name: "מינויים",                  kind: .expense, colorHex: "#E53935", symbolName: "play.rectangle", nature: .want),
            Category(name: "שונות",                    kind: .expense, colorHex: "#90A4AE", symbolName: "ellipsis.circle", nature: .want),

            // SECURITIES — ני״ע
            // Stand-ins until investment accounts are built: until then, buying
            // and selling securities is logged as an ordinary transaction
            // against whichever account the money moved through. Tagged
            // `.neutral` because a purchase is neither a need nor a want — note
            // that neutral expenses currently fall into the צרכים bucket in
            // needs-vs-wants, so a month with a large purchase will read as a
            // heavy "needs" month.
            Category(name: "קניית ני״ע", kind: .expense, colorHex: "#546E7A", symbolName: "chart.line.uptrend.xyaxis",   nature: .neutral),

            // INCOME — הכנסות
            Category(name: "משכורת",      kind: .income, colorHex: "#81C784", symbolName: "banknote",    nature: .neutral),
            Category(name: "הכנסה נוספת", kind: .income, colorHex: "#AED581", symbolName: "plus.circle", nature: .neutral),
            Category(name: "מכירת ני״ע", kind: .income, colorHex: "#26A69A", symbolName: "chart.line.downtrend.xyaxis", nature: .neutral),
        ]
    }
}
