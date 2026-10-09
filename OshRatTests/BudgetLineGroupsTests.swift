import Testing
import Foundation
import SwiftData
@testable import OshRat

/// The budget editor's nesting: needs / wants / other → category → line.
@MainActor
struct BudgetLineGroupsTests {

    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: UserProfile.self, Account.self, Holding.self, Category.self,
                Transaction.self, TransactionAttachment.self, BudgetItem.self,
                Goal.self, FXRateSnapshot.self, UserProgress.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private static func groups(_ items: [BudgetItem], fx: FXRateSnapshot? = nil) -> BudgetLineGroups {
        BudgetLineGroups(items: items, preferredCurrency: "ILS", fxSnapshot: fx)
    }

    @Test func bucketsComeInOrderAndEmptyOnesAreDropped() throws {
        let context = try Self.makeContext()
        let dining = Category(name: "מסעדות", kind: .expense, nature: .want)
        let housing = Category(name: "דיור", kind: .expense, nature: .need)
        [dining, housing].forEach(context.insert)
        let items = [
            BudgetItem(plannedAmount: 300, kind: .expense, category: dining),
            BudgetItem(plannedAmount: 4000, kind: .expense, category: housing),
            // Income never appears among the expenses.
            BudgetItem(name: "משכורת", plannedAmount: 12000, kind: .income),
        ]
        items.forEach(context.insert)

        let result = Self.groups(items)
        #expect(result.sections.map(\.bucket) == [.needs, .wants])
        #expect(result.sections[0].monthlyTotal == 4000)
        #expect(result.sections[1].groups.first?.name == "מסעדות")
    }

    @Test func linesWithoutACategoryLandInOther() throws {
        let context = try Self.makeContext()
        let neutral = Category(name: "קניית ני״ע", kind: .expense, nature: .neutral)
        context.insert(neutral)
        let items = [
            BudgetItem(plannedAmount: 100, kind: .expense),
            BudgetItem(plannedAmount: 500, kind: .expense, category: neutral),
        ]
        items.forEach(context.insert)

        let other = try #require(Self.groups(items).sections.only)
        #expect(other.bucket == .other)
        #expect(other.groups.map(\.name) == ["קניית ני״ע", nil])
        #expect(other.groups.last?.id == "")
    }

    @Test func categoriesSortByTotalAndOneTimeLinesAreNotMonthly() throws {
        let context = try Self.makeContext()
        let groceries = Category(name: "סופר", kind: .expense, nature: .need)
        let housing = Category(name: "דיור", kind: .expense, nature: .need)
        [groceries, housing].forEach(context.insert)
        let items = [
            BudgetItem(plannedAmount: 1200, kind: .expense, category: groceries),
            BudgetItem(plannedAmount: 4000, kind: .expense, category: housing),
            // A one-off ₪9,000 renovation isn't ₪9,000 a month.
            BudgetItem(name: "שיפוץ", plannedAmount: 9000, kind: .expense, scheduleKind: .oneTime,
                       scheduleDay: 1, scheduleMonth: 3, scheduleYear: 2027, category: housing),
            // Yearly: a twelfth of it per month.
            BudgetItem(name: "ארנונה", plannedAmount: 2400, kind: .expense, recurrenceUnit: .year, category: housing),
        ]
        items.forEach(context.insert)

        let needs = try #require(Self.groups(items).sections.only)
        #expect(needs.groups.map(\.name) == ["דיור", "סופר"])
        #expect(needs.groups[0].monthlyTotal == 4200)
        #expect(needs.groups[0].lines.count == 3)
        #expect(needs.monthlyTotal == 5400)
    }

    @Test func foreignLinesConvertAndAMissingRateIsFlagged() throws {
        let context = try Self.makeContext()
        let subscriptions = Category(name: "מינויים", kind: .expense, nature: .want)
        context.insert(subscriptions)
        let items = [
            BudgetItem(plannedAmount: 10, kind: .expense, currencyCode: "USD", category: subscriptions),
            BudgetItem(plannedAmount: 20, kind: .expense, currencyCode: "GBP", category: subscriptions),
        ]
        items.forEach(context.insert)
        let fx = FXRateSnapshot(base: "USD", rates: ["ILS": 3.5])

        let result = Self.groups(items, fx: fx)
        #expect(result.sections.first?.monthlyTotal == 35)
        #expect(result.fxUnavailable)
        #expect(Self.groups([items[0]], fx: fx).fxUnavailable == false)
    }

    @Test func aLineWithoutANoteIsTitledByItsSchedule() throws {
        let context = try Self.makeContext()
        let gym = Category(name: "כושר", kind: .expense, nature: .want)
        context.insert(gym)
        let plain = BudgetItem(plannedAmount: 200, kind: .expense, scheduleDay: 10, category: gym)
        let named = BudgetItem(name: "חדר כושר", plannedAmount: 250, kind: .expense, category: gym)
        [plain, named].forEach(context.insert)

        let lines = try #require(Self.groups([plain, named]).sections.only?.groups.only?.lines)
        let titled = try #require(lines.first { $0.id == named.persistentModelID })
        #expect(titled.title == "חדר כושר")
        #expect(titled.subtitle == named.scheduleDescription)
        let untitled = try #require(lines.first { $0.id == plain.persistentModelID })
        #expect(untitled.title == plain.scheduleDescription)
        #expect(untitled.subtitle == nil)
    }
}

private extension Collection {
    /// The single element, or `nil` when there are none or several.
    var only: Element? { count == 1 ? first : nil }
}
