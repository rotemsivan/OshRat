import Foundation

/// A card payment as the Wallet "Transaction" automation reported it, on its
/// way into a pre-filled "תנועה חדשה" sheet.
///
/// iOS tells no third-party app about Apple Pay payments. What it does offer
/// is a Shortcuts personal automation that runs when a Wallet card is tapped
/// and hands its shortcut the amount, the merchant and the card's name — so
/// the user builds that automation once, pointing it at `LogPaymentIntent`,
/// and every tap at a till opens the app with this value. Nothing leaves the
/// device. Every field is optional because what comes through depends on the
/// card issuer; whatever is missing stays blank in the form.
///
/// Compiled into the app **and** the App Intents extension
/// (`OshRatIntents`), so it holds only the value, the parsing and the setup
/// check — nothing that needs the store. Matching a payment against the
/// user's history is in `PaymentPrefill+History.swift`, app-only.
///
/// `Codable` because it waits on disk: the action runs in the background at
/// the till and the user opens it later from a notification, possibly after
/// the app was closed (see `IncomingPaymentRouter`).
struct PaymentPrefill: Identifiable, Equatable, Codable {
    var id = UUID()
    var amount: Decimal?
    var currencyCode: String?
    var merchant: String?
    var cardName: String?
    /// The amount exactly as the shortcut sent it, before `parseAmount` —
    /// shown in the sheet when a field came through empty, so a setup
    /// problem can be seen rather than guessed at.
    var rawAmount: String? = nil
    var receivedAt: Date = .now
    /// Set when the user skipped it ("דילוג"): it waits, parked, until they
    /// come back for it from the transactions list, instead of coming up by
    /// itself. Optional, so payments stored before skipping existed decode.
    var skippedAt: Date? = nil

    var isSkipped: Bool { skippedAt != nil }

    /// How long a payment waits to be logged — whether for its notification
    /// to be tapped or after being skipped — before it's deleted unlogged.
    /// A week: long enough to catch up on the weekend's payments, short
    /// enough that the list doesn't collect a month of stale coffees.
    static let freshness: TimeInterval = 7 * 24 * 60 * 60

    func isFresh(at now: Date = .now) -> Bool {
        now.timeIntervalSince(receivedAt) <= Self.freshness
    }

    /// The raw strings trimmed, with an empty one treated as absent — a
    /// shortcut variable the issuer didn't fill arrives as "".
    var trimmedMerchant: String? { Self.nonEmpty(merchant) }
    var trimmedCardName: String? { Self.nonEmpty(cardName) }

    /// Whether any of the three details arrived at all — false means the
    /// automation's fields weren't connected to the payment.
    var receivedAnything: Bool {
        (amount ?? 0) > 0 || trimmedMerchant != nil || trimmedCardName != nil
    }

    // MARK: - Checking the setup

    /// The three details the automation can hand over — the action's three
    /// fields.
    enum SetupField: CaseIterable {
        case amount, merchant, card
    }

    /// Whether this field's detail came through usable. An amount counts only
    /// once it reads as a number above zero: a field tied to the whole
    /// Shortcut Input instead of its Amount sends text that doesn't.
    func arrived(_ field: SetupField) -> Bool {
        switch field {
        case .amount:   (amount ?? 0) > 0
        case .merchant: trimmedMerchant != nil
        case .card:     trimmedCardName != nil
        }
    }

    /// What one delivered payment says about the user's automation — the
    /// setup screen's live check (`PaymentSetupCheckCard`).
    enum SetupVerdict: Equatable {
        /// Amount and merchant arrived; the card is optional (it only helps
        /// pick the account), so it never fails the check.
        case working
        /// Something arrived, so the automation runs and is wired up — but
        /// these required fields came through empty or unreadable.
        case missing([SetupField])
        /// Nothing at all: the action's fields aren't tied to the payment.
        case empty
    }

    var setupVerdict: SetupVerdict {
        guard receivedAnything else { return .empty }
        let missing = [SetupField.amount, .merchant].filter { !arrived($0) }
        return missing.isEmpty ? .working : .missing(missing)
    }

    // MARK: - Reading the amount

    /// The amount and currency out of whatever text the shortcut passed.
    ///
    /// The Wallet automation's amount reaches the action as text formatted
    /// for the device — "‏42.90 ‏₪", "₪1,234.50", "42.9", "USD 12.00" — so it
    /// is taken as a string and read here rather than as a typed currency
    /// amount, which Shortcuts silently left empty when it couldn't convert.
    /// Direction marks and spaces are ignored; with both separators present
    /// the last one is the decimal point, and a lone comma followed by one or
    /// two digits is one too ("42,90"). A sign is dropped: a payment is an
    /// expense either way. `nil` when there's no number in it.
    static func parseAmount(_ text: String?) -> (amount: Decimal, currencyCode: String?)? {
        guard let text else { return nil }
        let invisible = CharacterSet(charactersIn: "\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}")
        let cleaned = String(String.UnicodeScalarView(text.unicodeScalars.filter { !invisible.contains($0) }))
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        guard let range = cleaned.range(of: #"\d[\d.,' \x{202F}]*"#, options: .regularExpression) else { return nil }
        var number = cleaned[range]
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
        while let last = number.last, last == "." || last == "," { number.removeLast() }

        let lastComma = number.lastIndex(of: ","), lastDot = number.lastIndex(of: ".")
        if let lastComma, let lastDot {
            // Both: whichever comes last is the decimal separator.
            let decimal: Character = lastComma > lastDot ? "," : "."
            let grouping: Character = decimal == "," ? "." : ","
            number = number.filter { $0 != grouping }.map { $0 == decimal ? "." : String($0) }.joined()
        } else if lastComma != nil {
            let parts = number.split(separator: ",", omittingEmptySubsequences: false)
            number = parts.count == 2 && (1...2).contains(parts[1].count)
                ? parts.joined(separator: ".")
                : parts.joined()
        } else if number.filter({ $0 == "." }).count > 1 {
            number = number.replacingOccurrences(of: ".", with: "")
        }

        guard let amount = Decimal(string: number, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return (amount, currencyCode(in: cleaned))
    }

    /// The currency named in the text, if any: a symbol, the Hebrew or common
    /// name of the shekel, or an ISO code.
    private static func currencyCode(in text: String) -> String? {
        let symbols: [(String, String)] = [
            ("₪", "ILS"), ("ש״ח", "ILS"), ("ש\"ח", "ILS"), ("שח", "ILS"), ("NIS", "ILS"),
            ("€", "EUR"), ("£", "GBP"), ("$", "USD")
        ]
        if let match = symbols.first(where: { text.contains($0.0) }) { return match.1 }
        let codes = Set(Locale.commonISOCurrencyCodes)
        let letters = text.uppercased().split { !$0.isLetter }.map(String.init)
        return letters.first { $0.count == 3 && codes.contains($0) }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
