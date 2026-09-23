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
    enum Tab: String, Hashable {
        case home
        case transactions
        case analytics
        case calendar
        case profile
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

    /// Side of the rat icon's box. A shade under the SF Symbols beside it:
    /// the rat is a solid silhouette against their open line work, and equal
    /// sizes would read as a heavier icon rather than a matching one.
    fileprivate static let ratIconSize: CGFloat = 20

    /// Diameter of the floating "+" that hovers above the bar, and how far
    /// its bottom edge sits above the screen edge. `HomeView` positions the
    /// button from these, and the clearance below is derived from them, so
    /// the two can't drift apart.
    static let floatingButtonDiameter: CGFloat = 60
    static var floatingButtonBottomPadding: CGFloat {
        barHeight + homeButtonDiameter / 20 + Theme.Spacing.lg
    }

    /// How much of the screen bottom the bar itself covers, popped home button
    /// included. The floor for any scrolling screen.
    ///
    /// `HomeView` does install the bar as a `safeAreaInset`, but in practice
    /// that inset does **not** reach the scroll views inside the tab branches
    /// (each sits in its own `NavigationStack`, under a `ZStack` whose
    /// background ignores the safe area). Screens were measured assuming it
    /// did, and their last row ended up under the bar — so every figure here
    /// is a full clearance from the screen edge, assuming no help from the
    /// safe area at all.
    static var barClearance: CGFloat {
        barHeight + homeButtonDiameter / 2 + Theme.Spacing.sm
    }

    /// Bottom room for a screen whose **last element is interactive** — a
    /// button, or a row that has to stay tappable and swipeable. Clears the
    /// bar *and* the floating "+", which is an overlay that no safe area
    /// accounts for, plus a breath so the element stops just above the button
    /// rather than touching it.
    static var floatingButtonClearance: CGFloat {
        floatingButtonBottomPadding + floatingButtonDiameter + Theme.Spacing.md
    }

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

            // Side icons sit inside the bar, flanking the notch — two per
            // flank, so the notch stays visually centred between equal
            // groups. The middle slot is intentionally empty; the home
            // button is overlaid on top, raised into the notch.
            HStack(spacing: 0) {
                // Under RTL an HStack lays out from the *right*, so this
                // group is the visual right-hand flank and the rat is the
                // outermost icon on the screen's right edge.
                HStack(spacing: 0) {
                    HomeBarButton(
                        tab: .profile,
                        accessibilityLabel: "הפרופיל שלי",
                        selection: $selection
                    ) {
                        // Not an SF Symbol: there isn't one. The catalog has
                        // `computermouse`, `hare` and `pawprint` and no rat or
                        // mouse *animal* at all, so the app's own mark is
                        // drawn here. A bare `Shape` fills with the foreground
                        // style, so it picks up the button's accent-when-
                        // selected tint exactly as the symbols beside it do.
                        RatHeadShape()
                            .frame(width: Self.ratIconSize, height: Self.ratIconSize)
                    }
                    .frame(maxWidth: .infinity)

                    HomeBarButton(
                        tab: .transactions,
                        accessibilityLabel: "תנועות",
                        selection: $selection
                    ) {
                        BarSymbol("arrow.up.arrow.down")
                    }
                    .frame(maxWidth: .infinity)
                }
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
                        accessibilityLabel: "תובנות",
                        selection: $selection
                    ) {
                        BarSymbol("chart.line.uptrend.xyaxis")
                    }
                    .frame(maxWidth: .infinity)

                    HomeBarButton(
                        tab: .calendar,
                        accessibilityLabel: "יומן התקציב",
                        selection: $selection
                    ) {
                        BarSymbol("calendar")
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: Self.barHeight)
            // Four icons per bar instead of three, so the gutter tightens to
            // keep the outermost ones off the bar's rounded corners.
            .padding(.horizontal, Theme.Spacing.md)

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
///
/// Generic over its icon rather than taking a symbol name, because one of
/// the four isn't a symbol — see the rat in `HomeBottomBar`. The tint is
/// applied to the *container*, so an `Image(systemName:)` and a bare `Shape`
/// (which fills with the foreground style by default) colour identically and
/// neither call site has to remember to do it.
private struct HomeBarButton<Icon: View>: View {
    let tab: HomeBottomBar.Tab
    let accessibilityLabel: LocalizedStringKey
    @Binding var selection: HomeBottomBar.Tab
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button {
            selection = tab
        } label: {
            icon()
                .frame(width: 48, height: 48)
                .foregroundStyle(selection == tab ? Theme.Colors.accent : Theme.Colors.textSecondary)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

/// An SF Symbol at the bar's icon size. A named view so the three symbol
/// tabs can't drift apart from each other typographically.
private struct BarSymbol: View {
    let name: String

    init(_ name: String) { self.name = name }

    var body: some View {
        Image(systemName: name)
            .font(Theme.Typography.sectionTitle)
    }
}

// MARK: - Rat head

/// The app's own tab icon: a front-facing rat head — round skull, two big
/// ears, a tapering snout.
///
/// Hand-drawn because SF Symbols has no rat or mouse *animal* glyph (only
/// `computermouse`, plus `hare`, `pawprint` and `tortoise`), and none of
/// those say "עכבר עו״ש". Drawn **symmetrically** on purpose: a symmetric
/// path is immune to the RTL question of whether a custom `Shape`'s
/// coordinate space is mirrored, so the icon looks identical either way.
///
/// **Filled, not stroked.** Two earlier attempts drew it as line art to match
/// the SF Symbols beside it, and both failed at 21pt: the ear lobes merged
/// into the skull's outline, and the inner-ear detail that was supposed to
/// separate them read as a pair of eyes. A silhouette has no such problem —
/// two circles clear of a tapered head is the most legible mouse there is,
/// and the bar already carries a filled mark in `house.fill`.
///
/// The geometry is authored against a 100×100 box and scaled uniformly into
/// whatever frame it's given, so the proportions survive Dynamic Type and a
/// larger rendering (a wardrobe screen, say) needs no second set of numbers.
struct RatHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / 100
        let originX = rect.midX - side / 2
        let originY = rect.midY - side / 2

        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * scale, y: originY + y * scale)
        }

        var path = Path()

        // Ears: two plain circles, set high and wide enough that they clear
        // the skull entirely at their own centre line. That gap is what makes
        // the thing a mouse — overlap them into the crown and it goes back to
        // reading as one bumpy dome.
        for centreX in [26.0, 74.0] as [CGFloat] {
            addCircleClockwise(&path, centre: pt(centreX, 25), radius: 19 * scale)
        }

        // Skull: broad across the brow, drawn out into a long wedge of a
        // snout. Its top sits well below the ears, so they join it low down
        // where it's wide.
        //
        // The snout is doing real work. Two circles on a round head is the
        // Mickey silhouette, near enough to be somebody else's mark; a rat is
        // the one with the long pointed muzzle, and lengthening it both says
        // "rat" and puts clear water between the two.
        path.move(to: pt(16, 56))
        path.addCurve(to: pt(50, 37), control1: pt(16, 44), control2: pt(31, 37))
        path.addCurve(to: pt(84, 56), control1: pt(69, 37), control2: pt(84, 44))
        path.addCurve(to: pt(50, 99), control1: pt(84, 76), control2: pt(63, 99))
        path.addCurve(to: pt(16, 56), control1: pt(37, 99), control2: pt(16, 76))
        path.closeSubpath()

        return path
    }

    /// One circle traced left → top → right → bottom, i.e. clockwise on
    /// screen, matching the direction the skull above is wound.
    ///
    /// `Path.addEllipse` would be shorter but winds the other way, and `fill`
    /// uses the nonzero rule: subpaths that disagree about direction cancel
    /// where they overlap, which would punch an ear-shaped hole through the
    /// head instead of merging with it.
    private func addCircleClockwise(_ path: inout Path, centre: CGPoint, radius: CGFloat) {
        // Standard cubic approximation of a quarter circle.
        let handle = radius * 0.5522847
        let x = centre.x
        let y = centre.y

        path.move(to: CGPoint(x: x - radius, y: y))
        path.addCurve(
            to: CGPoint(x: x, y: y - radius),
            control1: CGPoint(x: x - radius, y: y - handle),
            control2: CGPoint(x: x - handle, y: y - radius)
        )
        path.addCurve(
            to: CGPoint(x: x + radius, y: y),
            control1: CGPoint(x: x + handle, y: y - radius),
            control2: CGPoint(x: x + radius, y: y - handle)
        )
        path.addCurve(
            to: CGPoint(x: x, y: y + radius),
            control1: CGPoint(x: x + radius, y: y + handle),
            control2: CGPoint(x: x + handle, y: y + radius)
        )
        path.addCurve(
            to: CGPoint(x: x - radius, y: y),
            control1: CGPoint(x: x - handle, y: y + radius),
            control2: CGPoint(x: x - radius, y: y + handle)
        )
        path.closeSubpath()
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
