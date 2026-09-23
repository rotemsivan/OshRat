import SwiftUI

/// How tightly a portrait crops the bust.
///
/// Both framings are stated in the bust SVG's own coordinates (400×520), not
/// nudged by eye, so they hold at any diameter:
/// - `head` centres on the head (y 160) at zoom 1.75. The ears sit *above*
///   that centre, so they have to clear the circle's width at their own
///   height, which caps the zoom near 1.77 — 2.15 sheared both ears off.
/// - `headroom` is for a rat wearing a hat. A propeller hat's top reaches
///   y≈56 with blades spanning x≈130–270: at the `head` framing the circle is
///   only ~92 wide at that height and cuts the blades. Zoom 1.35 centred at
///   y 150 leaves ~228 of width there, so the whole hat fits.
enum AvatarFraming {
    case head, headroom

    var zoom: CGFloat {
        switch self {
        case .head:     return 1.75
        case .headroom: return 1.35
        }
    }

    /// The bust-canvas y (out of 520) that lands on the portrait's centre.
    var centreY: CGFloat {
        switch self {
        case .head:     return 160
        case .headroom: return 150
        }
    }
}

/// A bust drawing cropped to a circle-sized square around the head. The
/// caller supplies the drawing (`UserAvatar` or `AvatarLayers`) and clips the
/// result to whatever shape it wants.
struct AvatarPortrait<Content: View>: View {
    let diameter: CGFloat
    let framing: AvatarFraming
    @ViewBuilder let content: Content

    /// The bust art's own proportions, so the frame can be stated in one
    /// dimension and stay true to the drawing.
    private static var artAspect: CGFloat { 520 / 400 }

    var body: some View {
        Color.clear
            .frame(width: diameter, height: diameter)
            .overlay {
                content
                    // **Both** dimensions, deliberately. With only a width,
                    // the height proposal falls through from the frame, and
                    // a portrait image then fits *that* — the picture comes
                    // out a third of the intended width.
                    .frame(
                        width: diameter * framing.zoom,
                        height: diameter * framing.zoom * Self.artAspect
                    )
                    // Shift the art so `centreY` sits on the frame's centre:
                    // the art's own centre is y 260 of 520.
                    .offset(y: (260 - framing.centreY) / 400 * diameter * framing.zoom)
            }
            .clipped()
    }
}
