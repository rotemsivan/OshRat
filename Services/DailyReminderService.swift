import Foundation
import SwiftData
import UserNotifications

/// The evening reminder as local notifications: "nothing logged yet today —
/// time to log", at 19:00 on working days (`DailyReminder`).
///
/// iOS can't wake the app at 19:00 to decide, so the next couple of weeks of
/// reminders sit in the notification centre already, and this service keeps
/// that set honest: `reschedule` runs whenever today's state could have
/// changed (launch, activation, a log, a quiet-day mark, midnight) and drops
/// today's reminder once the day has activity or is marked quiet. Purely
/// local — nothing leaves the device.
///
/// The notification carries two buttons (`registerCategories`): "רישום
/// תנועה" opens the new-transaction sheet, and "לא היו היום תנועות" marks
/// today quiet without opening the app (`handle`).
enum DailyReminderService {

    /// `UserDefaults` switch behind Settings → "תזכורת ערב". A device
    /// preference, like sounds — on by default.
    static let isEnabledKey = "dailyReminder.isEnabled"

    /// Set once the permission prompt has been shown from the dashboard, so
    /// it's only ever asked for there once.
    private static let didAskPermissionKey = "dailyReminder.didAskPermission"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: isEnabledKey) as? Bool ?? true
    }

    /// The store, for the background action. Set by `OshRatApp` once the
    /// container has opened; the action does nothing without one.
    static var container: ModelContainer?

    static let category = "daily-reminder"
    /// The same reminder without the quiet-day button — that week's quiet
    /// days are spent.
    static let plainCategory = "daily-reminder-plain"
    private static let quietDayAction = "quiet-day"
    private static let logAction = "log-transaction"
    private static let idPrefix = "daily-reminder-"

    static func isReminder(_ notification: UNNotification) -> Bool {
        let category = notification.request.content.categoryIdentifier
        return category == Self.category || category == plainCategory
    }

    // MARK: Setup

    /// Registers the two buttons, shown as WhatsApp shows its own: under the
    /// notification once it's long-pressed or pulled down. Called from
    /// `OshRatApp.init`, before a notification can be answered.
    static func registerCategories() {
        let logTransaction = UNNotificationAction(
            identifier: logAction,
            title: String(localized: "רישום תנועה"),
            // Opens the app, straight into the new-transaction sheet.
            options: [.foreground]
        )
        let markQuiet = UNNotificationAction(
            identifier: quietDayAction,
            title: String(localized: "לא היו היום תנועות"),
            // Runs in the background: nothing on screen needs the user.
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [logTransaction, markQuiet], intentIdentifiers: []),
            UNNotificationCategory(identifier: plainCategory, actions: [logTransaction], intentIdentifiers: []),
        ])
    }

    /// Asks for notification permission the first time the dashboard
    /// appears — the moment the app has shown what it's for. Once only; after
    /// that the Settings switch is the way to turn it on.
    static func askPermissionOnce() async {
        let defaults = UserDefaults.standard
        guard isEnabled, !defaults.bool(forKey: didAskPermissionKey) else { return }
        defaults.set(true, forKey: didAskPermissionKey)
        if await PaymentNotifier.permission() == .notAsked {
            _ = await PaymentNotifier.requestPermission()
        }
    }

    // MARK: Scheduling

    /// Replaces every pending reminder with the next `DailyReminder.scheduleAhead`
    /// evenings, skipping today once it has activity or is marked quiet.
    static func reschedule(in context: ModelContext, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        await removePending()
        guard isEnabled, await PaymentNotifier.permission() == .allowed else { return }

        let progress = ProgressService.progress(in: context)
        let skipToday = ProgressService.hasActivity(on: now, progress: progress)
            || ProgressService.isQuietDay(now, progress: progress)
        var rng = SystemRandomNumberGenerator()
        let slots = DailyReminder.upcoming(
            from: now,
            skipToday: skipToday,
            quietDays: Set(progress.quietDays),
            using: &rng
        )

        for slot in slots {
            let content = UNMutableNotificationContent()
            content.body = slot.phrase
            content.sound = .default
            content.categoryIdentifier = slot.offersQuietDay ? category : plainCategory
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: slot.fireDate)
            let request = UNNotificationRequest(
                identifier: idPrefix + XPRules.quietDayKey(for: slot.day),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            )
            try? await center.add(request)
        }
    }

    /// Takes every scheduled reminder down — the switch went off, or before
    /// a fresh set goes up.
    static func removePending() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: The action

    /// A reminder was answered.
    ///
    /// "רישום תנועה", or a plain tap on the reminder, opens the
    /// new-transaction sheet — through the widget's route (`DeepLinkRouter`),
    /// which skips the login and waits for the screen to be free.
    ///
    /// "לא היו היום תנועות" marks today quiet in the background. If that's
    /// refused (a transaction synced in meanwhile, or the week's marks are
    /// used up), a short notification says why, since there is no screen to
    /// say it on.
    static func handle(_ response: UNNotificationResponse) async {
        switch response.actionIdentifier {
        case logAction, UNNotificationDefaultActionIdentifier:
            DeepLinkRouter.shared.isNewTransactionPending = true
        case quietDayAction:
            guard let context = container?.mainContext else { return }
            let result = ProgressService.markQuietDay(in: context)
            if let explanation = refusal(for: result) {
                // No category: it isn't a reminder, so a tap just opens the app.
                let content = UNMutableNotificationContent()
                content.body = explanation
                try? await UNUserNotificationCenter.current()
                    .add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            }
            await reschedule(in: context)
        default:
            break
        }
    }

    /// Why a mark was refused, in the words the prompt uses too; `nil` when
    /// there's nothing to explain.
    static func refusal(for result: QuietDayEligibility) -> String? {
        switch result {
        case .allowed, .alreadyMarked, .restDay:
            return nil
        case .alreadyLogged:
            return String(localized: "היום כבר נרשמה תנועה, כך שהרצף שמור")
        case .weeklyLimitReached:
            return String(localized: "השבוע כבר סומנו \(XPRules.quietDaysPerWeek) ימים שקטים")
        }
    }

    #if DEBUG
    /// `-demoReminder`: a reminder ten seconds from now, so it can be tried
    /// without waiting for the evening. With the app open it arrives as the
    /// in-app toast; send the app to the background (or lock the phone)
    /// within the ten seconds to get the system notification and its buttons.
    static let demoIdentifier = "demo-reminder"

    static func postDemoReminder() async {
        _ = await PaymentNotifier.requestPermission()
        let content = UNMutableNotificationContent()
        content.body = DailyReminder.phrases.randomElement() ?? ""
        content.sound = .default
        content.categoryIdentifier = category
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: demoIdentifier, content: content, trigger: trigger))
    }
    #endif
}
