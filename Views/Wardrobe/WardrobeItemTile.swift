import SwiftUI

/// One wardrobe choice: the rat's head wearing the item, its name, and its
/// state. `item == nil` is the "nothing" tile that takes the slot's item off.
///
/// - Unlocked: rimmed in the tier's metal (the achievement colours, so a gold
///   hat reads as rare as a gold patch). Tap to put it on.
/// - Equipped: an accent ring and a check.
/// - Locked: dimmed and desaturated, with the level that opens it. Tapping
///   says when it unlocks rather than doing nothing.
struct WardrobeItemTile: View {
    let slot: WardrobeSlot
    let item: WardrobeItem?
    let level: Int
    let isEquipped: Bool
    let onSelect: () -> Void

    @State private var isShowingLockedNote = false
    @ScaledMetric(relativeTo: .body) private var portraitSize: CGFloat = 56

    private var isLocked: Bool {
        guard let item else { return false }
        return !item.isUnlocked(atLevel: level)
    }

    var body: some View {
        Button {
            if isLocked {
                isShowingLockedNote = true
            } else {
                onSelect()
            }
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                portrait
                caption
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(item?.name ?? String(localized: "ללא")))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityAddTraits(isEquipped ? .isSelected : [])
        .popover(isPresented: $isShowingLockedNote) {
            lockedNote
                .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: - Parts

    private var portrait: some View {
        AvatarPortrait(diameter: portraitSize, framing: .headroom) {
            AvatarLayers(
                crop: .bust,
                pose: .base,
                equipped: item.map { [slot: $0.id] } ?? [:]
            )
        }
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .saturation(isLocked ? 0 : 1)
        .opacity(isLocked ? 0.45 : 1)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(rimColor, lineWidth: isEquipped ? 3 : 1.5)
        }
        .overlay(alignment: .topTrailing) {
            if isEquipped {
                Image(systemName: "checkmark.circle.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.white, Theme.Colors.accent)
                    .offset(x: 5, y: -5)
            } else if isLocked {
                Image(systemName: "lock.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.xs)
            }
        }
        .accessibilityHidden(true)
    }

    private var caption: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            Text(item?.name ?? String(localized: "ללא"))
                .font(Theme.Typography.captionSmall)
                .foregroundStyle(isLocked ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let item, isLocked {
                Text("רמה \(item.unlockLevel)")
                    .font(Theme.Typography.captionSmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var lockedNote: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Label("נפתח ברמה \(item?.unlockLevel ?? 0)", systemImage: "lock.fill")
                .font(Theme.Typography.amount)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("הרמה שלך כרגע: \(level)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
    }

    // MARK: - State

    private var rimColor: Color {
        if isEquipped { return Theme.Colors.accent }
        guard let item, !isLocked else { return Theme.Colors.separator }
        switch item.tier {
        case .bronze: return Theme.Colors.tierBronze
        case .silver: return Theme.Colors.tierSilver
        case .gold:   return Theme.Colors.tierGold
        }
    }

    private var accessibilityValue: String {
        if isEquipped { return String(localized: "עליך עכשיו") }
        if let item, isLocked { return String(localized: "נעול, נפתח ברמה \(item.unlockLevel)") }
        return ""
    }
}
