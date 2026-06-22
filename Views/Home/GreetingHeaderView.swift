import SwiftUI

/// Top-of-dashboard greeting. Compact, two-line: a small muted "good
/// morning/afternoon/evening/night" in Hebrew, with the user's name
/// underneath in a medium-prominence weight.
///
/// Kept deliberately *not* hero-sized — the most prominent number on
/// the dashboard is the total balance, not the greeting.
struct GreetingHeaderView: View {
    let name: String

    var body: some View {
        // HStack auto-mirrors in RTL: in Hebrew the mascot ends up on
        // the right (where the eye lands first) and the greeting text
        // flows to its left.
        HStack(alignment: .center, spacing: Theme.Spacing.xxs) {
            Image("rat-mascot-wave")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 126)
                .accessibilityLabel(Text("עכבר עו״ש מקבל את פניך"))

            VStack(alignment: .leading) {
                Text("\(greetingText)\(name.isEmpty ? "" : ",")")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(Theme.Colors.textSecondary)

                if !name.isEmpty {
                    Text(name)
                        .font(Theme.Typography.screenTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Pull the row down past the parent VStack's `.lg` spacing so
        // the mascot visually *sits on* the AssetsSummaryCard — its
        // feet rest on the card's top edge with a few points of
        // overlap, instead of floating above it.
        .padding(.bottom, -(Theme.Spacing.lg + Theme.Spacing.sm))
        // Default sibling order in a VStack draws later children on
        // top; without this the card would cover the rat's feet at
        // the overlap. Lifting the greeting row's z-index makes the
        // mascot read as sitting *on* the card instead of behind it.
        .zIndex(1)
    }

    /// Hebrew greetings keyed to a coarse part-of-day split. Returned as
    /// a `Text` (not a `String`) so the literal stays a localisation key
    /// when interpolated into the composite greeting above.
    private var greetingText: Text {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return Text("בוקר טוב")          // morning
        case 12..<17: return Text("צוהריים טובים")     // afternoon
        case 17..<21: return Text("ערב טוב")          // evening
        default:      return Text("לילה טוב")          // night (21–04)
        }
    }
}

#Preview {
    GreetingHeaderView(name: "רותם")
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.background)
}
