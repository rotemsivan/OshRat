import SwiftUI

/// How tightly a portrait crops the rat.
///
/// Every framing is stated in its canvas's own coordinates, not nudged by
/// eye, so it holds at any diameter. The first three crop the bust
/// (400×520):
/// - `head` centres on the head (y 160) at zoom 1.75. The ears sit *above*
///   that centre, so they have to clear the circle's width at their own
///   height, which caps the zoom near 1.77 — 2.15 sheared both ears off.
/// - `headroom` is for a rat wearing a hat. A propeller hat's top reaches
///   y≈56 with blades spanning x≈130–270: at the `head` framing the circle is
///   only ~92 wide at that height and cuts the blades. Zoom 1.35 centred at
///   y 150 leaves ~228 of width there, so the whole hat fits — so do the
///   tallest hats since (the top hat reaches y≈27, the crown's points y≈40).
/// - `torso` is for an outfit tile. Outfits start under the chin (y≈290), so
///   either head framing shows little more than a collar. Zoom 1 centred at
///   y 280 is the whole width from the ear tips (y≈80) to y 480 — the rat is
///   still recognisably itself and the outfit fills the lower half. Meant
///   for square tiles; a circle would cut the shoulders.
///
/// The last two crop the full body (360×660), since the bust has no legs:
/// - `legs` is for pants: the waistband sits at y≈408 and the soles at ≈586,
///   and a skirt flares to x 94–266. Zoom 1.8 shows a 200-wide square, which
///   centred at y 495 holds all of that.
/// - `feet` is for shoes, which span y≈540–586: zoom 3 (a 120-wide square)
///   centred at y 560.
enum AvatarFraming {
    case head, headroom, torso, legs, feet

    /// The canvas this framing crops.
    var crop: AvatarCrop {
        switch self {
        case .head, .headroom, .torso: return .bust
        case .legs, .feet:             return .fullBody
        }
    }

    var zoom: CGFloat {
        switch self {
        case .head:     return 1.75
        case .headroom: return 1.35
        case .torso:    return 1
        case .legs:     return 1.8
        case .feet:     return 3
        }
    }

    /// The canvas y that lands on the portrait's centre.
    var centreY: CGFloat {
        switch self {
        case .head:     return 160
        case .headroom: return 150
        case .torso:    return 280
        case .legs:     return 495
        case .feet:     return 560
        }
    }
}

/// A drawing cropped to a circle-sized square around one part of the rat.
/// The caller supplies the drawing (`UserAvatar` or `AvatarLayers`, on the
/// framing's `crop`) and clips the result to whatever shape it wants.
struct AvatarPortrait<Content: View>: View {
    let diameter: CGFloat
    let framing: AvatarFraming
    @ViewBuilder let content: Content

    /// The canvas, so the frame can be stated in one dimension and stay true
    /// to the drawing.
    private var canvas: CGSize { framing.crop.canvasSize }

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
                        height: diameter * framing.zoom * canvas.height / canvas.width
                    )
                    // Shift the art so `centreY` sits on the frame's centre,
                    // from the art's own centre (half the canvas height).
                    .offset(y: (canvas.height / 2 - framing.centreY) / canvas.width * diameter * framing.zoom)
            }
            .clipped()
    }
}
