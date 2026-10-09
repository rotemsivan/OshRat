import Foundation
import UserNotifications

/// The notification a card payment leaves behind: "₪42.90 · Cafe Nero",
/// "הקישו כדי לרשום את התנועה".
///
/// Why a notification rather than opening the app: the Wallet automation runs
/// the moment the card is tapped, usually on a locked phone with the payment
/// sheet on top, and iOS refuses to bring an app forward then. So
/// `LogPaymentIntent` runs in the background, parks the payment
/// (`PaymentInbox`) and posts this; tapping it opens the app, which shows
/// the waiting payment. Nothing leaves the device — it's a local
/// notification.
///
/// Compiled into the app and the App Intents extension, since either may
/// run the intent; a notification an extension posts is shown as its app's.
/// Everything that needs the app — the delegate, taking notifications down,
/// asking permission — stays in `PaymentNotifier`.
enum PaymentNotification {
    /// Marks this app's payment notifications, so the delegate leaves any
    /// other kind alone.
    static let category = "payment"

    enum PostResult {
        case posted
        /// The user hasn't allowed notifications: iOS would drop it silently.
        case notAllowed
        /// iOS refused it for another reason.
        case failed
    }

    /// Posts the payment's notification, identified by the payment's id so it
    /// can be taken down once the payment has been dealt with.
    @discardableResult
    static func post(_ payment: PaymentPrefill) async -> PostResult {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: break
        default: return .notAllowed
        }
        let content = UNMutableNotificationContent()
        content.title = title(for: payment)
        // Nothing arrived at all means the automation's fields aren't tied to
        // the payment — the most common setup slip. Say so here, where it's
        // noticed, rather than leave an empty sheet to puzzle over; the sheet
        // then shows exactly what the shortcut sent.
        content.body = payment.receivedAnything
            ? String(localized: "הקישו כדי לרשום את התנועה בעכבר עו״ש")
            : String(localized: "לא הגיעו פרטים מהקיצור — הקישו כדי לבדוק את ההגדרה")
        content.sound = .default
        content.categoryIdentifier = category
        let request = UNNotificationRequest(identifier: payment.id.uuidString, content: content, trigger: nil)
        do {
            try await center.add(request)
            return .posted
        } catch {
            return .failed
        }
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
}
