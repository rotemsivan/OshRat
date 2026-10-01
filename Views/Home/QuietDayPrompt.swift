import SwiftUI
import SwiftData

/// "אין תנועות היום?" — from 19:00 on a working day with nothing logged,
/// the way to mark today a quiet day (`XPRules.quietDaysPerWeek`), and once
/// marked, the confirmation with a way back.
///
/// The in-app twin of the evening reminder's button, shown on the dashboard
/// and at the top of the transactions list. It renders nothing outside that
/// window, so a host can place it unconditionally. Owns its progress query,
/// so only the prompt re-renders when progress changes, not its host.
struct QuietDayPrompt: View {
    /// The host's clock — the dashboard ticks it at 19:00 so the prompt
    /// appears while the app is open.
    let now: Date
    /// Spacing around the card, applied inside so an empty prompt takes none.
    var insets = EdgeInsets()

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserProgress.createdAt, order: .forward)
    private var progressRows: [UserProgress]

    var body: some View {
        if let state {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                Image(systemName: state.isMarked ? "checkmark.seal.fill" : "moon.zzz.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title)
                        .font(Theme.Typography.body.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(state.caption)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                if let action = state.action {
                    Button(action.label) {
                        withAnimation(.easeInOut(duration: 0.2)) { perform(action) }
                    }
                    .font(Theme.Typography.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(Theme.Colors.accent)
                    .controlSize(.small)
                }
            }
            .padding(Theme.Spacing.md)
            .background(
                Theme.Colors.accent.opacity(0.08),
                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            )
            .padding(insets)
        }
    }

    /// DEBUG `-demoQuietPrompt`: show the prompt at any hour, so marking and
    /// "ביטול" can be tried without waiting for 19:00. The other conditions
    /// (a working day, nothing logged) still apply.
    static var ignoresEvening: Bool {
        #if DEBUG
        LaunchArguments.contains("-demoQuietPrompt")
        #else
        false
        #endif
    }

    // MARK: - State

    private enum Action {
        case mark, unmark

        var label: LocalizedStringKey {
            switch self {
            case .mark: "סימון יום שקט"
            case .unmark: "ביטול"
            }
        }
    }

    private struct PromptState {
        let isMarked: Bool
        let title: String
        let caption: String
        let action: Action?
    }

    /// Why the prompt isn't showing at `now`, or `nil` when it is — the
    /// conditions `state` checks, in words. The admin panel shows it, since
    /// a hidden prompt otherwise gives no clue which rule is hiding it.
    static func hiddenReason(progress: UserProgress?, now: Date) -> String? {
        guard let progress else { return String(localized: "אין עדיין נתוני התקדמות") }
        guard DailyReminder.isReminderDay(now) else {
            return String(localized: "היום אינו יום תזכורת (סוף שבוע, חג או ערב חג)")
        }
        guard Calendar.current.component(.hour, from: now) >= DailyReminder.hour || ignoresEvening else {
            return String(localized: "לפני 19:00 (ובלי ‎-demoQuietPrompt)")
        }
        guard !ProgressService.hasActivity(on: now, progress: progress) else {
            return String(localized: "כבר נרשמה היום פעילות")
        }
        return nil
    }

    /// `nil` outside the window: not a reminder day, before 19:00, or the day
    /// already has activity (`hiddenReason`).
    private var state: PromptState? {
        guard Self.hiddenReason(progress: progressRows.first, now: now) == nil,
              let progress = progressRows.first
        else { return nil }

        if ProgressService.isQuietDay(now, progress: progress) {
            return PromptState(
                isMarked: true,
                title: String(localized: "יום שקט"),
                caption: String(localized: "הרצף נשמר"),
                action: .unmark
            )
        }

        let eligibility = XPRules.quietDayEligibility(
            on: now,
            quietDays: Set(progress.quietDays),
            hasActivityToday: false
        )
        switch eligibility {
        case .allowed(let remainingAfter):
            let left = remainingAfter + 1
            return PromptState(
                isMarked: false,
                title: String(localized: "אין תנועות היום?"),
                caption: left == 1
                    ? String(localized: "שומר על הרצף · נשאר אחד השבוע")
                    : String(localized: "שומר על הרצף · נשארו \(left) השבוע"),
                action: .mark
            )
        case .weeklyLimitReached:
            return PromptState(
                isMarked: false,
                title: String(localized: "אין תנועות היום?"),
                caption: DailyReminderService.refusal(for: eligibility) ?? "",
                action: nil
            )
        case .alreadyMarked, .alreadyLogged, .restDay:
            return nil
        }
    }

    private func perform(_ action: Action) {
        switch action {
        case .mark: ProgressService.markQuietDay(in: modelContext, now: now)
        case .unmark: ProgressService.unmarkQuietDay(in: modelContext, now: now)
        }
    }
}
