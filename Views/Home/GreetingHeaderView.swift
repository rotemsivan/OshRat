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
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            (greetingText + Text(verbatim: name.isEmpty ? "" : ","))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            if !name.isEmpty {
                Text(name)
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Hebrew greetings keyed to a coarse part-of-day split. Returned as
    /// a `Text` (not a `String`) so the literal stays a localisation key
    /// and the `+` operator above works without losing that property.
    private var greetingText: Text {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return Text("בוקר טוב")          // morning
        case 12..<17: return Text("צהריים טובים")     // afternoon
        case 17..<21: return Text("ערב טוב")          // evening
        default:      return Text("לילה טוב")          // night (21–04)
        }
    }
}

#Preview {
    GreetingHeaderView(name: "רותם")
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.background)
        .environment(\.layoutDirection, .rightToLeft)
}
