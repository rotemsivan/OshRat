import SwiftUI
import SwiftData

/// "Your deposit has matured — where should the money go?"
///
/// Raised by `HomeView` when a savings account reaches its maturity date and
/// the user didn't ask for the payout to happen automatically. A sheet rather
/// than an alert because the user has two things to decide — the amount and
/// the destination — and an alert can hold neither a picker nor a field.
///
/// The amount is pre-filled with the deposit's projected value (principal plus
/// the interest its terms earned) but stays editable: the bank's actual figure
/// is the real one whenever the two disagree, and the app has no way to know
/// it. Confirming writes the interest as income and the move as a transfer —
/// see `DepositPayoutService`.
struct DepositMaturitySheet: View {
    let deposit: Account
    /// Accounts the money could land in — live עו״ש accounts, minus the
    /// deposit itself (filtered by `HomeView.payoutCandidates`).
    let candidates: [Account]
    /// Cached FX, needed only when the deposit and the target are in
    /// different currencies.
    let fxSnapshot: FXRateSnapshot?
    /// Confirmed: pay `amount` into `target`. The parent owns the write.
    let onConfirm: (_ amount: Decimal, _ target: Account) -> Void
    /// "Not now" — leaves the deposit alone; it asks again next launch.
    let onPostpone: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var amount: Decimal
    @State private var targetID: PersistentIdentifier?

    init(
        deposit: Account,
        candidates: [Account],
        fxSnapshot: FXRateSnapshot?,
        onConfirm: @escaping (Decimal, Account) -> Void,
        onPostpone: @escaping () -> Void
    ) {
        self.deposit = deposit
        self.candidates = candidates
        self.fxSnapshot = fxSnapshot
        self.onConfirm = onConfirm
        self.onPostpone = onPostpone
        _amount = State(initialValue: DepositPayoutService.suggestedPayoutAmount(for: deposit))
        // Pre-select the account chosen when the deposit was set up, falling
        // back to the favourite and then to the first candidate — so the
        // common case is "confirm", not "choose".
        _targetID = State(initialValue:
            deposit.payoutAccount?.persistentModelID
            ?? candidates.first(where: \.isFavorite)?.persistentModelID
            ?? candidates.first?.persistentModelID
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                summarySection

                Section {
                    BigAmountField(
                        value: $amount,
                        currencyCode: .constant(deposit.currencyCode),
                        supportedCurrencies: [deposit.currencyCode],
                        isCurrencyLocked: true
                    )
                    .listRowBackground(Color.clear)
                } header: {
                    Text("סכום הפדיון")
                } footer: {
                    Text(amountFooter)
                }

                Section {
                    if candidates.isEmpty {
                        Text("אין חשבון עו״ש להעביר אליו. אפשר להוסיף חשבון עו״ש ולחזור לכאן.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    } else {
                        Picker("חשבון היעד", selection: $targetID) {
                            ForEach(candidates) { account in
                                Text(account.name.isEmpty ? "ללא שם" : account.name)
                                    .tag(PersistentIdentifier?.some(account.persistentModelID))
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                } header: {
                    Text("להעביר אל")
                } footer: {
                    Text(targetFooter)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .font(Theme.Typography.body)
            .navigationTitle(Text("הפיקדון הגיע לפדיון"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("לא עכשיו") {
                        onPostpone()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("העברה") {
                        if let target { onConfirm(amount, target) }
                        dismiss()
                    }
                    .disabled(!canConfirm)
                }
            }
        }
        .tint(Theme.Colors.accent)
    }

    // MARK: - Sections

    /// The deposit's own story: what was put in, on what terms, and what it
    /// grew to. Read-only — the editable parts are below.
    private var summarySection: some View {
        Section {
            LabeledContent("הפיקדון") {
                Text(deposit.name.isEmpty ? "ללא שם" : deposit.name)
            }
            LabeledContent(deposit.isReplenishable ? "סך הכסף בפיקדון" : "סכום ההפקדה") {
                Text(deposit.balance.formatted(.currency(code: deposit.currencyCode)))
                    .monospacedDigit()
            }
            if let rate = deposit.interestRatePercent, rate > 0 {
                LabeledContent("ריבית שנתית") {
                    Text(verbatim: "\(rate.formatted(.number.precision(.fractionLength(0...2))))%")
                        .monospacedDigit()
                }
            }
            // The date the money is actually due — the latest sub-deposit's on
            // a replenishable deposit, which is the one that brought us here.
            if let maturity = deposit.effectiveMaturityDate {
                LabeledContent("מועד הפדיון") {
                    Text(maturity.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
    }

    // MARK: - Derived

    private var target: Account? {
        candidates.first { $0.persistentModelID == targetID }
    }

    /// Blocked only when there's genuinely nothing to do: no target picked, a
    /// non-positive amount, or two currencies with no rate to bridge them.
    private var canConfirm: Bool {
        guard let target, amount > 0 else { return false }
        return DepositPayoutService.canPayOut(deposit, to: target, using: fxSnapshot)
    }

    private var amountFooter: LocalizedStringKey {
        guard let ladder = deposit.depositLadder, ladder.projectedInterest != 0 else {
            return "אפשר לשנות את הסכום למה שהתקבל בפועל."
        }
        let interest = ladder.projectedInterest.formatted(.currency(code: deposit.currencyCode))
        return "כולל ריבית של \(interest) לפי תנאי הפיקדון. אם הבנק שילם סכום אחר — אפשר לתקן כאן, וההפרש יירשם כהכנסה."
    }

    private var targetFooter: LocalizedStringKey {
        guard let target else { return "" }
        if target.currencyCode != deposit.currencyCode {
            return DepositPayoutService.canPayOut(deposit, to: target, using: fxSnapshot)
                ? "הסכום יומר ל-\(target.currencyCode) לפי השער השמור."
                : "שערי חליפין לא זמינים כרגע, ולכן אי אפשר להעביר ל-\(target.currencyCode). אפשר לבחור חשבון ב-\(deposit.currencyCode)."
        }
        return "ההעברה תירשם ביומן התנועות ותעדכן את שתי היתרות."
    }
}
