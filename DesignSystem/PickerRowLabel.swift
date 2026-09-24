import SwiftUI

/// The tappable row that opens a `Menu` — Hebrew value text on the visual
/// right, an up/down chevron on the visual left, inside the app's standard
/// bordered card.
///
/// Extracted from `NewTransactionSheet` so every "choose one of these" control
/// looks the same wherever it appears: the transaction sheet's account and
/// category pickers, the budget editors' category picker and the transactions
/// filter's. Category menus fill it with `CategoryMenuContent`.
///
/// Implementation note (kept from the original): `Menu { … } label: { … }`
/// doesn't reliably forward the `\.layoutDirection` environment into the label
/// closure, so even with RTL forced at the sheet root the row kept rendering
/// LTR. We pin the direction on the row **and** order the children in their
/// RTL-correct visual positions, so it's right whether or not the environment
/// propagates.
struct PickerRowLabel: View {
    let text: String
    /// Shown ahead of the text when the caller has something to illustrate the
    /// current choice with — a category's glyph, say. Omitted for plain
    /// text-only pickers.
    var systemImage: String?

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 22)
            }
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.up.chevron.down")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.Colors.separator, lineWidth: 1)
        )
        .environment(\.layoutDirection, .rightToLeft)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.md) {
        PickerRowLabel(text: "בחרו קטגוריה")
        PickerRowLabel(text: "מכולת", systemImage: "cart")
    }
    .padding(Theme.Spacing.lg)
    .background(Theme.Colors.background)
}
