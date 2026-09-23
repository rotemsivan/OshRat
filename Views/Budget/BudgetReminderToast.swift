import SwiftUI

/// "Something's scheduled for today" — the budget reminder banner.
///
/// Deliberately the same card, position and rhythm as `CelebrationToast`
/// (slide in under the status bar, hold, slide away), so the app has one
/// banner language; it differs in its sound (a solid bell, not a chime) and in
/// what a tap does. A single reminder opens the new-transaction sheet with the
/// line's details filled in; a batch ("3 פריטים מתוכננים להיום") opens the
/// calendar, which marks them all.
///
/// `HomeView` only mounts it when no celebration is pending, so a level-up and
/// a reminder never talk over each other.
struct BudgetReminderToast: View {
    let reminder: BudgetReminder
    /// A tap — the parent routes it by `reminder.isBatch`.
    let onOpen: () -> Void
    /// Called once the toast has finished animating out, tapped or not. The
    /// parent stamps the lines as announced here, which is what advances to
    /// the next reminder.
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isShowing = false
    /// Guards against the hold running out and a tap both dismissing — see
    /// the same flag on `CelebrationToast`.
    @State private var isDismissing = false

    /// A beat longer than a celebration: this one asks for an action, so it
    /// has to stay long enough to be tapped.
    private static let holdDuration: Duration = .seconds(3.6)
    private static let slideDuration: TimeInterval = 0.35
    private static let entranceDelay: Duration = .seconds(0.4)

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            UserAvatar(crop: .bust, pose: .present)
                .accessibilityHidden(true)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(Theme.Typography.amount)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                subtitle
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: reminder.isBatch ? "calendar" : "wallet.bifold")
                .font(Theme.Typography.amount)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, Theme.Spacing.lg)
        .offset(y: offset)
        .opacity(isShowing ? 1 : 0)
        .onTapGesture { handleTap() }
        .allowsHitTesting(isShowing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(spokenText))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(reminder.isBatch ? "הקש למעבר ליומן" : "הקש לרישום כתנועה"))
        .task(id: reminder) {
            isDismissing = false
            await run()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var title: some View {
        if reminder.isBatch {
            Text("\(reminder.itemIDs.count) פריטים מתוכננים להיום")
        } else {
            Text("להיום: \(reminder.title)")
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if reminder.isBatch {
            Text("הקש כדי לראות אותם ביומן")
        } else {
            Text("\(kindLabel) של \(amountText) · הקש לרישום")
        }
    }

    private var kindLabel: String {
        switch reminder.kind {
        case .income:  String(localized: "הכנסה מתוכננת")
        case .expense: String(localized: "הוצאה מתוכננת")
        }
    }

    private var amountText: String {
        reminder.amount.formatted(.currency(code: reminder.currencyCode))
    }

    private var tint: Color {
        switch reminder.kind {
        case .income:  Theme.Colors.income
        case .expense: Theme.Colors.expense
        }
    }

    private var spokenText: String {
        if reminder.isBatch {
            return String(localized: "\(reminder.itemIDs.count) פריטים מתוכננים להיום")
        }
        return String(localized: "להיום: \(reminder.title), \(kindLabel) של \(amountText)")
    }

    private var offset: CGFloat {
        if reduceMotion { return 0 }
        return isShowing ? 0 : -120
    }

    // MARK: - Lifecycle

    /// Same shape as `CelebrationToast.run()`: cancellation leaves the lines
    /// unannounced, so a reminder interrupted by a sheet comes back.
    private func run() async {
        do {
            try await Task.sleep(for: Self.entranceDelay)
        } catch {
            return
        }
        withAnimation(.spring(response: Self.slideDuration, dampingFraction: 0.8)) {
            isShowing = true
        }
        CelebrationFeedback.shared.play(.budgetReminder)
        AccessibilityNotification.Announcement(spokenText).post()
        do {
            try await Task.sleep(for: Self.holdDuration)
        } catch {
            return
        }
        dismiss()
    }

    private func handleTap() {
        guard !isDismissing else { return }
        onOpen()
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
