import SwiftUI

/// "This month" card — actual income vs actual expenses, rolled up
/// into a single total in the user's preferred currency.
///
/// Same shape as `BudgetSummaryCard`, so the eye sweeps cleanly from
/// "planned" to "actual" without re-orienting. Transactions in
/// non-preferred currencies are converted via the FX snapshot; if
/// the snapshot is missing, those transactions are skipped and the
/// footer flags it.
struct MonthlySummaryCard: View {
    let transactions: [Transaction]
    let preferredCurrencyCode: String
    let fxSnapshot: FXRateSnapshot?

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.md) {
            HStack {
                Text("החודש")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .textCase(.uppercase)
                Spacer()
                Text(currentMonthLabel)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if thisMonthsTransactions.isEmpty {
                Text("עדיין לא נרשמו עסקאות החודש.")
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
        let net = totals.income - totals.expense
        return VStack(alignment: .trailing, spacing: Theme.Spacing.sm) {
            row(title: "הכנסות", amount: totals.income, color: Theme.Colors.income)
            row(title: "הוצאות", amount: totals.expense, color: Theme.Colors.expense)

            ProportionBar(income: totals.income, expense: totals.expense)

            HStack {
                Text("נטו")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text(formattedNet(net))
                    .font(Theme.Typography.amount)
                    .foregroundStyle(net >= 0 ? Theme.Colors.income : Theme.Colors.expense)
                    .monospacedDigit()
                    // Same RTL/sign fix as BudgetSummaryCard — the
                    // "+/-" prefix is bidi-neutral and would otherwise
                    // sit on the visual right of the number inside an
                    // RTL view. Force LTR to keep the sign on the left.
                    .environment(\.layoutDirection, .leftToRight)
            }

            fxFootnote
                .frame(maxWidth: .infinity, alignment: .trailing)
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

    @ViewBuilder
    private var fxFootnote: some View {
        if hasCrossCurrencyTransactions, fxSnapshot == nil {
            Text("שערי חליפין לא זמינים — מוצגות רק עסקאות ב-\(preferredCurrencyCode).")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func formattedNet(_ net: Decimal) -> String {
        // Format `abs(net)` and prepend our own sign so the sign
        // placement is ours, not the formatter's (whose negative
        // output is locale-dependent and would defeat the bidi fix).
        let body = abs(net).formatted(.currency(code: preferredCurrencyCode))
        let sign: String
        if net > 0      { sign = "+" }
        else if net < 0 { sign = "-" }
        else            { sign = "" }
        // LRI … PDI — see BudgetSummaryCard for the full reasoning.
        // The bidi-neutral "+"/"-" inherits RTL from the Hebrew view
        // and sits on the visual right of the number without this.
        return "\u{2066}\(sign)\(body)\u{2069}"
    }

    // MARK: - Computed data

    private var thisMonthsTransactions: [Transaction] {
        guard let monthInterval = Calendar.current.dateInterval(of: .month, for: Date()) else {
            return []
        }
        // Manual balance-edit rows (inserted whenever the user retypes
        // an account's cash balance) are deliberately excluded: they're
        // a bookkeeping artefact, not real income or expense, so
        // letting them roll into the monthly totals would inflate both
        // sides of "income vs expense" and skew the net. Transfers are
        // excluded for the same reason — money moving between the user's
        // own accounts is neither income nor expense.
        return transactions.filter { tx in
            monthInterval.contains(tx.date) && !tx.isManualBalanceEdit && !tx.isTransfer
        }
    }

    /// Bucket this month's transactions into income vs expense,
    /// converted to the preferred currency. Drops anything we can't
    /// convert (footer warns the user).
    private var combinedTotals: (income: Decimal, expense: Decimal) {
        var income = Decimal(0)
        var expense = Decimal(0)
        for tx in thisMonthsTransactions {
            guard let converted = convertToPreferred(tx.amount, from: tx.currencyCode) else { continue }
            switch tx.kind {
            case .income:  income += converted
            case .expense: expense += converted
            }
        }
        return (income: income, expense: expense)
    }

    private func convertToPreferred(_ amount: Decimal, from currency: String) -> Decimal? {
        if currency == preferredCurrencyCode { return amount }
        guard let snapshot = fxSnapshot else { return nil }
        return CurrencyConverter.convert(amount, from: currency, to: preferredCurrencyCode, using: snapshot)
    }

    private var hasCrossCurrencyTransactions: Bool {
        thisMonthsTransactions.contains { $0.currencyCode != preferredCurrencyCode }
    }

    private var currentMonthLabel: String {
        Date.now.formatted(
            .dateTime
                .locale(Locale(identifier: "he_IL"))
                .month(.wide)
                .year()
        )
    }
}

/// Income/expense proportional bar using the design system's semantic
/// money colours.
private struct ProportionBar: View {
    let income: Decimal
    let expense: Decimal

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                Rectangle()
                    .fill(Theme.Colors.income)
                    .frame(width: geo.size.width * incomeShare)
                Rectangle()
                    .fill(Theme.Colors.expense)
                    .frame(width: geo.size.width * expenseShare)
            }
            .clipShape(.capsule)
        }
        .frame(height: 6)
    }

    private var total: Decimal { income + expense }

    private var incomeShare: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(truncating: (income / total) as NSDecimalNumber)
    }

    private var expenseShare: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(truncating: (expense / total) as NSDecimalNumber)
    }
}

#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        MonthlySummaryCard(transactions: [], preferredCurrencyCode: "ILS", fxSnapshot: nil)
            .padding(Theme.Spacing.lg)
    }
}
