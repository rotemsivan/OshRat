import Foundation
import SwiftData

/// How a transaction matched the search, strongest first.
enum SearchMatchTier: Int, Comparable {
    /// The query's text appears as typed (after folding — see `HebrewSearch`).
    case exact
    /// It matches once vowel letters are ignored (תוכנית ↔ תכנית).
    case spelling
    /// It only matches by forgiving a typo. `TransactionFilters` shows these
    /// only when nothing matched more strongly, and says so.
    case typo

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A search string, parsed once per pass rather than once per transaction.
struct TransactionSearchQuery {
    /// The folded words of the query. Every one must match (AND), anywhere in
    /// the transaction — so "סופר שופרסל" finds a row titled "שופרסל" in the
    /// category "סופר".
    let tokens: [String]
    /// The same keystrokes read on the Hebrew layout, when the query has Latin
    /// letters in it. Tried as a whole alternative, not token by token.
    let layoutTokens: [String]?

    /// `nil` for a query with nothing searchable in it (empty, whitespace,
    /// punctuation only) — which is "no search", not "match nothing".
    init?(_ raw: String) {
        let tokens = HebrewSearch.words(ofFolded: HebrewSearch.fold(raw))
        guard !tokens.isEmpty else { return nil }
        self.tokens = tokens
        self.layoutTokens = HebrewSearch.hebrewLayoutVariant(ofRaw: raw)
            .map(HebrewSearch.words(ofFolded:))
            .flatMap { $0.isEmpty || $0 == tokens ? nil : $0 }
    }
}

/// The searchable text of each transaction, normalized once and kept.
///
/// Folding a transaction's title, note, category and account names is the
/// expensive part of a search, and it used to be redone for every row on every
/// keystroke — several times per render. The index keeps each row's folded
/// words (and their vowel-less skeletons) and only rebuilds an entry when the
/// row's source text actually changed, which it detects by comparing the raw
/// strings it was built from. So an edited title, or a renamed account, is
/// picked up on the next search without any invalidation for callers to
/// remember.
///
/// Held by `TransactionFilters` for the session, so the work survives a trip
/// to another tab along with the filters.
final class TransactionSearchIndex {

    struct Entry {
        fileprivate let source: Source
        /// Every searchable field, folded and joined with spaces.
        let folded: String
        let words: [String]
        let skeletons: [String]
    }

    /// The raw text an entry was built from — what's compared to spot a stale
    /// entry.
    fileprivate struct Source: Equatable {
        let title: String
        let note: String
        let category: String
        let account: String
        let destination: String
        let amount: Decimal
        let isTransfer: Bool

        init(_ transaction: Transaction) {
            title = transaction.title
            note = transaction.note
            category = transaction.category?.name ?? ""
            account = transaction.account?.name ?? ""
            destination = transaction.destinationAccount?.name ?? ""
            amount = transaction.amount
            isTransfer = transaction.isTransfer
        }

        /// Account names are searchable too, because the row shows them; and a
        /// transfer answers to "העברה", because that's what its row says when
        /// it has no title. The amount goes in as plain digits ("120.5"), so a
        /// search for "120" finds it; folding splits it at the point, the same
        /// way it splits the query.
        var searchableText: String {
            [title, note, category, account, destination,
             isTransfer ? "העברה" : "",
             "\(amount)"].joined(separator: " ")
        }
    }

    private var entries: [PersistentIdentifier: Entry] = [:]

    var count: Int { entries.count }

    /// The strongest way `transaction` matches `query`, or `nil` if it doesn't.
    func tier(of transaction: Transaction, for query: TransactionSearchQuery) -> SearchMatchTier? {
        let entry = entry(for: transaction)
        let direct = Self.tier(of: query.tokens, in: entry)
        guard let layoutTokens = query.layoutTokens else { return direct }
        let viaLayout = Self.tier(of: layoutTokens, in: entry)
        switch (direct, viaLayout) {
        case let (a?, b?): return min(a, b)
        case let (a, b):   return a ?? b
        }
    }

    /// Drop entries for rows that no longer exist. Rows get a new identifier
    /// when an insert is first saved, so without this the index would slowly
    /// collect orphans.
    func prune(keeping ids: Set<PersistentIdentifier>) {
        entries = entries.filter { ids.contains($0.key) }
    }

    // MARK: - Building

    private func entry(for transaction: Transaction) -> Entry {
        let id = transaction.persistentModelID
        let source = Source(transaction)
        if let cached = entries[id], cached.source == source { return cached }
        let folded = HebrewSearch.fold(source.searchableText)
        let words = HebrewSearch.words(ofFolded: folded)
        let entry = Entry(
            source: source,
            folded: folded,
            words: words,
            skeletons: words.map(HebrewSearch.skeleton)
        )
        entries[id] = entry
        return entry
    }

    // MARK: - Matching

    /// Every token has to match; the row matches as weakly as its weakest
    /// token.
    static func tier(of tokens: [String], in entry: Entry) -> SearchMatchTier? {
        var worst = SearchMatchTier.exact
        for token in tokens {
            guard let tier = tier(of: token, in: entry) else { return nil }
            worst = max(worst, tier)
        }
        return worst
    }

    static func tier(of token: String, in entry: Entry) -> SearchMatchTier? {
        if entry.folded.contains(token) { return .exact }
        // Numbers are amounts or dates: a "typo" in one is a different number.
        if token.allSatisfy(\.isNumber) { return nil }
        if token.count >= 3 {
            let skeleton = HebrewSearch.skeleton(token)
            if entry.skeletons.contains(where: { $0.contains(skeleton) }) { return .spelling }
        }
        if entry.words.contains(where: { HebrewSearch.fuzzyMatches(token, word: $0) }) { return .typo }
        return nil
    }
}
