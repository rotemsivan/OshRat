import Testing
import Foundation
import SwiftData
@testable import OshRat

/// The forgiving transactions search: normalization, spelling variants,
/// typo tolerance, wrong-layout recovery and the strict-before-fuzzy rule.
@MainActor
struct TransactionSearchTests {

    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: UserProfile.self, Account.self, Holding.self, Category.self,
                Transaction.self, TransactionAttachment.self, BudgetItem.self,
                Goal.self, FXRateSnapshot.self, UserProgress.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Inserts one expense per title and returns them in order.
    private static func ledger(_ titles: [String], in context: ModelContext) throws -> [Transaction] {
        let rows = titles.map { Transaction(amount: 10, kind: .expense, title: $0) }
        rows.forEach(context.insert)
        try context.save()
        return rows
    }

    private static func search(_ text: String, in rows: [Transaction]) -> TransactionSearchResults {
        let filters = TransactionFilters()
        filters.search = text
        return filters.results(for: rows)
    }

    // MARK: - Normalisation

    @Test func foldingIgnoresFinalLettersNiqqudAndGershayim() {
        #expect(HebrewSearch.fold("ירקן") == HebrewSearch.fold("ירקנ"))
        #expect(HebrewSearch.fold("שָׁלוֹם") == HebrewSearch.fold("שלום"))
        #expect(HebrewSearch.fold("ע״וש") == HebrewSearch.fold("עו\"ש"))
        #expect(HebrewSearch.fold("צ'יפס") == HebrewSearch.fold("ציפס"))
        #expect(HebrewSearch.fold("  בית-קפה ,  תל אביב ") == "בית קפה תל אביב")
    }

    // MARK: - Typos

    @Test func aNeighbouringKeyTypoFindsTheWord() throws {
        let context = try Self.makeContext()
        let rows = try Self.ledger(["ירקן", "סופר", "דלק"], in: context)

        // ק sits right beside ר on the Hebrew keyboard.
        let results = Self.search("יקקן", in: rows)
        #expect(results.rows.map(\.title) == ["ירקן"])
        #expect(results.isApproximate)
    }

    @Test func aPartlyTypedTypoAlreadyMatches() throws {
        let context = try Self.makeContext()
        let rows = try Self.ledger(["ירקן", "סופר"], in: context)

        #expect(Self.search("יקק", in: rows).rows.map(\.title) == ["ירקן"])
    }

    @Test func shortTokensMustBeExact() throws {
        let context = try Self.makeContext()
        let rows = try Self.ledger(["ירקן"], in: context)

        // Two letters are a prefix, not a word to correct.
        #expect(Self.search("יק", in: rows).rows.isEmpty)
        // Three letters forgive a neighbouring key only: ל is nowhere near ר.
        #expect(Self.search("ילק", in: rows).rows.isEmpty)
    }

    @Test func exactMatchesHideTypoMatches() throws {
        let context = try Self.makeContext()
        // "סופג" is one neighbouring-key slip (ג beside ר) from "סופר" — but
        // "סופר" matches as typed, so the near miss stays out of the way.
        let rows = try Self.ledger(["סופר", "סופג"], in: context)

        let results = Self.search("סופר", in: rows)
        #expect(results.rows.map(\.title) == ["סופר"])
        #expect(!results.isApproximate)
    }

    // MARK: - Spelling and layout

    @Test func pleneAndDefectiveSpellingsMeet() throws {
        let context = try Self.makeContext()
        let rows = try Self.ledger(["תוכנית חיסכון", "שכירות"], in: context)

        let results = Self.search("תכנית", in: rows)
        #expect(results.rows.map(\.title) == ["תוכנית חיסכון"])
        #expect(!results.isApproximate)
    }

    @Test func aQueryTypedOnTheEnglishLayoutIsReadAsHebrew() throws {
        let context = try Self.makeContext()
        let rows = try Self.ledger(["ירקן", "Netflix"], in: context)

        // ירקן with the keyboard left on English.
        #expect(Self.search("hrei", in: rows).rows.map(\.title) == ["ירקן"])
        // …without breaking a search that really is in English.
        #expect(Self.search("netf", in: rows).rows.map(\.title) == ["Netflix"])
    }

    // MARK: - Fields

    @Test func everyTokenMustMatchSomewhere() throws {
        let context = try Self.makeContext()
        let supermarket = Category(name: "סופר", kind: .expense)
        let fuel = Category(name: "דלק", kind: .expense)
        context.insert(supermarket)
        context.insert(fuel)
        let a = Transaction(amount: 300, kind: .expense, title: "שופרסל", category: supermarket)
        let b = Transaction(amount: 200, kind: .expense, title: "פז", category: fuel)
        [a, b].forEach(context.insert)
        try context.save()

        #expect(Self.search("סופר שופרסל", in: [a, b]).rows == [a])
        #expect(Self.search("סופר פז", in: [a, b]).rows.isEmpty)
    }

    @Test func accountNamesAndAmountsAreSearchable() throws {
        let context = try Self.makeContext()
        let wallet = Account(name: "ביט", type: .digitalWallet, currencyCode: "ILS")
        context.insert(wallet)
        let coffee = Transaction(amount: Decimal(string: "120.5")!, kind: .expense, title: "קפה", account: wallet)
        let rent = Transaction(amount: 4200, kind: .expense, title: "שכירות")
        [coffee, rent].forEach(context.insert)
        try context.save()

        #expect(Self.search("ביט", in: [coffee, rent]).rows == [coffee])
        #expect(Self.search("120", in: [coffee, rent]).rows == [coffee])
        // A number is never "corrected" into a nearby one.
        #expect(Self.search("121", in: [coffee, rent]).rows.isEmpty)
    }

    @Test func anEditedTitleIsPickedUpByTheNextSearch() throws {
        let context = try Self.makeContext()
        let rows = try Self.ledger(["סופר"], in: context)
        let filters = TransactionFilters()

        filters.search = "ירקן"
        #expect(filters.results(for: rows).rows.isEmpty)

        rows[0].title = "ירקן"
        #expect(filters.results(for: rows).rows == rows)
    }

    @Test func punctuationOnlyIsNotASearch() throws {
        let context = try Self.makeContext()
        let rows = try Self.ledger(["סופר", "ירקן"], in: context)

        #expect(Self.search(" ״ - ", in: rows).rows.count == 2)
    }
}
