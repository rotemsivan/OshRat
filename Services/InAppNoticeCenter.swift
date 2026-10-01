import Foundation
import Observation
import UserNotifications

/// A notification that arrived while the app was open, shown as the app's
/// own toast (`InAppNoticeToast`) rather than as a system banner over it.
struct InAppNotice: Identifiable, Equatable {
    enum Action: Equatable {
        /// A tap just dismisses.
        case none
        /// A tap opens the new-transaction sheet — the evening reminder.
        case newTransaction
    }

    let id = UUID()
    let title: String?
    let body: String
    let action: Action
    /// The evening reminder rings its bell; anything else arrives quietly.
    let isReminder: Bool
}

/// Where `PaymentNotifier.willPresent` parks a notification that arrived in
/// the foreground, for `HomeView` to show in its banner slot once nothing
/// else is there. Oldest first.
///
/// Why not the system banner: it slides over the app's own UI from outside
/// it, ignores the open sheet, and (for the reminder) repeats what the
/// dashboard's quiet-day card is already saying. A toast in the app's own
/// voice waits its turn behind celebrations and modals like everything else.
@MainActor
@Observable
final class InAppNoticeCenter {
    static let shared = InAppNoticeCenter()

    private(set) var queue: [InAppNotice] = []

    var next: InAppNotice? { queue.first }

    private init() {}

    func post(_ notice: InAppNotice) {
        queue.append(notice)
    }

    /// Takes `notice` off once its toast has animated out — only if it's
    /// still the head, the same guard `ProgressService.dismissCelebration` has.
    func dismiss(_ notice: InAppNotice) {
        guard queue.first?.id == notice.id else { return }
        queue.removeFirst()
    }

    /// The notice a system notification becomes in the foreground.
    static func notice(for notification: UNNotification) -> InAppNotice {
        let content = notification.request.content
        let isReminder = DailyReminderService.isReminder(notification)
        return InAppNotice(
            title: content.title.isEmpty ? nil : content.title,
            body: content.body,
            action: isReminder ? .newTransaction : .none,
            isReminder: isReminder
        )
    }
}
