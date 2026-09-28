import Foundation
import SwiftData

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
struct PaymentPrefill: Identifiable, Equatable {
    let id = UUID()
    var amount: Decimal?
    var currencyCode: String?
    var merchant: String?
    var cardName: String?
    var receivedAt: Date = .now

    /// A payment this old isn't shown. The router holds a payment until the
    /// dashboard can present it, and one that arrived before onboarding was
    /// finished shouldn't pop up whenever the user eventually gets there.
    static let freshness: TimeInterval = 10 * 60

    func isFresh(at now: Date = .now) -> Bool {
        now.timeIntervalSince(receivedAt) <= Self.freshness
    }

    /// The raw strings trimmed, with an empty one treated as absent — a
    /// shortcut variable the issuer didn't fill arrives as "".
    var trimmedMerchant: String? { Self.nonEmpty(merchant) }
    var trimmedCardName: String? { Self.nonEmpty(cardName) }

    // MARK: - Resolving against the user's history

    /// What the sheet should open with.
    struct Resolved {
        var title: String
        var category: Category?
        var account: Account?
    }

    /// How many recent rows the title fallback looks at. The sheet fetches
    /// this many and no more, so opening it on a long ledger stays cheap.
    static let recentRowLimit = 1_000

    /// Fills in what the automation can't know, from how the user logged
    /// earlier payments — so the second coffee at the same café arrives with
    /// the name, category and account the first one was given.
    ///
    /// - Title and category: the newest row logged from a payment at the same
    ///   merchant; failing that, the newest recent row whose title matches the
    ///   merchant name; failing that, the merchant name and no category.
    /// - Account: the newest row paid with the same card; failing that, an
    ///   account whose name the card name mentions ("כרטיס 1234" for
    ///   "Visa 1234"); failing that, the favourite, then the first.
    ///
    /// Names are compared with `HebrewSearch.fold`, so case, niqqud, final
    /// letters and punctuation don't matter.
    ///
    /// - Parameters:
    ///   - paymentHistory: live rows that were logged from a payment (a
    ///     `paymentMerchant` or `paymentCardName` is set), **newest first**.
    ///   - recent: the newest live rows (up to `recentRowLimit`), newest
    ///     first — for payments logged by hand before this feature existed.
    ///   - accounts: the accounts an expense can be paid from (current and
    ///     digital-wallet, not deleted) — the sheet's `selectableAccounts`.
    static func resolve(
        _ payment: PaymentPrefill,
        paymentHistory: [Transaction],
        recent: [Transaction],
        accounts: [Account]
    ) -> Resolved {
        let merchantKey = payment.trimmedMerchant.map(HebrewSearch.fold)
        let cardKey = payment.trimmedCardName.map(HebrewSearch.fold)
        let accountIDs = Set(accounts.map(\.persistentModelID))

        var merchantMatch: Transaction?
        var cardAccount: Account?
        for row in paymentHistory where row.isOrdinaryExpense {
            if merchantMatch == nil, let merchantKey, let raw = row.paymentMerchant,
               HebrewSearch.fold(raw) == merchantKey {
                merchantMatch = row
            }
            if cardAccount == nil, let cardKey, let raw = row.paymentCardName,
               HebrewSearch.fold(raw) == cardKey,
               let account = row.account, accountIDs.contains(account.persistentModelID) {
                cardAccount = account
            }
            if (merchantMatch != nil || merchantKey == nil) && (cardAccount != nil || cardKey == nil) { break }
        }

        if merchantMatch == nil, let merchantKey, !merchantKey.isEmpty {
            merchantMatch = recent.first { $0.isOrdinaryExpense && HebrewSearch.fold($0.title) == merchantKey }
        }

        let account = cardAccount
            ?? cardKey.flatMap { accountNamed(in: $0, from: accounts) }
            ?? accounts.first(where: \.isFavorite)
            ?? accounts.first

        return Resolved(
            title: merchantMatch?.title ?? payment.trimmedMerchant ?? "",
            category: merchantMatch?.category,
            account: account
        )
    }

    /// An account whose folded name shares a meaningful word with the card's:
    /// the last four digits ("1234"), or a word of three letters or more
    /// ("isracard", "max"). Picks nothing when two accounts would both match,
    /// rather than guessing between them.
    private static func accountNamed(in cardKey: String, from accounts: [Account]) -> Account? {
        let cardWords = Set(cardKey.split(separator: " ").map(String.init).filter { word in
            word.allSatisfy(\.isNumber) ? word.count >= 4 : word.count >= 3
        })
        guard !cardWords.isEmpty else { return nil }
        let matches = accounts.filter { account in
            let words = HebrewSearch.fold(account.name).split(separator: " ").map(String.init)
            return words.contains(where: cardWords.contains)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

private extension Transaction {
    /// A payment is money going out, so only an ordinary expense row is a
    /// useful precedent — not income, a transfer, or a balance correction.
    var isOrdinaryExpense: Bool {
        kind == .expense && !isTransfer && !isManualBalanceEdit
    }
}
