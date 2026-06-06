import SwiftUI

/// Floating bottom navigation bar.
///
/// For now there's only one item — the home icon, centred — but the bar
/// is intentionally laid out with empty side slots so future feature
/// icons (transactions, goals, settings…) can slot in on either side
/// without re-doing the layout.
///
/// Uses iOS 26's Liquid Glass material so the bar floats over the
/// content behind it. Icon colours come from the design system: the
/// active tab uses the brand accent, inactive uses muted text.
struct HomeBottomBar: View {
    enum Tab: Hashable {
        case home
    }

    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 0) {
            sideSlot
            HomeBarButton(tab: .home, symbol: "house.fill", selection: $selection)
            sideSlot
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .glassEffect(.regular, in: .capsule)
    }

    /// Empty slot on either side of the centred home button. Both sides
    /// share the same builder so future icons land symmetrically.
    private var sideSlot: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

/// One tappable item inside the bar. Highlights itself with the brand
/// accent when its tab is the active selection.
private struct HomeBarButton: View {
    let tab: HomeBottomBar.Tab
    let symbol: String
    @Binding var selection: HomeBottomBar.Tab

    var body: some View {
        Button {
            selection = tab
        } label: {
            Image(systemName: symbol)
                .font(Theme.Typography.sectionTitle)
                .frame(width: 48, height: 48)
                .foregroundStyle(selection == tab ? Theme.Colors.accent : Theme.Colors.textSecondary)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("בית"))
    }
}

#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        VStack {
            Spacer()
            HomeBottomBar(selection: .constant(.home))
                .padding(Theme.Spacing.md)
        }
    }
    .environment(\.layoutDirection, .rightToLeft)
}
