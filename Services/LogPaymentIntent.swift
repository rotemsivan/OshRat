import AppIntents
import Foundation

/// "רישום תשלום" — the Shortcuts action behind logging Apple Pay payments.
///
/// iOS gives apps no notification of Apple Pay payments (FinanceKit covers
/// only Apple Card / Cash / Savings, US-only, behind an entitlement — and it
/// is bank data, which this app stays away from). What iOS *does* have is the
/// Shortcuts "Wallet" personal automation: it runs the moment a Wallet card
/// is tapped at a till and exposes the payment's amount, merchant and card
/// name. The user builds that automation once (`ApplePaySetupView` walks them
/// through it) with this action in it.
///
/// **It runs in the background and leaves a notification.** It used to bring
/// the app forward, and on a real phone that failed with an error: the
/// automation fires while the phone is usually still locked with the payment
/// sheet on top, and iOS won't open an app then. Now it parks the payment
/// (`IncomingPaymentRouter`, on disk) and posts "₪42.90 · Cafe Nero"
/// (`PaymentNotifier`); a tap on that opens the pre-filled "תנועה חדשה".
///
/// Every parameter is optional: which details reach the automation depends on
/// the card issuer, and the sheet leaves whatever is missing blank.
struct LogPaymentIntent: AppIntent {
    static let title: LocalizedStringResource = "רישום תשלום"
    static let description = IntentDescription(
        "שומר את התשלום — הסכום, בית העסק והכרטיס — ומציג התראה. הקשה עליה פותחת את עכבר עו״ש עם תנועה חדשה שמולאה מהתשלום."
    )

    /// Text, not `IntentCurrencyAmount`: the Wallet trigger's amount comes
    /// through as formatted text ("‏42.90 ‏₪"), which a typed currency
    /// parameter silently dropped. `PaymentPrefill.parseAmount` reads it.
    @Parameter(title: "סכום")
    var amount: String?

    @Parameter(title: "בית עסק")
    var merchant: String?

    @Parameter(title: "כרטיס")
    var card: String?

    /// All three fields on the action's face. The card used to sit behind the
    /// action's expand arrow, which in the automation editor was easy to miss.
    static var parameterSummary: some ParameterSummary {
        Summary("רישום תשלום של \(\.$amount) ב\(\.$merchant) בכרטיס \(\.$card)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let parsed = PaymentPrefill.parseAmount(amount)
        let payment = PaymentPrefill(
            amount: parsed?.amount,
            currencyCode: parsed?.currencyCode,
            merchant: merchant,
            cardName: card,
            rawAmount: amount
        )
        IncomingPaymentRouter.shared.receive(payment)
        // The payment is saved either way. If its notification can't be
        // shown (permission off), fail loudly: Shortcuts shows a thrown
        // error's message as a banner, which beats a payment waiting where
        // nobody knows to look.
        guard await PaymentNotifier.notify(payment) else {
            throw LogPaymentError.notificationsOff
        }
        return .result()
    }
}

/// What `LogPaymentIntent` reports back to Shortcuts when it can't finish the
/// job quietly. Shortcuts displays `localizedStringResource` to the user.
enum LogPaymentError: Error, CustomLocalizedStringResourceConvertible {
    case notificationsOff

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notificationsOff:
            "התשלום נשמר, אבל ההתראות של עכבר עו״ש כבויות. פתחו את האפליקציה כדי לרשום אותו, ואפשרו התראות בהגדרות."
        }
    }
}
