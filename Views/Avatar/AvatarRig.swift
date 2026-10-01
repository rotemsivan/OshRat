import SwiftUI

/// How the Bare rat's limbs are turned: one angle per arm and leg, in
/// degrees, each about its own joint (`AvatarCrop.armPivot` / `legPivot`).
/// Zero is the drawing's rest position, arms hanging and legs straight.
///
/// Positive is **clockwise on screen**. So a raised *right* arm (the one on
/// the canvas's right) is negative and a raised left arm positive, and a
/// positive left leg kicks out to the left.
///
/// A plain value of numbers so `KeyframeAnimator` can drive it: the
/// wardrobe and the greeting animate a rig directly, everything else asks for
/// a named `AvatarPose`.
struct AvatarRig: Equatable {
    var leftArm: Double = 0
    var rightArm: Double = 0
    var leftLeg: Double = 0
    var rightLeg: Double = 0

    static let rest = AvatarRig()

    func arm(_ side: LimbSide) -> Angle {
        .degrees(side == .left ? leftArm : rightArm)
    }

    func leg(_ side: LimbSide) -> Angle {
        .degrees(side == .left ? leftLeg : rightLeg)
    }

    /// An animated wave as Reduce Motion should see it: the still wave pose
    /// while the arm is more than halfway up, the rest pose otherwise. The
    /// keyframes still run; only what's drawn from them stops moving.
    var steppedToWave: AvatarRig {
        rightArm < -60 ? AvatarPose.wave.rig : .rest
    }
}

/// The rat's named poses — a set of limb angles each, not a drawing each.
///
/// They used to be separate drawings with the arm painted in, which is why a
/// sleeve (cut once, for an arm at rest) could never follow a wave. Now the
/// arm is a part turned about the shoulder and the sleeve is drawn inside the
/// same group, so every pose works in every outfit. The price is the hand:
/// a raised arm ends in the resting paw, not a drawn thumb or open fingers.
///
/// The angles keep the hand on the canvas in both crops — the bust is only
/// 400 wide, and a lower right arm swings out past its edge.
enum AvatarPose {
    case base, wave, present, thumbsup, confident, cheer

    var rig: AvatarRig {
        switch self {
        case .base:      return .rest
        case .wave:      return AvatarRig(rightArm: -135)
        case .present:   return AvatarRig(rightArm: -125)
        case .thumbsup:  return AvatarRig(rightArm: -145)
        case .confident: return AvatarRig(leftArm: 10, rightArm: -40)
        case .cheer:     return AvatarRig(leftArm: 135, rightArm: -135, leftLeg: 6, rightLeg: -6)
        }
    }
}

extension MascotMood {
    /// The body language that goes with the face, on the bust: arms in a
    /// little for worry and sadness, out at the sides for anger, up for joy.
    var rig: AvatarRig {
        switch self {
        case .calm:    return .rest
        case .happy:   return AvatarPose.cheer.rig
        case .worried: return AvatarRig(leftArm: -6, rightArm: 6)
        case .sad:     return AvatarRig(leftArm: -10, rightArm: 10)
        case .angry:   return AvatarRig(leftArm: 22, rightArm: -22)
        }
    }
}

extension AvatarCrop {
    /// The art's canvas, as the asset-name suffix.
    var canvas: AvatarCanvas {
        switch self {
        case .bust:     return .bust
        case .fullBody: return .full
        }
    }

    /// The canvas in its own units — every pivot below is stated in these.
    var canvasSize: CGSize {
        switch self {
        case .bust:     return CGSize(width: 400, height: 520)
        case .fullBody: return CGSize(width: 360, height: 660)
        }
    }

    /// The asset-name stem of the Bare rat's parts on this canvas.
    var rigPrefix: String {
        switch self {
        case .bust:     return "bare-bust-rig"
        case .fullBody: return "bare-fullbody-rig"
        }
    }

    /// The shoulder: the middle of the arm drawing's top edge, where it meets
    /// the body. A pivot any higher looks more like a shoulder on paper but
    /// swings the arm's end clear of the torso, leaving a gap.
    func armPivot(_ side: LimbSide) -> UnitPoint {
        switch (self, side) {
        case (.bust, .left):      return unit(143, 358)
        case (.bust, .right):     return unit(257, 358)
        case (.fullBody, .left):  return unit(134, 276)
        case (.fullBody, .right): return unit(226, 276)
        }
    }

    /// The hip, as the art pack specifies it. Only the full body has legs.
    func legPivot(_ side: LimbSide) -> UnitPoint {
        side == .left ? unit(166, 444) : unit(194, 444)
    }

    private func unit(_ x: CGFloat, _ y: CGFloat) -> UnitPoint {
        UnitPoint(x: x / canvasSize.width, y: y / canvasSize.height)
    }
}
