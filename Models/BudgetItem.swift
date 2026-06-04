import Foundation
import SwiftData

/// One planned line in the monthly budget: how much the user intends to
/// earn or spend in a given category. Used for planned-vs-actual on the dashboard.
@Model
final class BudgetItem {
    var plannedAmount: Decimal = 0
    var kind: TransactionKind = TransactionKind.expense
    var currencyCode: String = "ILS"

    var category: Category?

    init(
        plannedAmount: Decimal = 0,
        kind: TransactionKind = .expense,
        currencyCode: String = "ILS",
        category: Category? = nil
    ) {
        self.plannedAmount = plannedAmount
        self.kind = kind
        self.currencyCode = currencyCode
        self.category = category
    }
}
