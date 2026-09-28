import SwiftUI
import SwiftData

/// "הקטגוריות שלי" — every category, grouped the way the menus group them
/// (income, then צרכים / מותרות / אחר). Pushed from Settings → ניהול.
///
/// **Only the user's own categories are editable.** The defaults are shown
/// greyed, with no chevron and no swipe — they're the fixed vocabulary the
/// budget, the analytics and the demo scenarios are written against. The
/// user's own rows tap to edit and swipe to delete; "+" adds one.
///
/// **Deleting is a hard delete** (categories have no Recently Deleted), so
/// the rows render from `CategoryRowSnapshot` values and act through a
/// `PersistentIdentifier` — reading a just-deleted model while `List`
/// animates its row away traps (the hard-delete trap in CLAUDE.md).
///
/// Only an **unused** category can be deleted. One with transactions —
/// including ones in Recently Deleted, which would come back without it — or
/// with budget lines is kept, and the swipe explains why; renaming it or
/// changing its icon is always possible.
struct CategoriesView: View {
    @Query private var categories: [Category]
    @Query private var budgetItems: [BudgetItem]
    @Environment(\.modelContext) private var modelContext

    @State private var isCreating = false
    @State private var editing: EditTarget?
    /// The category a delete was refused for, named in the alert.
    @State private var blockedName = ""
    @State private var showsBlockedAlert = false

    var body: some View {
        let groups = sections()
        List {
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.rows) { row in
                        if row.isUserCreated {
                            Button {
                                editing = EditTarget(id: row.id)
                            } label: {
                                CategoryManagerRow(row: row)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("מחיקה", systemImage: "trash", role: .destructive) {
                                    delete(row)
                                }
                            }
                        } else {
                            CategoryManagerRow(row: row)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        // The rows are tappable to the last one, so clear the floating "+" too.
        .contentMargins(.bottom, HomeBottomBar.floatingButtonClearance, for: .scrollContent)
        .navigationTitle(Text("הקטגוריות שלי"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("קטגוריה חדשה", systemImage: "plus") { isCreating = true }
            }
        }
        .sheet(isPresented: $isCreating) {
            CategoryEditorSheet()
        }
        .sheet(item: $editing) { target in
            // Nothing can be deleted while this sheet is up, so the id always
            // resolves to a live category here.
            if let category = modelContext.model(for: target.id) as? Category {
                CategoryEditorSheet(category: category)
            }
        }
        .alert("אי אפשר למחוק את הקטגוריה", isPresented: $showsBlockedAlert, presenting: blockedName) { _ in
            Button("הבנתי", role: .cancel) {}
        } message: { name in
            Text("ל\(name) יש תנועות או פריטי תקציב. אפשר לשנות לה שם או סמל.")
        }
    }

    // MARK: - Data

    private struct EditTarget: Identifiable {
        let id: PersistentIdentifier
    }

    private struct CategorySection: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let rows: [CategoryRowSnapshot]
    }

    /// The menus' grouping, turned into value snapshots.
    private func sections() -> [CategorySection] {
        let budgeted = Set(budgetItems.compactMap { $0.category?.persistentModelID })
        return CategoryMenuGroup.groups(from: categories, kinds: [.income, .expense]).map { group in
            CategorySection(id: group.id, title: group.title, rows: group.categories.map { category in
                CategoryRowSnapshot(
                    id: category.persistentModelID,
                    name: category.name,
                    symbolName: category.symbolName,
                    colorHex: category.colorHex,
                    isUserCreated: category.isUserCreated,
                    isInUse: !category.transactions.isEmpty || budgeted.contains(category.persistentModelID)
                )
            })
        }
    }

    private func delete(_ row: CategoryRowSnapshot) {
        guard !row.isInUse else {
            blockedName = row.name
            showsBlockedAlert = true
            return
        }
        guard let category = modelContext.model(for: row.id) as? Category else { return }
        modelContext.delete(category)
        try? modelContext.save()
    }
}

/// What a manager row needs, copied out of the model so the row can outlive it.
struct CategoryRowSnapshot: Identifiable {
    let id: PersistentIdentifier
    let name: String
    let symbolName: String
    let colorHex: String
    let isUserCreated: Bool
    let isInUse: Bool
}

/// One manager row. A default reads greyed — its badge drained of colour,
/// its name secondary, no chevron — so "this one's fixed" shows before any
/// tap is tried.
private struct CategoryManagerRow: View {
    let row: CategoryRowSnapshot

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            CategoryBadge(symbolName: row.symbolName, colorHex: row.colorHex)
                .grayscale(row.isUserCreated ? 0 : 1)
                .opacity(row.isUserCreated ? 1 : 0.6)
            Text(row.name)
                .font(Theme.Typography.body)
                .foregroundStyle(row.isUserCreated ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            Spacer()
            if row.isUserCreated {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint(row.isUserCreated ? Text("עריכה") : Text("קטגוריית ברירת מחדל, לא ניתנת לעריכה"))
    }
}
