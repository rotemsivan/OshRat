import SwiftUI

/// The contents of every "choose a category" menu in the app, so the list
/// reads the same wherever it opens: the transaction sheet, the budget
/// expense editor and the transactions filter.
///
/// One arrangement everywhere:
/// - **Grouped.** Income first (when it's offered), then expenses split into
///   צרכים, רצונות and אחר — the needs-vs-wants split the budget and the
///   dashboard are built on, so picking a category shows which side of it the
///   money lands on. A group with nothing in it is left out rather than shown
///   as an empty heading.
/// - **Alphabetical within a group**, by Hebrew collation rather than the
///   store's byte order, which is what the `@Query` sorts gave each picker
///   before (and why they could disagree).
/// - **Each with its glyph**, the same one the transaction rows show.
///
/// Wrap it in a `Menu` whose label is a `PickerRowLabel`, and put any "no
/// category" / "all" option ahead of it.
struct CategoryMenuContent: View {
    let categories: [Category]
    /// Which kinds to offer, e.g. `[.expense]` for the budget editor or both
    /// for the filter. Their order doesn't matter — income always leads.
    let kinds: Set<TransactionKind>
    let onSelect: (Category) -> Void

    var body: some View {
        let groups = CategoryMenuGroup.groups(from: categories, kinds: kinds)
        ForEach(groups) { group in
            Section {
                ForEach(group.categories) { category in
                    Button {
                        onSelect(category)
                    } label: {
                        Label(category.name, systemImage: category.symbolName)
                    }
                }
            } header: {
                // A lone group needs no heading: an income-only menu titled
                // "הכנסות" says nothing the sheet around it hasn't.
                if groups.count > 1 {
                    Text(group.title)
                }
            }
        }
    }
}

/// One headed group of `CategoryMenuContent`.
struct CategoryMenuGroup: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let categories: [Category]

    /// The groups, in display order, with duplicates collapsed and each
    /// group sorted by name.
    static func groups(from categories: [Category], kinds: Set<TransactionKind>) -> [CategoryMenuGroup] {
        let unique = categories.semanticallyUnique.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        var groups: [CategoryMenuGroup] = []
        if kinds.contains(.income) {
            groups.append(CategoryMenuGroup(
                id: "income",
                title: "הכנסות",
                categories: unique.filter { $0.kind == .income }
            ))
        }
        if kinds.contains(.expense) {
            let expenses = unique.filter { $0.kind == .expense }
            groups.append(CategoryMenuGroup(id: "need", title: "צרכים", categories: expenses.filter { $0.nature == .need }))
            groups.append(CategoryMenuGroup(id: "want", title: "רצונות", categories: expenses.filter { $0.nature == .want }))
            groups.append(CategoryMenuGroup(id: "neutral", title: "אחר", categories: expenses.filter { $0.nature == .neutral }))
        }
        return groups.filter { !$0.categories.isEmpty }
    }
}
