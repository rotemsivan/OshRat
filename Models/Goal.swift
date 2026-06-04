import Foundation
import SwiftData

/// A savings goal or future plan, e.g. "קרן חירום" with a target amount.
@Model
final class Goal {
    var title: String = ""
    var targetAmount: Decimal = 0
    var savedAmount: Decimal = 0
    var targetDate: Date?
    var note: String = ""
    var currencyCode: String = "ILS"
    var isCompleted: Bool = false

    init(
        title: String = "",
        targetAmount: Decimal = 0,
        savedAmount: Decimal = 0,
        targetDate: Date? = nil,
        note: String = "",
        currencyCode: String = "ILS",
        isCompleted: Bool = false
    ) {
        self.title = title
        self.targetAmount = targetAmount
        self.savedAmount = savedAmount
        self.targetDate = targetDate
        self.note = note
        self.currencyCode = currencyCode
        self.isCompleted = isCompleted
    }

    /// Progress from 0 to 1, handy for a progress bar. Guards against divide-by-zero.
    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        let saved = (savedAmount as NSDecimalNumber).doubleValue
        let target = (targetAmount as NSDecimalNumber).doubleValue
        return min(max(saved / target, 0), 1)
    }
}
