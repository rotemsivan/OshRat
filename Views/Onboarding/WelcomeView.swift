import SwiftUI

/// First-launch hero screen.
///
/// Reads from the design system end-to-end: the brand accent backs the
/// hero icon, `screenTitle` typography sets the app name, and the
/// primary CTA picks up `Colors.accent` via the screen-wide tint.
struct WelcomeView: View {
    let onStart: () -> Void

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 96, weight: .regular))
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityHidden(true)

                VStack(alignment: .trailing, spacing: Theme.Spacing.sm) {
                    Text("עכבר עו״ש")
                        .font(Theme.Typography.screenTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    Text("ניהול תקציב אישי, פשוט ופרטי.")
                        .font(Theme.Typography.sectionTitle)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Text("היישום עוזר לעקוב אחר הכספים שלך מבלי להתחבר לבנקים או לכרטיסי אשראי. הכול נשאר במכשיר שלך, ואתה זה שמחליט מה להוסיף ומתי לעדכן.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Spacer()

                Button(action: onStart) {
                    Text("בוא נתחיל")
                        .font(Theme.Typography.sectionTitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.Colors.accent)
            }
            .padding(Theme.Spacing.lg)
        }
    }
}

#Preview {
    WelcomeView(onStart: {})
        .environment(\.layoutDirection, .rightToLeft)
}
