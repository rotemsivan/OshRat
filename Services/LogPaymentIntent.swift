import AppIntents
import Foundation

/// "רישום תשלום" — the Shortcuts action behind logging Apple Pay payments.
///
/// iOS gives apps no notification of Apple Pay payments (FinanceKit covers
/// only Apple Card / Cash / Savings, US-only, behind an entitlement — and it
/// is bank data, which this app stays away from). What iOS *does* have is the
/// Shortcuts "Transaction" personal automation: it runs the moment a Wallet
/// card is tapped at a till and exposes the payment's amount, merchant and
/// card name. The user builds that automation once (`ApplePaySetupView`
/// walks them through it) with this action in it, and from then on every
/// tap opens the app on a pre-filled "תנועה חדשה".
///
/// Every parameter is optional: which details reach the automation depends on
/// the card issuer, and the sheet leaves whatever is missing blank.
struct LogPaymentIntent: AppIntent {
    static let title: LocalizedStringResource = "רישום תשלום"
    static let description = IntentDescription(
        "פותח את עכבר עו״ש עם תנועה חדשה שמולאה מהתשלום — הסכום, בית העסק והכרטיס."
    )

    /// Logging happens in the app's own sheet, so the action brings it to the
    /// foreground rather than running in the background.
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "סכום")
    var amount: IntentCurrencyAmount?

    @Parameter(title: "בית עסק")
    var merchant: String?

    @Parameter(title: "כרטיס")
    var card: String?

    static var parameterSummary: some ParameterSummary {
        Summary("רישום תשלום של \(\.$amount) ב\(\.$merchant)") {
            \.$card
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        IncomingPaymentRouter.shared.receive(PaymentPrefill(
            amount: amount?.amount,
            currencyCode: amount?.currencyCode,
            merchant: merchant,
            cardName: card
        ))
        return .result()
    }
}

/// Lists the action under the app in Shortcuts (and lets Siri run it by
/// phrase) without the user having to search for it.
struct OshRatShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogPaymentIntent(),
            phrases: ["רישום תשלום ב\(.applicationName)"],
            shortTitle: "רישום תשלום",
            systemImageName: "creditcard"
        )
    }
}
