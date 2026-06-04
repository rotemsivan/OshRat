import Foundation
import SwiftData

/// A grouping for transactions, e.g. "מזון", "שכר דירה", "משכורת".
/// Each category is either an income or an expense category.
@Model
final class Category {
    var name: String = ""
    var kind: TransactionKind = TransactionKind.expense
    /// Hex colour like "#E57373" — used for the tag/dot colour in the UI.
    var colorHex: String = "#9E9E9E"
    /// An SF Symbol name for the icon, e.g. "cart" or "house".
    var symbolName: String = "tag"

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction] = []

    init(
        name: String = "",
        kind: TransactionKind = .expense,
        colorHex: String = "#9E9E9E",
        symbolName: String = "tag"
    ) {
        self.name = name
        self.kind = kind
        self.colorHex = colorHex
        self.symbolName = symbolName
    }
}
