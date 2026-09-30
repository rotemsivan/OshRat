import SwiftUI

/// What a returning user sees on launch, before the dashboard: the same brand
/// screen as the first-launch welcome, with one way in.
///
/// Not authentication — the data is on the device and never leaves it. It's a
/// front door, so opening the app starts on the brand rather than dropping
/// straight into the numbers. `ContentView` decides when to show it and
/// skips it when the app was opened to do something specific (the widget's
/// quick add, an Apple Pay payment).
struct LoginView: View {
    let onEnter: () -> Void

    @State private var isEntering = false

    var body: some View {
        BrandHeroLayout(subtitle: String(localized: "ניהול תקציב אישי, פשוט ופרטי.")) {
            HeroPrimaryButton("לחשבון שלי", isPressed: $isEntering, action: onEnter)
        }
    }
}

#Preview {
    LoginView(onEnter: {})
}
