//
//  Theme.swift
//  OshRat
//
//  Created by Rotem Sivan on 04/06/2026.
//


import SwiftUI

// MARK: - Design system for עכבר עו״ש
// One place for colours, fonts, spacing, and the card look, so every screen
// stays consistent. Use it like: Theme.Colors.accent, Theme.Typography.amount,
// Theme.Spacing.md, and the .cardStyle() modifier.
//
// The palette adapts to light and dark mode on its own.
// Rat-themed touches: a warm "cheese" gold accent, and a deep "graphite" grey.

enum Theme {

    // MARK: Colours
    enum Colors {
        /// App background — a soft, warm off-white (dark: near-black).
        static let background    = Color(light: Color(hex: "F6F5F2"), dark: Color(hex: "15151A"))
        /// Card / surface colour that sits on top of the background.
        static let surface       = Color(light: Color(hex: "FFFFFF"), dark: Color(hex: "1F1F26"))
        /// Main text.
        static let textPrimary   = Color(light: Color(hex: "1F1F24"), dark: Color(hex: "F2F2F4"))
        /// Muted text for labels and captions.
        static let textSecondary = Color(light: Color(hex: "7A7A82"), dark: Color(hex: "9A9AA2"))
        /// Hairline dividers.
        static let separator     = Color(light: Color(hex: "E7E6E2"), dark: Color(hex: "2C2C34"))

        /// Brand accent — a deep teal blue (#006699) that reads as calm,
        /// trustworthy, and financial. The dark-mode variant lightens
        /// and saturates the same hue so it stays legible on the
        /// near-black surface without losing its brand identity.
        static let accent        = Color(light: Color(hex: "006699"), dark: Color(hex: "2BA0C7"))
        /// Deep graphite — the "rat" neutral, good for strong headers or a dark brand element.
        static let graphite      = Color(light: Color(hex: "3B3B45"), dark: Color(hex: "C9C9D2"))

        /// Semantic money colours.
        ///
        /// `expense` is the warm-red "out of pocket" colour, used for
        /// expense totals on the monthly summary *and* for the "needs"
        /// row in the budget breakdown — the things you *have* to pay
        /// every month. `wants` is a separate, calmer orange used only
        /// for the discretionary "wants" row, so needs and wants read
        /// as two distinct categories on the same screen.
        static let income        = Color(light: Color(hex: "2FA36B"), dark: Color(hex: "46C088"))
        static let expense       = Color(light: Color(hex: "E0654B"), dark: Color(hex: "F0775C"))
        static let wants         = Color(light: Color(hex: "F58220"), dark: Color(hex: "F89F47"))
    }

    // MARK: Spacing (use these instead of magic numbers)
    enum Spacing {
        static let xxs: CGFloat = 1
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: Corner radius
    enum Radius {
        static let card: CGFloat = 16
        static let button: CGFloat = 12
    }

    // MARK: Typography
    // The app's primary typeface is Heebo — a Hebrew-first humanist sans that
    // pairs naturally with Latin text. The font files live in the app bundle
    // (Fonts/) and are registered automatically by iOS via the `UIAppFonts`
    // entry in Info.plist. Sizes are paired with the standard Dynamic Type
    // text styles via `relativeTo:` so they still scale with the user's
    // accessibility text-size settings.
    enum Typography {
        static let screenTitle  = Font.custom(Fonts.bold,    size: 28, relativeTo: .largeTitle)
        static let sectionTitle = Font.custom(Fonts.bold,    size: 22, relativeTo: .headline)
        static let amount       = Font.custom(Fonts.bold,    size: 18, relativeTo: .title2)
        static let body         = Font.custom(Fonts.regular, size: 17, relativeTo: .body)
        /// A step below `body` for dense secondary content, e.g. the note and
        /// insight lines inside the expanded transaction card.
        static let bodySmall    = Font.custom(Fonts.regular, size: 14, relativeTo: .subheadline)
        static let caption      = Font.custom(Fonts.regular, size: 13, relativeTo: .caption)
        /// ~15% smaller than `caption`, for tight secondary text like the
        /// filename on an attachment tile. Still scales with Dynamic Type.
        static let captionSmall = Font.custom(Fonts.regular, size: 11, relativeTo: .caption2)
    }

    // MARK: Fonts
    // PostScript names for the Heebo family. SwiftUI's `Font.custom` looks
    // fonts up by PostScript name, not by file name — these match the
    // PostScript names baked into the .ttf files in `Fonts/`.
    enum Fonts {
        static let regular = "Heebo-Regular"
        static let bold    = "Heebo-Bold"

        /// UIFont helpers, used by the UIKit appearance proxies below.
        /// Falls back to the system font if the custom font fails to load,
        /// so the app never ships with empty rectangles.
        static func uiRegular(_ size: CGFloat) -> UIFont {
            UIFont(name: regular, size: size) ?? .systemFont(ofSize: size)
        }
        static func uiBold(_ size: CGFloat) -> UIFont {
            UIFont(name: bold, size: size) ?? .boldSystemFont(ofSize: size)
        }

        /// Dynamic-Type-aware variants for the UIKit-backed inputs
        /// (`UITextField` / `UITextView`). The SwiftUI `Text` tokens above
        /// scale via `relativeTo:`, but a plain `UIFont(name:size:)` is
        /// frozen — so we scale the base size against a text style here.
        /// Pair with `adjustsFontForContentSizeCategory = true` on the view
        /// so it also tracks live changes to the user's text-size setting.
        static func uiRegularScaled(_ size: CGFloat, style: UIFont.TextStyle = .body) -> UIFont {
            UIFontMetrics(forTextStyle: style).scaledFont(for: uiRegular(size))
        }
        static func uiBoldScaled(_ size: CGFloat, style: UIFont.TextStyle = .body) -> UIFont {
            UIFontMetrics(forTextStyle: style).scaledFont(for: uiBold(size))
        }
    }

