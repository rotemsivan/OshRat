import Testing
import Foundation
import SwiftData
@testable import OshRat

/// The versioned default-category seed, and the editor's name rule.
@MainActor
struct CategorySeedTests {

    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: UserProfile.self, Account.self, Holding.self, Category.self,
                Transaction.self, TransactionAttachment.self, BudgetItem.self,
                Goal.self, FXRateSnapshot.self, UserProgress.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private static func names(_ context: ModelContext) throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<Category>()).map(\.name))
    }

    @Test func anEmptyStoreGetsTheWholeCurrentSet() throws {
        let context = try Self.makeContext()
        SeedData.seedDefaultCategoriesIfNeeded(in: context)

        let names = try Self.names(context)
        #expect(names.isSuperset(of: ["דיור", "חינוך והשכלה", "מינויים", "שונות"]))
        #expect(names.isDisjoint(with: ["שכירות", "לימודים"]))
    }

    /// Every launch runs it; the second run must change nothing.
    @Test func seedingTwiceAddsNothing() throws {
        let context = try Self.makeContext()
        SeedData.seedDefaultCategoriesIfNeeded(in: context)
        let first = try context.fetchCount(FetchDescriptor<Category>())
        SeedData.seedDefaultCategoriesIfNeeded(in: context)
        #expect(try context.fetchCount(FetchDescriptor<Category>()) == first)
        #expect(first == SeedData.defaultCategories().count)
    }

    /// The launch pass merges a duplicated default and tops up the rest from
    /// one fetch: a store holding "דיור" twice ends with exactly the defaults.
    @Test func thePreparePassDedupesThenSeeds() throws {
        let context = try Self.makeContext()
        let rent = try #require(SeedData.defaults.first { $0.name == "דיור" })
        context.insert(rent.makeCategory())
        context.insert(rent.makeCategory())
        try context.save()

        SeedData.prepareCategories(in: context)

        let all = try context.fetch(FetchDescriptor<Category>())
        #expect(all.count == SeedData.defaults.count)
        #expect(all.filter { $0.name == "דיור" }.count == 1)
    }

    /// An existing user's rent keeps its transactions — it's renamed, not
    /// replaced — and the new defaults are added beside it.
    @Test func anOldStoreIsRenamedInPlaceAndGetsTheNewCategories() throws {
        let context = try Self.makeContext()
        let rent = Category(name: "שכירות", kind: .expense, nature: .need)
        let studies = Category(name: "לימודים", kind: .expense, nature: .need)
        [rent, studies].forEach(context.insert)
        let payment = Transaction(amount: 4200, kind: .expense, category: rent)
        context.insert(payment)
        try context.save()

        SeedData.seedDefaultCategoriesIfNeeded(in: context)

        #expect(payment.category?.name == "דיור")
        #expect(studies.name == "חינוך והשכלה")
        let names = try Self.names(context)
        #expect(names.isSuperset(of: ["מינויים", "שונות"]))
        #expect(names.isDisjoint(with: ["שכירות", "לימודים"]))
        #expect(try context.fetchCount(FetchDescriptor<Category>()) == SeedData.defaultCategories().count)
    }

    /// A category the user made under an old default's name is theirs — it's
    /// left alone, and the default is added under its new name.
    @Test func aUsersOwnCategoryIsNeverRenamed() throws {
        let context = try Self.makeContext()
        let own = Category(name: "שכירות", kind: .expense, nature: .need)
        own.isUserCreated = true
        context.insert(own)
        try context.save()

        SeedData.seedDefaultCategoriesIfNeeded(in: context)

        #expect(own.name == "שכירות")
        #expect(try Self.names(context).contains("דיור"))
    }

    /// Defaults can't be deleted from the app, but if one goes missing (an
    /// old build, a bad import) the next launch puts it back.
    @Test func aMissingDefaultIsRestored() throws {
        let context = try Self.makeContext()
        SeedData.seedDefaultCategoriesIfNeeded(in: context)
        let fitness = try #require(try context.fetch(FetchDescriptor<Category>()).first { $0.name == "כושר גופני" })
        context.delete(fitness)
        try context.save()

        SeedData.seedDefaultCategoriesIfNeeded(in: context)

        #expect(try Self.names(context).contains("כושר גופני"))
    }

    // MARK: Name rule

    @Test func aNameIsTakenOnlyWithinItsKind() throws {
        let context = try Self.makeContext()
        let giftsOut = Category(name: "מתנות", kind: .expense)
        context.insert(giftsOut)
        let all = [giftsOut]

        #expect(Category.nameIsTaken(" מתנות ", kind: .expense, among: all))
        #expect(!Category.nameIsTaken("מתנות", kind: .income, among: all))
        // Editing a category may keep its own name.
        #expect(!Category.nameIsTaken("מתנות", kind: .expense, among: all, excluding: giftsOut))
    }
}
