import SwiftUI

/// Lets an in-app toast be flicked away before its hold runs out: it follows
/// the finger upward, and released past a short distance (or flung) it calls
/// `onDismiss`, which runs the toast's own exit from where the finger left
/// it. A drag downward only stretches a little and springs back — the toast
/// has nowhere to go but up, as a system banner does.
///
/// Shared by every toast in the app's one banner slot (`CelebrationToast`,
/// `BudgetReminderToast`, `XPGainToast`, `InAppNoticeToast`), so they all
/// answer the same gesture. Tap gestures on the toast still work: the drag
/// only begins after a few points of movement.
struct SwipeUpToDismiss: ViewModifier {
    /// Off while the toast is invisible (its entrance delay) or already leaving.
    let isEnabled: Bool
    /// Changes when the toast is reused for the next item in its queue, which
    /// puts a swiped-away offset back to zero.
    let resetID: AnyHashable
    let onDismiss: () -> Void

    @State private var drag: CGFloat = 0

    /// How far up a release has to be to count — or how far a fling would
    /// carry it.
    private static let distance: CGFloat = 24
    private static let flingDistance: CGFloat = 70

    func body(content: Content) -> some View {
        content
            .offset(y: drag)
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        let height = value.translation.height
                        // Upward follows the finger; downward resists.
                        drag = height < 0 ? height : height / 5
                    }
                    .onEnded { value in
                        if value.translation.height < -Self.distance
                            || value.predictedEndTranslation.height < -Self.flingDistance {
                            // Leave the offset where the finger let go; the
                            // toast's exit carries it the rest of the way.
                            onDismiss()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { drag = 0 }
                        }
                    },
                isEnabled: isEnabled
            )
            // VoiceOver has no swipe to find, so the same thing is an action.
            .accessibilityAction(named: Text("סגירה"), onDismiss)
            .onChange(of: resetID) { drag = 0 }
    }
}

extension View {
    func swipeUpToDismiss(isEnabled: Bool, resetID: AnyHashable, onDismiss: @escaping () -> Void) -> some View {
        modifier(SwipeUpToDismiss(isEnabled: isEnabled, resetID: resetID, onDismiss: onDismiss))
    }
}
