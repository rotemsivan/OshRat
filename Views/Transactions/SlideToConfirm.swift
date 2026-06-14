import SwiftUI

/// "Slide to confirm" control, in the spirit of the iPhone slide-to-answer
/// pill.
///
/// The user drags a thumb across a track; once the thumb reaches the far
/// edge the control fires `onConfirm` and the thumb stays anchored there
/// so the user gets a "snap" of completion. Below the threshold the thumb
/// springs back to its starting position.
///
/// RTL aware: in Hebrew the thumb starts on the right and the drag is to
/// the left. We read `\.layoutDirection` and flip the gesture sign so the
/// visual "swipe in the natural reading direction" works in both LTR and
/// RTL.
///
/// `isEnabled` greys the control out — the gesture still works at a low
/// level (we want the user to feel the resistance) but doesn't trigger
/// the confirm callback. The colour cues and the disabled state come from
/// the design system to stay consistent with the rest of the app.
struct SlideToConfirm: View {
    let label: String
    let isEnabled: Bool
    let onConfirm: () -> Void

    @Environment(\.layoutDirection) private var layoutDirection

    @State private var dragOffset: CGFloat = 0
    @State private var isConfirmed: Bool = false

    /// Pixels we need the thumb to travel before counting as "confirmed".
    /// 90% of the track keeps the threshold tight while still tolerating
    /// users who overshoot or undershoot by a few points.
    private static let confirmRatio: CGFloat = 0.9
    private static let height: CGFloat = 60
    private static let thumbInset: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let trackWidth = geo.size.width
            let thumbSize = Self.height - Self.thumbInset * 2
            let maxOffset = trackWidth - thumbSize - Self.thumbInset * 2

            ZStack(alignment: .leading) {
                track(trackWidth: trackWidth)

                // The label fades as the thumb gets closer to the end —
                // the closer the user is to confirming, the less the
                // label "competes" with the thumb visually.
                Text(label)
                    .font(Theme.Typography.amount)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .opacity(labelOpacity(for: dragOffset, max: maxOffset))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .allowsHitTesting(false)

                thumb(thumbSize: thumbSize)
                    .offset(x: visibleOffset(maxOffset: maxOffset))
                    .gesture(dragGesture(maxOffset: maxOffset))
            }
            .frame(width: trackWidth, height: Self.height)
        }
        .frame(height: Self.height)
        .opacity(isEnabled ? 1 : 0.5)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isConfirmed)
    }

    // MARK: - Pieces

    private func track(trackWidth: CGFloat) -> some View {
        Capsule()
            .fill(Theme.Colors.surface)
            .overlay(
                Capsule().stroke(Theme.Colors.separator, lineWidth: 1)
            )
            // Progress fill that grows toward the thumb so the user sees
            // how far they've travelled. Inset to sit inside the stroke.
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Theme.Colors.accent.opacity(0.18))
                    .frame(width: max(Self.height, abs(dragOffset) + Self.height))
                    .padding(Self.thumbInset)
            }
            .clipShape(Capsule())
    }

    private func thumb(thumbSize: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.accent)
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            Image(systemName: isConfirmed ? "checkmark" : thumbSymbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: thumbSize, height: thumbSize)
        .padding(Self.thumbInset)
    }

    /// Direction-sensitive thumb arrow. In LTR the arrow points right
    /// (drag right to confirm); in RTL it points left.
    private var thumbSymbol: String {
        layoutDirection == .rightToLeft ? "chevron.left" : "chevron.right"
    }

    // MARK: - Gesture

    private func dragGesture(maxOffset: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEnabled, !isConfirmed else { return }
                // In RTL the user drags leftwards (negative translation)
                // to reveal "progress" — flip the sign so the rest of the
                // math stays direction-agnostic.
                let raw = layoutDirection == .rightToLeft
                    ? -value.translation.width
                    : value.translation.width
                dragOffset = min(max(0, raw), maxOffset)
            }
            .onEnded { _ in
                guard isEnabled else {
                    springBack()
                    return
                }
                if dragOffset >= maxOffset * Self.confirmRatio {
                    // Snap to the end and fire — the small spring still
                    // happens via the implicit animation on `dragOffset`.
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        dragOffset = maxOffset
                        isConfirmed = true
                    }
                    onConfirm()
                } else {
                    springBack()
                }
            }
    }

    private func springBack() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
            dragOffset = 0
        }
    }

    /// The thumb is laid out with `.leading` alignment, but in RTL the
    /// system mirrors that to the visual right edge. We always store
    /// `dragOffset` as a positive number; in RTL we negate it so the
    /// visual motion goes from the (mirrored) leading edge inward.
    private func visibleOffset(maxOffset _: CGFloat) -> CGFloat {
        layoutDirection == .rightToLeft ? -dragOffset : dragOffset
    }

    private func labelOpacity(for offset: CGFloat, max: CGFloat) -> Double {
        guard max > 0 else { return 1 }
        let progress = Double(offset / max)
        return Swift.max(0, 1 - progress * 1.4)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.lg) {
        SlideToConfirm(
            label: "החליקו לאישור התנועה",
            isEnabled: true,
            onConfirm: {}
        )
        SlideToConfirm(
            label: "לא ניתן לאשר",
            isEnabled: false,
            onConfirm: {}
        )
    }
    .padding()
    .background(Theme.Colors.background)
    .environment(\.layoutDirection, .rightToLeft)
}
