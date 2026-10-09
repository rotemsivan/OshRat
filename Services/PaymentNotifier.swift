import Foundation
import UserNotifications

/// The app's side of the payment notification (`PaymentNotification`
/// posts it, from whichever process ran the intent): permission, taking it
/// down once the payment has been seen, and the notification centre's
/// delegate — while the app is already open, the payment's sheet appears by
/// itself, so the banner is suppressed.
final class PaymentNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PaymentNotifier()

    // MARK: Permission

    enum Permission {
        case notAsked, allowed, denied
    }

    static func permission() async -> Permission {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notAsked
        case .denied: .denied
        default: .allowed
        }
    }

    /// Asks once; `ApplePaySetupView` calls it from its button, since the
    /// intent itself runs where no prompt could be shown.
    static func requestPermission() async -> Permission {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
        return granted ? .allowed : .denied
    }

    // MARK: Taking it down

    /// Takes the payment's notification off the lock screen and Notification
    /// Centre — it has been shown in the app, so it's done.
    static func clear(_ payment: PaymentPrefill) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [payment.id.uuidString])
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Nothing the app posts appears as a system banner while it's open.
    /// A waiting payment's sheet comes up on its own, so its notification is
    /// simply dropped; everything else — the evening reminder, a quiet-day
    /// note — becomes the app's own toast (`InAppNoticeCenter`), which waits
    /// its turn behind celebrations and open sheets.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if notification.request.content.categoryIdentifier != PaymentNotification.category {
            InAppNoticeCenter.shared.post(InAppNoticeCenter.notice(for: notification))
        }
        return []
    }

    /// A notification was answered. Only the evening reminder's button needs
    /// handling here; a plain tap just opens the app, which does the rest.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if DailyReminderService.isReminder(response.notification) {
            await DailyReminderService.handle(response)
        }
    }
}
