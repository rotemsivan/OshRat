import SwiftUI

/// Every waiting card payment, in one sheet that stays up until the line is
/// done.
///
/// It used to be a sheet per payment: each save or cancel closed it and the
/// next one slid up a moment later, and in that gap the dashboard showed the
/// XP just earned — so a cancel looked as if it had paid points. Now one
/// presentation walks the queue: saving or cancelling a payment swaps in the
/// next (`NewTransactionSheet(payment:queueStep:)`), "תשלום 2 מתוך 5" says
/// where you are, and the sheet closes only after the last one — when the XP
/// for the whole batch shows once, together.
///
/// "ביטול" discards the payment on screen and moves on; "דילוג" keeps it for
/// later — parked in the router, counted in the transactions list, deleted
/// if it's still there after `PaymentPrefill.freshness`. Swiping the sheet
/// away instead means "later": the payment on screen goes back to the front
/// of the line with the others, and `HomeView` leaves the line alone until a
/// new payment arrives or the app comes back to the front.
struct PaymentQueueSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var current: PaymentPrefill
    /// Payments already dealt with in this sheet — saved, cancelled or
    /// logged by "רישום כולם". Drives "תשלום N מתוך M".
    @State private var handled = 0
    /// Set when the line ran out, so closing doesn't put anything back.
    @State private var isFinished = false

    private let router = IncomingPaymentRouter.shared

    init(first: PaymentPrefill) {
        _current = State(initialValue: first)
    }

    var body: some View {
        ZStack {
            NewTransactionSheet(
                payment: current,
                queueStep: PaymentQueueStep(
                    position: handled + 1,
                    total: handled + 1 + router.waitingCount,
                    onFinish: advance,
                    onSkip: skip,
                    onLoggedOthers: recordLogged
                )
            )
            // A fresh form per payment: its fields, glow and banner state
            // start over rather than carrying the last payment's edits.
            .id(current.id)
            .transition(stepTransition)
        }
        .onDisappear(perform: putBackIfUnfinished)
    }

    /// The next payment comes in from the side a Hebrew reader moves toward
    /// (`.trailing` is the visual left under RTL).
    private var stepTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
    }

    private func advance() {
        guard let next = router.take() else {
            isFinished = true
            dismiss()
            return
        }
        // On screen now; its notification has done its job.
        PaymentNotifier.clear(next)
        withAnimation(.easeInOut(duration: 0.35)) {
            handled += 1
            current = next
        }
    }

    private func skip() {
        router.skip(current)
        advance()
    }

    private func recordLogged(_ count: Int) {
        handled += count
    }

    /// A swipe-down leaves the payment on screen for later instead of losing
    /// it — it was taken from the line when it came up.
    private func putBackIfUnfinished() {
        guard !isFinished else { return }
        router.putBack([current])
    }
}

/// What a `NewTransactionSheet` needs to be one step of `PaymentQueueSheet`:
/// its place in the line, and where to go when it's done.
struct PaymentQueueStep {
    let position: Int
    let total: Int
    /// Saved or cancelled: show the next payment, or close after the last.
    let onFinish: () -> Void
    /// Keep this payment for later, then move on.
    let onSkip: () -> Void
    /// "רישום כולם" logged this many of the payments waiting behind.
    let onLoggedOthers: (Int) -> Void
}
