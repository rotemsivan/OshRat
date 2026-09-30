import Foundation
import SwiftData

/// A grouping for transactions, e.g. "מזון", "שכר דירה", "משכורת".
/// Each category is either an income or an expense category.
///
/// `nature` distinguishes "need" categories (rent, bills…) from "want"
/// categories (going out, gifts…). Income categories use `.neutral`.
/// The split powers the wants-vs-needs visualisation on the dashboard
/// and the budget builder during onboarding.
@Model
final class Category {
    var name: String = ""
    var kind: TransactionKind = TransactionKind.expense
    /// Hex colour like "#E57373" — used for the tag/dot colour in the UI.
    var colorHex: String = "#9E9E9E"
    /// An SF Symbol name for the icon, e.g. "cart" or "house".
    var symbolName: String = "tag"

    /// Stored as the enum's rawValue so SwiftData can persist it. The
    /// computed `nature` property below is what callers should use.
    /// Default of "neutral" means manually-created categories don't get
    /// silently labelled as a "need" or "want" unless the user asks.
    var natureRaw: String = CategoryNature.neutral.rawValue

    /// True for a category the user made in the category editor; false for
    /// the defaults `SeedData` ships. Defaults are **read-only** — every
    /// screen, analytic and demo scenario can rely on them being there under
    /// their own names — so the manager greys them out and only user-made
    /// ones can be edited or deleted. Defaulted to `false`, so every row
    /// from before the flag existed (all of them seeded) migrates as a default.
    var isUserCreated: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction]? = []

    /// Budget lines filed under this category. The inverse of
    /// `BudgetItem.category`, which had none — and CloudKit sync requires
    /// every relationship to have one. Nullify: deleting a category leaves
    /// its budget lines uncategorised rather than taking them with it.
    @Relationship(deleteRule: .nullify, inverse: \BudgetItem.category)
    var budgetItems: [BudgetItem]? = []

    init(
        name: String = "",
        kind: TransactionKind = .expense,
        colorHex: String = "#9E9E9E",
        symbolName: String = "tag",
        nature: CategoryNature = .neutral
    ) {
        self.name = name
        self.kind = kind
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.natureRaw = nature.rawValue
    }

    /// Bridges the stored raw value to the typed enum. The fallback to
    /// `.neutral` covers old rows from before this field existed.
    var nature: CategoryNature {
        get { CategoryNature(rawValue: natureRaw) ?? .neutral }
        set { natureRaw = newValue.rawValue }
    }
}

extension Category {
    /// Whether `name` would clash with another category of the same kind —
    /// the rule the category editor enforces. Two "מסעדות" expense rows
    /// would read as one in every menu, and the launch-time dedupe pass
    /// (`SeedData.dedupeCategoriesIfNeeded`) would merge them. Compared
    /// trimmed and ignoring case and niqqud; `excluding` is the category
    /// being edited, which may keep its own name.
    static func nameIsTaken(
        _ name: String,
        kind: TransactionKind,
        among categories: [Category],
        excluding: Category? = nil
    ) -> Bool {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return categories.contains { other in
            other !== excluding
                && other.kind == kind
                && other.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .compare(wanted, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }
}

extension Array where Element == Category {
    /// Returns the array with semantic duplicates collapsed — two
    /// categories sharing the same `(name, kind, nature)` triple
    /// become one row. Order is preserved (first occurrence wins).
    ///
    /// The launch-time `SeedData.dedupeCategoriesIfNeeded` pass handles
    /// duplicates at the persistence layer, but a UI-side guard means
    /// pickers can never *visually* show a doubled list even if the
    /// store somehow still has dupes (mid-migration, stale simulator
    /// state, etc.).
    var semanticallyUnique: [Category] {
        var seen: Set<String> = []
        var result: [Category] = []
        for category in self {
            let key = "\(category.name)|\(category.kind.rawValue)|\(category.natureRaw)"
            if seen.insert(key).inserted {
                result.append(category)
            }
        }
        return result
    }
}
