import SwiftUI

/// The very first screen a brand-new user sees. It's deliberately calm:
/// a logo-ish symbol, the app name, a one-sentence pitch, and a single
/// primary call-to-action that hands off to the setup wizard.
///
/// Note on text: SwiftUI's `Text(_:)` initialiser takes a `LocalizedStringKey`,
/// so the Hebrew literals below double as localisation keys. When we add
/// a String Catalog later, the call sites won't have to change.
struct WelcomeView: View {

    /// Called when the user taps the primary button. The parent decides
    /// what "start" means (here: replace this screen with the wizard).
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Hero — a simple SF Symbol stands in for the (future) mascot.
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 96, weight: .regular))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("עכבר עו״ש")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text("ניהול תקציב אישי, פשוט ופרטי.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // A short intro that sets expectations: this is a manual,
            // privacy-first app — the user owns every number in it.
            Text("היישום עוזר לעקוב אחר הכספים שלך מבלי להתחבר לבנקים או לכרטיסי אשראי. הכול נשאר במכשיר שלך, ואתה זה שמחליט מה להוסיף ומתי לעדכן.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Spacer()

            Button(action: onStart) {
                Text("בוא נתחיל")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
    }
}

#Preview {
    WelcomeView(onStart: {})
        .environment(\.layoutDirection, .rightToLeft)
}
