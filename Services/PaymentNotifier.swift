import Foundation
import UserNotifications

/// The notification a card payment leaves behind: "₪42.90 · Cafe Nero",
/// "הקישו כדי לרשום את התנועה".
///
/// Why a notification rather than opening the app: the Wallet automation runs
/// the moment the card is tapped, usually on a locked phone with the payment
/// sheet on top, and iOS refuses to bring an app forward then — the action
/// failed with an error. So `LogPaymentIntent` runs in the background, parks
/// the payment (`IncomingPaymentRouter`) and posts this; tapping it opens the
/// app, which shows the waiting payment. Nothing leaves the device — it's a
/// local notification.
///
/// Also the notification centre's delegate: while the app is already open,
/// the payment's sheet appears by itself, so the banner is suppressed.
final class PaymentNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PaymentNotifier()

    /// Marks this app's payment notifications, so the delegate leaves any
    /// other kind alone.
    private static let category = "payment"

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

    // MARK: Posting

    /// Posts the payment's notification, identified by the payment's id so it
    /// can be taken down once the payment has been dealt with.
    static func notify(_ payment: PaymentPrefill) async {
        let content = UNMutableNotificationContent()
        content.title = title(for: payment)
        content.body = String(localized: "הקישו כדי לרשום את התנועה בעכבר עו״ש")
        content.sound = .default
        content.categoryIdentifier = category
        let request = UNNotificationRequest(identifier: payment.id.uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Takes the payment's notification off the lock screen and Notification
    /// Centre — it has been shown in the app, so it's done.
    static func clear(_ payment: PaymentPrefill) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [payment.id.uuidString])
    }

    /// "₪42.90 · Cafe Nero", or as much of it as the card issuer sent. A dot,
    /// not the prefix ב: merchant names mostly arrive in Latin letters, and
    /// "בCafe Nero" doesn't read.
    private static func title(for payment: PaymentPrefill) -> String {
        let amount = payment.amount.flatMap { $0 > 0 ? $0 : nil }
            .map { $0.formatted(.currency(code: payment.currencyCode ?? "ILS").locale(Locale(identifier: "he_IL"))) }
        switch (amount, payment.trimmedMerchant) {
        case let (amount?, merchant?): return "\(amount) · \(merchant)"
        case let (amount?, nil):       return String(localized: "תשלום של \(amount)")
        case let (nil, merchant?):     return String(localized: "תשלום · \(merchant)")
        case (nil, nil):               return String(localized: "תשלום בכרטיס")
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    /// With the app open, the waiting payment's sheet comes up on its own, so
    /// a banner on top of it would say the same thing twice.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        notification.request.content.categoryIdentifier == Self.category ? [] : [.banner, .sound]
    }
}
