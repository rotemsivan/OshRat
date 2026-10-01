import SwiftUI

/// A notification that arrived while the app was open — the evening reminder,
/// or a note like "this week's quiet days are used up" — in the app's own
/// banner rather than the system's.
///
/// The same card, slot and rhythm as `BudgetReminderToast` (slide in under the
/// status bar, hold, slide away, or swipe up to send it off sooner), so the
/// app keeps one banner language. A reminder taps through to the
/// new-transaction sheet; anything else just dismisses.
struct InAppNoticeToast: View {
    let notice: InAppNotice
    let onOpen: () -> Void
    /// Called once the toast has animated out; the parent pops the queue here.
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isShowing = false
    @State private var isDismissing = false

    /// As long as the budget reminder's: it, too, asks for an action.
    private static let holdDuration: Duration = .seconds(3.6)
    private static let slideDuration: TimeInterval = 0.35
    private static let entranceDelay: Duration = .seconds(0.4)

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            UserAvatar(crop: .bust, pose: .present)
                .accessibilityHidden(true)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                if let title = notice.title {
                    Text(verbatim: title)
                        .font(Theme.Typography.amount)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                }
                Text(verbatim: notice.body)
                    .font(notice.title == nil ? Theme.Typography.body.weight(.semibold) : Theme.Typography.caption)
                    .foregroundStyle(notice.title == nil ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                    .lineLimit(3)
                if notice.action == .newTransaction {
                    Text("הקש לרישום תנועה")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if notice.action == .newTransaction {
                Image(systemName: "plus.circle.fill")
                    .font(Theme.Typography.amount)
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, Theme.Spacing.lg)
        .offset(y: reduceMotion || isShowing ? 0 : -120)
        .opacity(isShowing ? 1 : 0)
        .swipeUpToDismiss(isEnabled: isShowing && !isDismissing, resetID: notice.id, onDismiss: dismiss)
        .onTapGesture { handleTap() }
        .allowsHitTesting(isShowing)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(notice.action == .newTransaction ? "הקש לרישום תנועה" : "הקש לסגירה"))
        .task(id: notice.id) {
            isDismissing = false
            await run()
        }
    }

    // MARK: - Lifecycle

    /// Same shape as `BudgetReminderToast.run()`: cancelled by a sheet coming
    /// up, it leaves the notice queued, so it comes back afterwards.
    private func run() async {
        do {
            try await Task.sleep(for: Self.entranceDelay)
        } catch {
            return
        }
        withAnimation(.spring(response: Self.slideDuration, dampingFraction: 0.8)) {
            isShowing = true
        }
        if notice.isReminder {
            CelebrationFeedback.shared.play(.budgetReminder)
        }
        AccessibilityNotification.Announcement(notice.body).post()
        do {
            try await Task.sleep(for: Self.holdDuration)
        } catch {
            return
        }
        dismiss()
    }

    private func handleTap() {
        guard !isDismissing else { return }
        if notice.action == .newTransaction { onOpen() }
        dismiss()
    }

    private func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        withAnimation(.easeIn(duration: Self.slideDuration)) {
            isShowing = false
        }
        Task {
            try? await Task.sleep(for: .seconds(Self.slideDuration))
            onDismiss()
        }
    }
}
