import SwiftUI

/// "Monthly plan" card — the user's budget rolled up into a single
/// total in their preferred currency.
///
/// Layout (one block, no more per-currency stacks):
///   * planned income (green)
///   * needs (red — required spending)
///   * wants (orange — discretionary spending)
///   * a thin proportion bar showing the wants/needs split
///   * net (income − total expense) coloured by sign
///
/// Every line is rolled to a monthly equivalent via
/// `BudgetItem.monthlyEquivalent`, then converted via the FX snapshot
/// into the preferred currency. Lines whose currency can't be
/// converted (no FX cache) are silently dropped — the footer flags
/// this so the total never reads as wrong without context.
struct BudgetSummaryCard: View {
    let budgetItems: [BudgetItem]
    let preferredCurrencyCode: String
    let fxSnapshot: FXRateSnapshot?

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.md) {
            Text("התקציב החודשי")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)

            if budgetItems.isEmpty {
                Text("עדיין לא הוגדר תקציב.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .cardStyle()
    }

    // MARK: - Body

    private var content: some View {
        let totals = combinedTotals
        return VStack(alignment: .trailing, spacing: Theme.Spacing.sm) {
            row(title: "הכנסות מתוכננות", amount: totals.income, color: Theme.Colors.income)
            row(title: "צרכים",            amount: totals.needs,  color: Theme.Colors.expense)
            row(title: "רצונות",           amount: totals.wants,  color: Theme.Colors.wants)

            ProportionBar(needs: totals.needs, wants: totals.wants)

            netRow(net: totals.income - totals.needs - totals.wants)

            fxFootnote
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(
        title: LocalizedStringKey,
        amount: Decimal,
        color: Color
    ) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Text(amount.formatted(.currency(code: preferredCurrencyCode)))
                .font(Theme.Typography.amount)
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
        }
    }

    private func netRow(net: Decimal) -> some View {
        HStack {
            Text("נטו")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(formattedNet(net))
                .font(Theme.Typography.amount)
                .foregroundStyle(net >= 0 ? Theme.Colors.income : Theme.Colors.expense)
                .monospacedDigit()
                // Force LTR on just this Text. The "+/-" prefix is a
                // bidi-neutral character; sitting inside an RTL view
                // it inherits RTL direction and ends up on the visual
                // right of the number. Pinning the text to LTR keeps
                // the sign on the visual left where it reads as a
                // mathematical sign.
                .environment(\.layoutDirection, .rightToLeft)
        }
    }

    @ViewBuilder
    private var fxFootnote: some View {
        if hasCrossCurrencyItems, fxSnapshot == nil {
            Text("שערי חליפין לא זמינים — מוצגים רק פריטים ב-\(preferredCurrencyCode).")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func formattedNet(_ net: Decimal) -> String {
        // Format the *absolute* value and prepend our own sign so the
        // sign placement is ours, not the formatter's. The currency
        // formatter's negative output is locale-dependent (some
        // locales prefix "-", some wrap in parens, some put the sign
        // after the digits) and would defeat the bidi fix below.
        let body = abs(net).formatted(.currency(code: preferredCurrencyCode))
        let sign: String
        if net > 0      { sign = "+" }
        else if net < 0 { sign = "-" }
        else            { sign = "" }
        // Wrap in U+2066 LRI (Left-to-Right Isolate) … U+2069 PDI
        // (Pop Directional Isolate). The "+" and "-" characters are
        // bidi-neutral, so without isolation they'd inherit the
        // surrounding RTL direction from the Hebrew view and end up
        // on the visual right of the number. The isolate pair tells
        // the OS bidi algorithm to render this substring as a single
        // LTR run, keeping the sign on the visual left.
        return "\u{2066}\(sign)\(body)\u{2069}"
    }

    // MARK: - Aggregation

    /// One pass over the budget items: monthly-equivalent each line,
    /// convert into the preferred currency, bucket by income / needs
    /// / wants. Items that can't be converted are dropped.
    private var combinedTotals: (income: Decimal, needs: Decimal, wants: Decimal) {
        var income = Decimal(0)
        var needs = Decimal(0)
        var wants = Decimal(0)

        for item in budgetItems {
            let monthly = item.monthlyEquivalent
            guard let converted = convertToPreferred(monthly, from: item.currencyCode) else { continue }

            switch item.kind {
            case .income:
                income += converted
            case .expense:
                switch item.category?.nature {
                case .need:
                    needs += converted
                case .want:
                    wants += converted
                case .neutral, .none:
                    // Unclassified expense lines lean into "needs" so they're
                    // never silently dropped from the budget.
                    needs += converted
                }
            }
        }
        return (income: income, needs: needs, wants: wants)
    }

    private func convertToPreferred(_ amount: Decimal, from currency: String) -> Decimal? {
        if currency == preferredCurrencyCode { return amount }
        guard let snapshot = fxSnapshot else { return nil }
        return CurrencyConverter.convert(amount, from: currency, to: preferredCurrencyCode, using: snapshot)
    }

    private var hasCrossCurrencyItems: Bool {
        budgetItems.contains { $0.currencyCode != preferredCurrencyCode }
    }
}

/// Two-segment proportional bar: needs (expense colour) vs wants
/// (wants colour). Purely visual — numeric labels live in the rows.
private struct ProportionBar: View {
    let needs: Decimal
    let wants: Decimal

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                Rectangle()
                    .fill(Theme.Colors.expense)
                    .frame(width: geo.size.width * needsShare)
                Rectangle()
                    .fill(Theme.Colors.wants)
                    .frame(width: geo.size.width * wantsShare)
            }
            .clipShape(.capsule)
        }
        .frame(height: 6)
    }

    private var total: Decimal { needs + wants }

    private var needsShare: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(truncating: (needs / total) as NSDecimalNumber)
    }

    private var wantsShare: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(truncating: (wants / total) as NSDecimalNumber)
    }
}

#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        BudgetSummaryCard(budgetItems: [], preferredCurrencyCode: "ILS", fxSnapshot: nil)
            .padding(Theme.Spacing.lg)
    }
}
