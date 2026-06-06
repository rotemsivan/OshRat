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
        static let income        = Color(light: Color(hex: "2FA36B"), dark: Color(hex: "46C088"))
        static let expense       = Color(light: Color(hex: "E0654B"), dark: Color(hex: "F0775C"))
    }

    // MARK: Spacing (use these instead of magic numbers)
    enum Spacing {
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
    // Built on the system font with Dynamic Type, so it scales with the user's
    // accessibility text-size settings. The rounded design gives a friendly,
    // minimal feel — especially nice for the money figures.
    enum Typography {
        static let screenTitle  = Font.system(.largeTitle, design: .rounded).weight(.bold)
        static let sectionTitle = Font.system(.headline,   design: .rounded)
        static let amount       = Font.system(.title2,     design: .rounded).weight(.semibold)
        static let body         = Font.system(.body)
        static let caption      = Font.system(.caption)
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
    // Preview in Hebrew right-to-left, like the real app.
    .environment(\.layoutDirection, .rightToLeft)
}