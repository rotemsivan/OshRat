import SwiftUI
import SwiftData

/// Creates a category, or edits one the user made: name, income/expense,
/// need or luxury (צורך / מותרות), and an icon and colour from
/// `CategoryAppearance`'s closed lists. Default categories are read-only and
/// never reach this sheet.
///
/// An expense is always one of the two — no "אחר" — so everything the user
/// adds lands cleanly on one side of the needs-vs-luxuries split the budget
/// and the analytics are built on.
///
/// Opened from the category manager (`CategoriesView`) and from the
/// "קטגוריה חדשה…" item at the end of a category menu, where `fixedKind`
/// pins the kind to the transaction or budget line being filled in and
/// `onSave` hands the new category back so it can be selected on the spot.
///
/// The kind can only be chosen when creating: changing an existing
/// category's kind would leave its expenses filed under an income category.
/// Deleting lives in the manager, not here — see `CategoriesView`.
struct CategoryEditorSheet: View {
    /// The category being edited; `nil` to create one.
    private let category: Category?
    private let fixedKind: TransactionKind?
    private let onSave: (Category) -> Void

    @State private var name: String
    @State private var kind: TransactionKind
    @State private var nature: CategoryNature
    @State private var symbolName: String
    @State private var colorHex: String

    @Query private var allCategories: [Category]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    init(
        category: Category? = nil,
        fixedKind: TransactionKind? = nil,
        onSave: @escaping (Category) -> Void = { _ in }
    ) {
        self.category = category
        self.fixedKind = fixedKind
        self.onSave = onSave
        let kind = category?.kind ?? fixedKind ?? .expense
        _name = State(initialValue: category?.name ?? "")
        _kind = State(initialValue: kind)
        // A neutral expense (none can be made here any more) opens as a need.
        let nature = category?.nature ?? .need
        _nature = State(initialValue: kind == .income ? .neutral : (nature == .neutral ? .need : nature))
        _symbolName = State(initialValue: category?.symbolName ?? CategoryAppearance.defaultSymbol)
        _colorHex = State(initialValue: category?.colorHex ?? CategoryAppearance.defaultColor)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var nameIsTaken: Bool {
        Category.nameIsTaken(trimmedName, kind: kind, among: allCategories, excluding: category)
    }

    private var canSave: Bool { !trimmedName.isEmpty && !nameIsTaken }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CategoryPreview(name: trimmedName, symbolName: symbolName, colorHex: colorHex)
                        .listRowBackground(Color.clear)
                }

                Section {
                    HebrewTextField("שם הקטגוריה", text: $name)
                } footer: {
                    if nameIsTaken {
                        Text("כבר יש קטגוריה בשם הזה.")
                            .foregroundStyle(Theme.Colors.expense)
                    }
                }

                // Kind (only when creating from the manager) and, for an
                // expense, need / luxury — one section, so the form stays short.
                let choosesKind = category == nil && fixedKind == nil
                if choosesKind || kind == .expense {
                    Section {
                        if choosesKind {
                            Picker("סוג", selection: $kind) {
                                Text("הוצאה").tag(TransactionKind.expense)
                                Text("הכנסה").tag(TransactionKind.income)
                            }
                            .pickerStyle(.segmented)
                            .listRowBackground(Color.clear)
                        }
                        if kind == .expense {
                            Picker("סיווג", selection: $nature) {
                                Text("צורך").tag(CategoryNature.need)
                                Text("מותרות").tag(CategoryNature.want)
                            }
                            .pickerStyle(.segmented)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listRowSeparator(.hidden)
                }

                Section("צבע") {
                    ColorSwatches(selection: $colorHex)
                        .listRowBackground(Color.clear)
                }

                ForEach(CategoryAppearance.symbolGroups) { group in
                    Section(group.title) {
                        SymbolGrid(symbols: group.symbols, colorHex: colorHex, selection: $symbolName)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .listSectionSpacing(.compact)
            .navigationTitle(category == nil ? Text("קטגוריה חדשה") : Text("עריכת קטגוריה"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה", action: save)
                        .disabled(!canSave)
                }
            }
            // Income categories have no need/want split.
            .onChange(of: kind) { _, newKind in
                nature = newKind == .expense ? .need : .neutral
            }
        }
        .tint(Theme.Colors.accent)
    }

    private func save() {
        guard canSave else { return }
        let target: Category
        if let category {
            target = category
        } else {
            target = Category(kind: kind)
            target.isUserCreated = true
            modelContext.insert(target)
        }
        target.name = trimmedName
        target.nature = kind == .expense ? nature : .neutral
        target.symbolName = symbolName
        target.colorHex = colorHex
        try? modelContext.save()
        onSave(target)
        dismiss()
    }
}

// MARK: - Preview chip

/// The category as menus and rows will show it, updating as it's edited.
private struct CategoryPreview: View {
    let name: String
    let symbolName: String
    let colorHex: String

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            CategoryBadge(symbolName: symbolName, colorHex: colorHex, diameter: 64)
            Text(name.isEmpty ? "קטגוריה חדשה" : name)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(name.isEmpty ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A category's icon on a tinted disc — the editor preview and the manager's rows.
struct CategoryBadge: View {
    let symbolName: String
    let colorHex: String
    var diameter: CGFloat = 36

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: diameter * 0.45, weight: .semibold))
            .foregroundStyle(Color(hex: colorHex))
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(Color(hex: colorHex).opacity(0.16)))
            .accessibilityHidden(true)
    }
}

// MARK: - Pickers

private struct ColorSwatches: View {
    @Binding var selection: String

    /// The palette, plus the current colour when it isn't one of them (a
    /// category from before the palette existed keeps its own).
    private var colors: [String] {
        let palette = CategoryAppearance.colors
        return palette.contains(where: { $0.caseInsensitiveCompare(selection) == .orderedSame })
            ? palette : [selection] + palette
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: Theme.Spacing.xs)], spacing: Theme.Spacing.xs) {
            ForEach(colors, id: \.self) { hex in
                let isSelected = hex.caseInsensitiveCompare(selection) == .orderedSame
                Button {
                    selection = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 30, height: 30)
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("צבע"))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

private struct SymbolGrid: View {
    let symbols: [String]
    let colorHex: String
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: Theme.Spacing.xs)], spacing: Theme.Spacing.xs) {
            ForEach(symbols, id: \.self) { symbol in
                let isSelected = symbol == selection
                Button {
                    selection = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Theme.Colors.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.button)
                                .fill(isSelected ? Color(hex: colorHex) : Theme.Colors.surface)
                        )
                }
                .buttonStyle(.plain)
                // No label of our own: the symbol's built-in description
                // ("fork and knife") is what VoiceOver should read.
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
