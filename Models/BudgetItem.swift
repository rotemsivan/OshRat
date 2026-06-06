import Foundation
import SwiftData

/// One planned line in the user's budget: how much they intend to
/// earn or spend, and how often. Two flavours, distinguished by `kind`:
///
/// * **Income** — `kind = .income`, `name` holds the source label
///   ("משכורת", "עבודה צדדית"), `category` is usually nil.
/// * **Expense** — `kind = .expense`, `category` is required, `name` is
///   an optional free-text note (e.g. "ספר" for a barber under "טיפוח").
///
/// Most budget lines are monthly. `everyXWeeks` covers things like a
/// barber visit every 3 weeks; the dashboard uses `monthlyEquivalent`
/// to roll that into a single monthly total.
@Model
final class BudgetItem {
    /// Free-text label. For income, this is the source name; for
    /// expense, an optional clarifying note about this specific line.
    var name: String = ""

    /// Amount per occurrence. For monthly lines this is also the
    /// monthly total; for `everyXWeeks` lines it's the per-visit amount.
    /// Computed monthly equivalents go through `monthlyEquivalent`.
    var plannedAmount: Decimal = 0

    var kind: TransactionKind = TransactionKind.expense
    var currencyCode: String = "ILS"

    /// Stored raw value of the frequency kind enum; defaults to monthly
    /// because that's far and away the most common cadence.
    var frequencyKindRaw: String = BudgetFrequencyKind.monthly.rawValue

    /// Interval in weeks for `.everyXWeeks` lines. Ignored for monthly.
    /// Stored even when unused so old rows migrate cleanly.
    var frequencyWeeks: Int = 1

    var category: Category?

    init(
        name: String = "",
        plannedAmount: Decimal = 0,
        kind: TransactionKind = .expense,
        currencyCode: String = "ILS",
        frequencyKind: BudgetFrequencyKind = .monthly,
        frequencyWeeks: Int = 1,
        category: Category? = nil
    ) {
        self.name = name
        self.plannedAmount = plannedAmount
        self.kind = kind
        self.currencyCode = currencyCode
        self.frequencyKindRaw = frequencyKind.rawValue
        self.frequencyWeeks = frequencyWeeks
        self.category = category
    }

    // MARK: - Computed

    /// Typed view of the stored raw frequency kind. Fallback to monthly
    /// keeps old rows (pre-migration) working.
    var frequencyKind: BudgetFrequencyKind {
        get { BudgetFrequencyKind(rawValue: frequencyKindRaw) ?? .monthly }
        set { frequencyKindRaw = newValue.rawValue }
    }

    /// Per-month equivalent of this line, for rolling into dashboard
    /// totals. For weekly cadences we approximate "30 days in a month"
    /// because the user-facing question is "roughly per month", not "to
    /// the day exact". For example, every-3-weeks at ₪100 ≈ ₪143/month.
    var monthlyEquivalent: Decimal {
        switch frequencyKind {
        case .monthly:
            return plannedAmount
        case .everyXWeeks:
            let weeks = max(frequencyWeeks, 1)
            // 30 days/month divided by (weeks × 7) gives occurrences/month
            return plannedAmount * (Decimal(30) / Decimal(weeks * 7))
        }
    }
}
