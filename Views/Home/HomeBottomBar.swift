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
    /// A budget line is scheduled for today and the user hasn't opened the
    /// calendar since — the calendar icon wears a small bell until they do.
    var calendarHasReminder: Bool = false

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
    fileprivate static let ratIconSize: CGFloat = 25

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
                            // `.topTrailing` mirrors under RTL to the visual
                            // top-left — where Hebrew iOS puts a tab badge.
                            .overlay(alignment: .topTrailing) {
                                if calendarHasReminder {
                                    ReminderBadge()
                                        .offset(x: 7, y: -6)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: calendarHasReminder)
                    }
                    .accessibilityValue(calendarHasReminder ? Text("יש פריט מתוכנן להיום") : Text(verbatim: ""))
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

/// The small bell on the calendar icon while a budget reminder is pending.
/// Filled accent disc with a surface-coloured ring, so it stays legible where
/// it overlaps the calendar glyph and over the glass bar in both appearances.
private struct ReminderBadge: View {
    var body: some View {
        Image(systemName: "bell.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 15, height: 15)
            .background(Circle().fill(Theme.Colors.expense))
            .overlay(Circle().strokeBorder(Theme.Colors.surface, lineWidth: 1.5))
            .accessibilityHidden(true)
    }
}

// MARK: - Rat head

/// The app's own tab icon: a rat seen from the side, crouching, nose to the
/// visual left, with its tail sweeping up over its back.
///
/// Hand-drawn because SF Symbols has no rat or mouse *animal* glyph (only
/// `computermouse`, plus `hare`, `pawprint` and `tortoise`), and none of
/// those say "עכבר עו״ש".
///
/// **A custom `Shape`'s coordinate space is mirrored under RTL** — confirmed
/// on device, not assumed: drawn nose-left it rendered facing right, off the
/// edge of the screen. The coordinates below are therefore pre-mirrored so it
/// faces left, into the bar and along the reading direction.
///
/// **Filled, not stroked.** Two earlier attempts drew it as line art to match
/// the SF Symbols beside it, and both failed at 21pt: the ear lobes merged
/// into the skull's outline, and the inner-ear detail that was supposed to
/// separate them read as a pair of eyes. A silhouette has no such problem,
/// and the bar already carries a filled mark in `house.fill`.
///
/// **Not a head at all, deliberately.** Any front-facing rodent head is two
/// lobes above a face, which is the Mickey silhouette — near enough to be
/// someone else's mark. Tilting the ears into ovals, dropping them to the
/// temples and lengthening the muzzle were all tried and all still read as
/// it; the lobes are the tell, not the face under them. A whole animal in
/// profile cannot make that shape, and the tail settles the species. The
/// candidates were drawn as SVG and rasterised side by side at icon size
/// first — a front-facing pass read as a cat, tall ears read as a rabbit, and
/// wide low ears read as a koala.
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

        // Body: a crouching rat seen from the side, nose at the visual left.
        //
        // Every subpath here is wound **clockwise**, checked by signed area
        // rather than by eye — `fill` uses the nonzero rule, so a subpath that
        // disagreed would cancel the overlap into a hole. The coordinates were
        // authored nose-left and then mirrored, which flips winding, so each
        // path is also traversed in reverse to put it back. That is why the
        // curves below read tail-first rather than nose-first.
        path.move(to: pt(99, 64))
        path.addCurve(to: pt(93, 69), control1: pt(100, 66), control2: pt(98, 67))
        path.addCurve(to: pt(53, 74), control1: pt(85, 73), control2: pt(67, 76))
        path.addCurve(to: pt(32, 60), control1: pt(41, 73), control2: pt(33, 68))
        path.addCurve(to: pt(45, 38), control1: pt(32, 52), control2: pt(36, 42))
        path.addCurve(to: pt(79, 44), control1: pt(54, 33), control2: pt(68, 36))
        path.addCurve(to: pt(99, 64), control1: pt(89, 47), control2: pt(97, 54))
        path.closeSubpath()

        // The tail, sweeping up and back over the rump. It is the one feature
        // that settles the animal outright, and it has to stay **thick** — at
        // 25pt a naturalistic thin tail aliases into a stray wisp, which a
        // side-by-side render at icon size made obvious.
        path.move(to: pt(38, 49))
        path.addCurve(to: pt(38, 55), control1: pt(38, 51), control2: pt(38, 52))
        path.addCurve(to: pt(17, 36), control1: pt(35, 42), control2: pt(26, 33))
        path.addCurve(to: pt(29, 76), control1: pt(8, 39), control2: pt(16, 58))
        path.addCurve(to: pt(11, 31), control1: pt(8, 63), control2: pt(0, 40))
        path.addCurve(to: pt(38, 49), control1: pt(20, 24), control2: pt(34, 33))
        path.closeSubpath()

        // One ear, sunk into the back of the skull so the two read as one
        // silhouette. A circle needs no mirroring, and the helper emits it
        // clockwise to match the two paths above.
        addEllipseClockwise(&path, centre: pt(71, 40),
                            radiusX: 9 * scale, radiusY: 10 * scale,
                            rotation: .degrees(0))

        return path
    }

    /// One ellipse, optionally tilted, traced left → top → right → bottom in
    /// its own rotated frame — i.e. clockwise on screen, matching the
    /// direction the skull above is wound.
    ///
    /// `Path.addEllipse` would be shorter but winds the other way and cannot
    /// tilt, and `fill` uses the nonzero rule: subpaths that disagree about
    /// direction cancel where they overlap, which would punch an ear-shaped
    /// hole through the head instead of merging with it. Rotation preserves
    /// orientation, so the tilt doesn't disturb that.
    private func addEllipseClockwise(
        _ path: inout Path,
        centre: CGPoint,
        radiusX: CGFloat,
        radiusY: CGFloat,
        rotation: Angle
    ) {
        // Standard cubic approximation of a quarter arc, per axis.
        let handleX = radiusX * 0.5522847
        let handleY = radiusY * 0.5522847
        let cosine = cos(rotation.radians)
        let sine = sin(rotation.radians)

        /// Ellipse-local coordinates → the shape's space: rotate about the
        /// centre, then translate onto it.
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: centre.x + x * cosine - y * sine,
                y: centre.y + x * sine + y * cosine
            )
        }

        path.move(to: point(-radiusX, 0))
        path.addCurve(
            to: point(0, -radiusY),
            control1: point(-radiusX, -handleY),
            control2: point(-handleX, -radiusY)
        )
        path.addCurve(
            to: point(radiusX, 0),
            control1: point(handleX, -radiusY),
            control2: point(radiusX, -handleY)
        )
        path.addCurve(
            to: point(0, radiusY),
            control1: point(radiusX, handleY),
            control2: point(handleX, radiusY)
        )
        path.addCurve(
            to: point(-radiusX, 0),
            control1: point(-handleX, radiusY),
            control2: point(-radiusX, handleY)
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