    // MARK: Global UIKit appearance
    // SwiftUI's `.font(...)` modifier propagates to most `Text` views but
    // *doesn't* reach into UIKit-backed chrome — navigation bars, tab bars,
    // text fields, segmented pickers, alert buttons, etc. Those pull their
    // font from UIKit appearance proxies, so we set them here once at launch.
    static func applyGlobalAppearance() {
        // Navigation bar: large title + inline title + back-button text.
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithDefaultBackground()
        navAppearance.titleTextAttributes = [
            .font: Fonts.uiBold(17)
        ]
        navAppearance.largeTitleTextAttributes = [
            .font: Fonts.uiBold(34)
        ]
        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance   = navAppearance
        navBar.scrollEdgeAppearance = navAppearance
        navBar.compactAppearance    = navAppearance

        // Bar button items (toolbar buttons, nav-bar buttons).
        let barButton = UIBarButtonItem.appearance()
        let buttonFont: [NSAttributedString.Key: Any] = [.font: Fonts.uiRegular(17)]
        barButton.setTitleTextAttributes(buttonFont, for: .normal)
        barButton.setTitleTextAttributes(buttonFont, for: .highlighted)
        barButton.setTitleTextAttributes(buttonFont, for: .disabled)

        // Tab bar item labels.
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithDefaultBackground()
        let tabItemFont: [NSAttributedString.Key: Any] = [.font: Fonts.uiRegular(10)]
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes   = tabItemFont
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = tabItemFont
        tabAppearance.inlineLayoutAppearance.normal.titleTextAttributes    = tabItemFont
        tabAppearance.inlineLayoutAppearance.selected.titleTextAttributes  = tabItemFont
        tabAppearance.compactInlineLayoutAppearance.normal.titleTextAttributes   = tabItemFont
        tabAppearance.compactInlineLayoutAppearance.selected.titleTextAttributes = tabItemFont
        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance   = tabAppearance
        tabBar.scrollEdgeAppearance = tabAppearance

        // Note: we deliberately do *not* set `UITextField.appearance().font`.
        // Pushing a font through the UITextField appearance proxy interferes
        // with SwiftUI's `TextField` rendering inside `Form` — characters
        // typed by the user stop showing up live. SwiftUI's environment
        // `.font(...)` on the root view already propagates Heebo to every
        // `TextField` / `SecureField`, which is enough.

        // Segmented `Picker`.
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.font: Fonts.uiRegular(13)], for: .normal
        )
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.font: Fonts.uiRegular(13)], for: .selected
        )
    }
}

// MARK: - Tap-anywhere to dismiss the keyboard
// SwiftUI doesn't ship a built-in "tap outside to close the keyboard"
// behaviour, but Hebrew users coming in from the iOS norm expect it on
// every input (transaction title, account name, amount, etc.). We
// install a single `UITapGestureRecognizer` on the app's key window so
// any tap that isn't on a text input ends editing — no per-screen
// boilerplate, no fragile background `.onTapGesture` overlays.
//
// Two flags make this safe:
//   • `cancelsTouchesInView = false` — the underlying view still gets the
//     touch, so buttons, list rows, pickers, and slide-to-confirm all
//     keep working. The recognizer just *additionally* fires
//     `endEditing(_:)` on the window.
//   • A delegate that refuses touches landing on a `UITextField` /
//     `UITextView` (or any subview of one). Without this, tapping a
//     field would focus it AND immediately resign first responder,
//     dismissing the very keyboard the user wanted to open.
//
// `KeyboardDismissTapInstaller` is held by a single static reference
// because `UIGestureRecognizer.delegate` is weak — without the strong
// reference the delegate would deallocate on the next runloop tick and
// the gesture would silently stop firing.
final class KeyboardDismissTapInstaller: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissTapInstaller()
    private var installed = false

    /// Idempotent. Safe to call from `.onAppear` — it will look up the
    /// current key window and attach the gesture once.
    func install() {
        guard !installed else { return }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow }) else { return }

        let tap = UITapGestureRecognizer(target: window, action: #selector(UIView.endEditing(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
        installed = true
    }

    // Walk up the view tree so a tap on the inner scroll view / label
    // inside a `UITextView` is still recognised as "on the text input".
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let v = view {
            if v is UITextField || v is UITextView || v is UISearchBar { return false }
            view = v.superview
        }
        return true
    }

    // Let SwiftUI's own gestures (taps on buttons, scroll, swipe-to-go-back)
    // run alongside ours. We're only listening, never consuming.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

// MARK: - Reusable card style
// Apply to any view to give it the standard card look: padding, surface colour,
// rounded corners, and a soft shadow. Usage:  SomeView().cardStyle()
private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}

// MARK: - Colour helpers

extension Color {
    /// Create a colour from a 6-digit hex string like "F6F5F2" (with or without "#").
    init(hex: String) {
        let cleaned = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// A colour that automatically switches between light and dark appearance.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

// MARK: - Live preview (open this file to see the theme in the canvas)
#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()

        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("עכבר עו״ש")
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)

            // Example "balance" card using the design system.
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("יתרה כוללת")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Text("₪ 12,480")
                    .font(Theme.Typography.amount)
                    .foregroundStyle(Theme.Colors.textPrimary)

                HStack(spacing: Theme.Spacing.lg) {
                    Label("3,200", systemImage: "arrow.down.left")
                        .foregroundStyle(Theme.Colors.income)
                    Label("1,750", systemImage: "arrow.up.right")
                        .foregroundStyle(Theme.Colors.expense)
                }
                .font(Theme.Typography.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .padding(Theme.Spacing.lg)
    }
}
