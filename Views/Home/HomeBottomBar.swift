import SwiftUI

/// Floating bottom navigation bar with a centred, notched home button.
///
/// Visual structure:
///   * Pill-shaped glass bar across the bottom, with a circular cutout
///     at the top centre.
///   * The home button is a separate circle that sits *in* that cutout
///     — half embedded in the bar, half popping above it — so it reads
///     as the primary destination at a glance.
///   * Side icons (currently the transactions tab; placeholder slot
///     for future tabs on the other side) live inside the bar.
struct HomeBottomBar: View {
    enum Tab: Hashable {
        case home
        case transactions
        case analytics
        case calendar
    }

    @Binding var selection: Tab

    // Layout constants — kept as static so the FAB / HomeView can
    // reference the same heights when computing safe-area insets.
    static let barHeight: CGFloat = 60
    static let homeButtonDiameter: CGFloat = 60
    /// Slightly larger than the home-button radius so the notch leaves
    /// a small breathing gap around the button instead of clipping it.
    static let notchRadius: CGFloat = 36
    private static let cornerRadius: CGFloat = 30

    var body: some View {
        ZStack(alignment: .top) {
            // Glass-effect bar background. The shape itself defines
            // the notch — the iOS 26 `glassEffect(_:in:)` modifier
            // takes any InsettableShape, so the cutout shows through.
            Color.clear
                .frame(height: Self.barHeight)
                .glassEffect(
                    .regular,
                    in: NotchedBarShape(
                        notchRadius: Self.notchRadius,
                        cornerRadius: Self.cornerRadius
                    )
                )

            // Side icons sit inside the bar, flanking the notch.
            // The middle slot is intentionally empty — the home
            // button is overlaid on top, raised into the notch.
            HStack(spacing: 0) {
                HomeBarButton(
                    tab: .transactions,
                    symbol: "arrow.up.arrow.down",
                    accessibilityLabel: "תנועות",
                    selection: $selection
                )
                .frame(maxWidth: .infinity)

                // Reserve the notch's horizontal footprint so side
                // icons never crowd the home button visually.
                Color.clear
                    .frame(width: Self.notchRadius * 2)

                // Opposite flank holds the two "overview/planning" tabs —
                // analytics and the budget calendar — sharing the half so
                // every side icon uses the identical accent-when-selected
                // treatment.
                HStack(spacing: 0) {
                    HomeBarButton(
                        tab: .analytics,
                        symbol: "chart.line.uptrend.xyaxis",
                        accessibilityLabel: "תובנות",
                        selection: $selection
                    )
                    .frame(maxWidth: .infinity)

                    HomeBarButton(
                        tab: .calendar,
                        symbol: "calendar",
                        accessibilityLabel: "יומן התקציב",
                        selection: $selection
                    )
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: Self.barHeight)
            .padding(.horizontal, Theme.Spacing.lg)

            // The home button itself, raised so its centre sits on
            // the bar's top edge (half above, half embedded).
            HomeCenterButton(
                isSelected: selection == .home,
                action: { selection = .home }
            )
            .offset(y: -Self.homeButtonDiameter / 2)
        }
    }
}

// MARK: - Centre home button

/// The raised circular home button that sits in the bar's notch.
/// Kept separate from the bar's side icons because its look and size
/// don't match the small inline icons — it's the primary destination.
private struct HomeCenterButton: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "house.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Theme.Colors.accent)
                .frame(
                    width: HomeBottomBar.homeButtonDiameter,
                    height: HomeBottomBar.homeButtonDiameter
                )
                .background(
                    Circle().fill(isSelected ? Theme.Colors.accent : Theme.Colors.surface)
                )
                .overlay(
                    Circle().stroke(Theme.Colors.separator, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("בית"))
    }
}

// MARK: - Side icon

/// One tappable side item inside the bar. Highlights itself with the
/// brand accent when its tab is the active selection.
private struct HomeBarButton: View {
    let tab: HomeBottomBar.Tab
    let symbol: String
    let accessibilityLabel: LocalizedStringKey
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
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

// MARK: - Notched bar shape

/// Rounded-rectangle bar with a circular cutout on the top edge.
///
/// The cutout is a half-circle whose flat side aligns with the bar's
/// top, so a button centred on that edge sits half-embedded in the
/// bar. Conforms to `InsettableShape` so it works as the mask for
/// `glassEffect(_:in:)`.
struct NotchedBarShape: InsettableShape {
    var notchRadius: CGFloat = 36
    var cornerRadius: CGFloat = 30
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> NotchedBarShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        // Honour the insetAmount so `.stroke`-style insets render
        // correctly when the shape is reused as a stroke source.
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let cR = cornerRadius
        let nR = notchRadius
        let centerX = r.midX
        let topY = r.minY
        let bottomY = r.maxY
        let leftX = r.minX
        let rightX = r.maxX
        let notchStart = centerX - nR

        var path = Path()

        // Start just past the top-left corner and trace the boundary
        // clockwise so the interior fill stays on the correct side.
        path.move(to: CGPoint(x: leftX + cR, y: topY))

        // Top edge → notch start
        path.addLine(to: CGPoint(x: notchStart, y: topY))

        // Notch — semicircle dipping *into* the bar. In SwiftUI's
        // angle convention (clockwise from the +x axis), going from
        // 180° clockwise to 0° passes through 90° (south), which is
        // exactly the downward arc we want.
        path.addArc(
            center: CGPoint(x: centerX, y: topY),
            radius: nR,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: true
        )

        // Top edge from notch end → before the top-right corner
        path.addLine(to: CGPoint(x: rightX - cR, y: topY))

        // Top-right rounded corner (quad curve keeps things simple)
        path.addQuadCurve(
            to: CGPoint(x: rightX, y: topY + cR),
            control: CGPoint(x: rightX, y: topY)
        )

        // Right edge
        path.addLine(to: CGPoint(x: rightX, y: bottomY - cR))

        // Bottom-right corner
        path.addQuadCurve(
            to: CGPoint(x: rightX - cR, y: bottomY),
            control: CGPoint(x: rightX, y: bottomY)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: leftX + cR, y: bottomY))

        // Bottom-left corner
        path.addQuadCurve(
            to: CGPoint(x: leftX, y: bottomY - cR),
            control: CGPoint(x: leftX, y: bottomY)
        )

        // Left edge
        path.addLine(to: CGPoint(x: leftX, y: topY + cR))

        // Top-left corner — closes the loop back to the move-to point.
        path.addQuadCurve(
            to: CGPoint(x: leftX + cR, y: topY),
            control: CGPoint(x: leftX, y: topY)
        )

        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        VStack {
            Spacer()
            HomeBottomBar(selection: .constant(.home))
                .padding(.horizontal, Theme.Spacing.md)
                // Allowance for the home button popping above the bar
                .padding(.top, HomeBottomBar.homeButtonDiameter / 2)
                .padding(.bottom, Theme.Spacing.sm)
        }
    }
}
