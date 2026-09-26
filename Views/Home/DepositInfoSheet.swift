import SwiftUI
import SwiftData

/// "What exactly is this deposit?" — the read-only counterpart to the account
/// editor, opened from the little "i" beside a deposit row on the dashboard.
///
/// Two halves, in the order the questions get asked: the deposit's **terms**
/// (what was put in, on what terms, what it's worth now, where it pays out),
/// then its **history** — the ledger rows that actually touched it. Nothing
/// here is editable; the editor is one tap away on the row itself, and mixing
/// "read the facts" with "change the facts" is what made the maturity prompt
/// confusing to begin with.
struct DepositInfoSheet: View {
    let deposit: Account

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                termsSection
                // Only a replenishable deposit has rungs worth listing — a
                // one-time one *is* its single rung, already described above.
                if deposit.isReplenishable {
                    ladderSection
                }
                // `progress` is nil without a maturity date to be a fraction
                // of, which is exactly when the bar would be meaningless.
                if let ladder = deposit.depositLadder, let progress = ladder.progress() {
                    progressSection(progress)
                }
                historySection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .font(Theme.Typography.body)
            .navigationTitle(Text("פרטי הפיקדון"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סגירה") { dismiss() }
                }
            }
        }
        .tint(Theme.Colors.accent)
    }

    // MARK: - Terms

    /// The deposit's identity card. Every row is conditional: an open-ended
    /// savings pot with no rate and no maturity legitimately has almost
    /// nothing to say, and empty "—" rows would be worse than absent ones.
    private var termsSection: some View {
        Section {
            LabeledContent("שם") {
                Text(deposit.name.isEmpty ? "ללא שם" : deposit.name)
            }

            LabeledContent(balanceLabel) {
                Text(deposit.balance.formatted(.currency(code: deposit.currencyCode)))
                    .monospacedDigit()
            }

            if deposit.isReplenishable {
                LabeledContent("סוג") {
                    Text(DepositKind.replenishable.hebrewLabel)
                }
            }

            if let rate = deposit.interestRatePercent, rate > 0 {
                LabeledContent(deposit.isReplenishable ? "ריבית שנתית (ברירת מחדל)" : "ריבית שנתית") {
                    Text(verbatim: "\(rate.formatted(.number.precision(.fractionLength(0...2))))%")
                        .monospacedDigit()
                }
            }

            if let start = deposit.depositStartDate {
                LabeledContent("תאריך הפקדה") {
                    Text(start.formatted(date: .abbreviated, time: .omitted))
                }
            }

            // The date the whole deposit comes due — the latest of its
            // sub-deposits when there's more than one.
            if let maturity = deposit.effectiveMaturityDate {
                LabeledContent("מועד הפדיון") {
                    Text(maturity.formatted(date: .abbreviated, time: .omitted))
                }
            }

            accruedInterestRow
            projectedRow
            payoutTargetRow

            LabeledContent("סטטוס") {
                Text(statusText)
                    .foregroundStyle(statusColor)
            }
        } header: {
            Text("תנאי הפיקדון")
        } footer: {
            Text(termsFooter)
        }
    }

    /// Interest earned *so far*, as distinct from the projection below.
    /// Hidden once the deposit has been paid out: at that point the balance is
    /// zero, so `DepositTerms` would compute today's accrual off a principal
    /// of nothing and report ₪0 — technically true and completely misleading.
    /// The history section is where a settled deposit's interest actually is.
    @ViewBuilder
    private var accruedInterestRow: some View {
        if deposit.payoutCompletedAt == nil,
           let ladder = deposit.depositLadder,
           case let accrued = ladder.value(asOf: .now) - ladder.principal,
           accrued != 0 {
            LabeledContent("ריבית שנצברה") {
                Text(accrued.formatted(.currency(code: deposit.currencyCode)))
                    .foregroundStyle(Theme.Colors.income)
                    .monospacedDigit()
            }
        }
    }

    /// What the terms say it pays at maturity. Same figure the payout prompt
    /// pre-fills, so the two screens can't disagree.
    @ViewBuilder
    private var projectedRow: some View {
        if deposit.payoutCompletedAt == nil,
           let ladder = deposit.depositLadder,
           ladder.projectedInterest != 0 {
            LabeledContent("צפוי בפדיון") {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(ladder.projectedValue.formatted(.currency(code: deposit.currencyCode)))
                        .font(Theme.Typography.amount)
                        .monospacedDigit()
                    Text("ריבית \(ladder.projectedInterest.formatted(.currency(code: deposit.currencyCode)))")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.income)
                        .monospacedDigit()
                }
            }
        }
    }

    /// Where the money goes (or went). Only meaningful for a deposit with a
    /// maturity date — an open pot never pays out.
    @ViewBuilder
    private var payoutTargetRow: some View {
        if deposit.effectiveMaturityDate != nil {
            LabeledContent("חשבון היעד") {
                if let target = deposit.payoutAccount {
                    Text(target.name.isEmpty ? "ללא שם" : target.name)
                } else {
                    Text("ייבחר בפדיון")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    /// After a payout the balance is zero and "סכום ההפקדה" would be a lie,
    /// so the label follows the deposit's state rather than being fixed.
    private var balanceLabel: LocalizedStringKey {
        guard deposit.payoutCompletedAt == nil else { return "יתרה נוכחית" }
        return deposit.isReplenishable ? "סך הכסף בפיקדון" : "סכום ההפקדה"
    }

    private var statusText: LocalizedStringKey {
        if let paidOut = deposit.payoutCompletedAt {
            return "נפדה ב-\(paidOut.formatted(date: .abbreviated, time: .omitted))"
        }
        if deposit.isAwaitingPayout() { return "ממתין לפדיון" }
        if let days = deposit.depositLadder?.daysRemaining(), days > 0 {
            // `String(localized:)` so the day count gets proper Hebrew plurals
            // from the catalog (יום אחד / יומיים / N ימים).
            return "פעיל • \(String(localized: "עוד \(days) ימים"))"
        }
        return "חיסכון פתוח"
    }

    private var statusColor: Color {
        if deposit.payoutCompletedAt != nil { return Theme.Colors.textSecondary }
        return deposit.isAwaitingPayout() ? Theme.Colors.wants : Theme.Colors.textPrimary
    }

    private var termsFooter: LocalizedStringKey {
        if deposit.payoutCompletedAt != nil {
            return "הפיקדון נפדה. החשבון נשאר כאן עם התנאים שלו כדי שאפשר יהיה לראות מה היה."
        }
        if deposit.isAwaitingPayout() {
            return "הפיקדון הגיע לפדיון והכסף עדיין בו. אפשר להעביר אותו מהתזכורת שתיפתח, או לערוך את החשבון."
        }
        guard deposit.depositLadder != nil else {
            return "חיסכון פתוח בלי תאריך פדיון — לא תופיע תזכורת ולא תירשם העברה."
        }
        if deposit.isReplenishable {
            return "כל הפקדה צוברת ריבית פשוטה לפי התנאים שלה, והפיקדון כולו נפדה כשההפקדה האחרונה מגיעה לפדיון."
        }
        return "הריבית מחושבת ריבית פשוטה לפי הימים שחלפו. בפדיון אפשר לתקן לסכום שהבנק שילם בפועל."
    }

    // MARK: - Sub-deposits

    /// The rungs of a replenishable deposit: the opening amount, then one row
    /// per transfer that added to it. Each is a deposit in its own right, so
    /// each shows its own amount, term and rate — and each (bar the opening,
    /// which has no row of its own) can be opened and corrected when the bank's
    /// terms turn out to differ from the defaults.
    private var ladderSection: some View {
        Section {
            if deposit.openingDepositAmount > 0 {
                DepositTrancheRow(
                    title: String(localized: "הפקדה ראשונה"),
                    amount: deposit.openingDepositAmount,
                    currencyCode: deposit.currencyCode,
                    startDate: deposit.depositStartDate ?? deposit.lastUpdated,
                    maturityDate: deposit.maturityDate,
                    ratePercent: deposit.interestRatePercent
                )
            }

            ForEach(deposit.liveDepositTranches) { tranche in
                NavigationLink {
                    DepositTrancheEditorView(tranche: tranche, deposit: deposit)
                } label: {
                    DepositTrancheRow(
                        title: tranche.note.isEmpty ? String(localized: "הפקדה") : tranche.note,
                        amount: tranche.amount,
                        currencyCode: deposit.currencyCode,
                        startDate: tranche.startDate,
                        maturityDate: tranche.maturityDate ?? deposit.maturityDate,
                        ratePercent: tranche.interestRatePercent ?? deposit.interestRatePercent
                    )
                }
            }
        } header: {
            Text("ההפקדות בפיקדון")
        } footer: {
            Text(ladderFooter)
        }
    }

    private var ladderFooter: LocalizedStringKey {
        if deposit.liveDepositTranches.isEmpty {
            return "כל העברה לפיקדון הזה תופיע כאן כהפקדה נפרדת, עם התקופה והריבית שלה."
        }
        return "אפשר לפתוח כל הפקדה ולתקן את הריבית ומועד הפדיון שלה למה שסוכם בבנק."
    }

    // MARK: - Progress

    /// How far through the term the deposit is. Only drawn when there's a real
    /// term to be a fraction of — `DepositTerms.progress` returns `nil`
    /// without a maturity date.
    private func progressSection(_ progress: Double) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ProgressView(value: progress)
                    .tint(Theme.Colors.accent)
                HStack {
                    Text(deposit.depositStartDate?.formatted(date: .numeric, time: .omitted) ?? "")
                    Spacer(minLength: Theme.Spacing.sm)
                    Text(deposit.effectiveMaturityDate?.formatted(date: .numeric, time: .omitted) ?? "")
                }
                .font(Theme.Typography.captionSmall)
                .foregroundStyle(Theme.Colors.textSecondary)
                .monospacedDigit()
            }
            .listRowBackground(Color.clear)
        } header: {
            Text("מסלול הפיקדון")
        }
    }

    // MARK: - History

    /// Every ledger row that touched this deposit, newest first.
    private var historySection: some View {
        Section {
            if entries.isEmpty {
                Text("עדיין אין תנועות בפיקדון הזה.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                ForEach(entries) { entry in
                    HStack(spacing: Theme.Spacing.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }

                        Spacer(minLength: Theme.Spacing.sm)

                        Text(entry.signedAmount.formattedSignedCurrency(entry.currencyCode))
                            .font(Theme.Typography.amount)
                            .foregroundStyle(entry.signedAmount < 0 ? Theme.Colors.expense : Theme.Colors.income)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .layoutPriority(1)
                    }
                }
            }
        } header: {
            Text("היסטוריה")
        } footer: {
            Text("כל תנועה שנרשמה על הפיקדון — הפקדות, ריבית והעברות. מחיקה ושחזור נעשים ביומן התנועות.")
        }
    }

    private var entries: [DepositHistoryEntry] {
        DepositHistoryEntry.entries(for: deposit)
    }
}

// MARK: - Sub-deposit row

/// One rung of a replenishable deposit, as a plain read-only row: what went in,
/// over what window, at what rate.
///
/// Takes values rather than the `DepositTranche` model so the same row can draw
/// the *opening* deposit, which has no row of its own in the store (see
/// `DepositLadder.make`).
private struct DepositTrancheRow: View {
    let title: String
    let amount: Decimal
    let currencyCode: String
    let startDate: Date
    let maturityDate: Date?
    let ratePercent: Decimal?

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: Theme.Spacing.sm)

            Text(amount.formatted(.currency(code: currencyCode)))
                .font(Theme.Typography.amount)
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(1)
        }
    }

    /// Numeric dates, like the assets-card subtitle: this is one line under a
    /// title, and the spelled-out form ran past it.
    private var subtitle: String {
        var parts: [String] = [startDate.formatted(date: .numeric, time: .omitted)]
        if let maturityDate {
            parts.append(maturityDate.formatted(date: .numeric, time: .omitted))
        }
        // Opens with U+200F (RIGHT-TO-LEFT MARK). Nothing else in this line is
        // a Hebrew letter — numeric dates, an arrow, a percentage — so without
        // it the text system has no direction to go on, lays the line out
        // left-to-right, and the arrow points back from the maturity date to
        // the start. The mark makes it read start ← maturity, right to left.
        var text = "\u{200F}" + parts.joined(separator: " ← ")
        if let ratePercent, ratePercent > 0 {
            text += " • \(ratePercent.formatted(.number.precision(.fractionLength(0...2))))%"
        }
        return text
    }
}

// MARK: - Sub-deposit editor

/// Correct one sub-deposit's terms.
///
/// The rung was created from a transfer with the deposit's defaults, which is
/// right most of the time and wrong exactly when the bank quoted something
/// else for that particular deposit — so rate and maturity are editable and
/// nothing else is. The amount isn't: it's what the transfer actually moved,
/// and changing it here would put the ladder and the ledger at odds (edit the
/// transfer instead, or delete it and enter it again).
private struct DepositTrancheEditorView: View {
    /// Held plainly, not `@Bindable`: nothing here binds straight to the model.
    /// The two editable fields are optional in the store and non-optional in
    /// their controls, so they go through `@State` and are written back on save.
    let tranche: DepositTranche
    let deposit: Account

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @ScaledMetric(relativeTo: .body) private var rateFieldWidth: CGFloat = 56

    /// Bound copies of the two optional stored fields. `DecimalField` and
    /// `DatePicker` both want a non-optional, and the mapping back to `nil`
    /// (no rate agreed / open-ended) happens once, on save.
    @State private var ratePercent: Decimal
    @State private var hasMaturityDate: Bool
    @State private var maturityDate: Date

    init(tranche: DepositTranche, deposit: Account) {
        self.tranche = tranche
        self.deposit = deposit
        let maturity = tranche.maturityDate ?? deposit.maturityDate
        _ratePercent = State(initialValue: tranche.interestRatePercent ?? deposit.interestRatePercent ?? 0)
        _hasMaturityDate = State(initialValue: maturity != nil)
        _maturityDate = State(
            initialValue: maturity
                ?? deposit.defaultTrancheMaturityDate(fundedOn: tranche.startDate)
                ?? AccountDraft.defaultMaturityDate(from: tranche.startDate)
        )
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("סכום ההפקדה") {
                    Text(tranche.amount.formatted(.currency(code: deposit.currencyCode)))
                        .monospacedDigit()
                }
                LabeledContent("תאריך ההפקדה") {
                    Text(tranche.startDate.formatted(date: .abbreviated, time: .omitted))
                }
            } footer: {
                Text("הסכום והתאריך נקבעים לפי ההעברה שפתחה את ההפקדה. לשינוי שלהם צריך לערוך את ההעברה ביומן התנועות.")
            }

            Section {
                LabeledContent("ריבית שנתית") {
                    HStack(spacing: Theme.Spacing.xs) {
                        DecimalField(placeholder: "0", value: $ratePercent)
                            .frame(width: rateFieldWidth)
                        Text(verbatim: "%")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }

                Toggle("תאריך פדיון", isOn: $hasMaturityDate.animation(.easeInOut(duration: 0.2)))

                if hasMaturityDate {
                    DatePicker(
                        "מועד הפדיון",
                        selection: $maturityDate,
                        in: tranche.startDate...,
                        displayedComponents: .date
                    )
                }

                if case let terms = previewTerms, terms.projectedInterest != 0 {
                    LabeledContent("צפוי בפדיון") {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(terms.projectedValue.formatted(.currency(code: deposit.currencyCode)))
                                .font(Theme.Typography.amount)
                                .monospacedDigit()
                            Text("ריבית \(terms.projectedInterest.formatted(.currency(code: deposit.currencyCode)))")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.income)
                                .monospacedDigit()
                        }
                    }
                }
            } header: {
                Text("תנאי ההפקדה")
            } footer: {
                Text("הפיקדון כולו נפדה במועד המאוחר מבין ההפקדות, ולכן דחייה של ההפקדה הזו עשויה לדחות גם אותו.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .font(Theme.Typography.body)
        .navigationTitle(Text("עריכת הפקדה"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("שמירה") {
                    save()
                    dismiss()
                }
            }
        }
    }

    private var previewTerms: DepositTerms {
        DepositTerms(
            principal: tranche.amount,
            annualRatePercent: ratePercent > 0 ? ratePercent : nil,
            startDate: tranche.startDate,
            maturityDate: hasMaturityDate ? maturityDate : nil
        )
    }

    private func save() {
        tranche.interestRatePercent = ratePercent > 0 ? ratePercent : nil
        tranche.maturityDate = hasMaturityDate ? maturityDate : nil
        try? modelContext.save()
    }
}

// MARK: - History entry

/// One line of a deposit's story, normalised from the two sides a deposit can
/// appear on: rows where it is the *source* (`Account.transactions` — the
/// interest credit, a manual balance edit, the payout transfer leaving it) and
/// rows where it is the *destination* (`Account.incomingTransfers` — money
/// moved in to fund it).
///
/// Co-located with the sheet rather than split out, matching the way the other
/// feature-local helper types in this project sit beside their view.
struct DepositHistoryEntry: Identifiable {
    let id: PersistentIdentifier
    let date: Date
    let title: String
    /// Signed from *this deposit's* point of view: positive when money landed
    /// in it, negative when money left.
    ///
    /// Deliberately unlike the global transactions list, which shows transfers
    /// unsigned because moving money between your own accounts is neutral to
    /// net worth. Here the whole frame is one account, and a payout that
    /// emptied it reads as a fiction if it isn't negative.
    let signedAmount: Decimal
    let currencyCode: String

    static func entries(for deposit: Account) -> [DepositHistoryEntry] {
        var rows: [DepositHistoryEntry] = []

        // Money leaving, or logged against, the deposit.
        for transaction in deposit.transactions where transaction.deletedAt == nil {
            let outgoing = transaction.isTransfer || transaction.kind == .expense
            rows.append(
                DepositHistoryEntry(
                    id: transaction.persistentModelID,
                    date: transaction.date,
                    title: displayTitle(for: transaction, incoming: false),
                    signedAmount: outgoing ? -transaction.amount : transaction.amount,
                    currencyCode: transaction.currencyCode
                )
            )
        }

        // Money arriving as a transfer — credited in the deposit's own
        // currency, which is what `destinationAmount` already holds.
        for transaction in deposit.incomingTransfers where transaction.deletedAt == nil {
            rows.append(
                DepositHistoryEntry(
                    id: transaction.persistentModelID,
                    date: transaction.date,
                    title: displayTitle(for: transaction, incoming: true),
                    signedAmount: transaction.destinationAmount ?? transaction.amount,
                    currencyCode: deposit.currencyCode
                )
            )
        }

        return rows.sorted { $0.date > $1.date }
    }

    private static func displayTitle(for transaction: Transaction, incoming: Bool) -> String {
        let trimmed = transaction.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if transaction.isTransfer { return incoming ? "הפקדה" : "העברה" }
        return transaction.category?.name ?? "ללא שם"
    }
}

#Preview {
    DepositInfoSheet(
        deposit: Account(
            name: "פיקדון שנתי",
            type: .savings,
            balance: 50_000,
            currencyCode: "ILS",
            interestRatePercent: 4.2,
            depositStartDate: .now.addingTimeInterval(-60 * 60 * 24 * 200),
            maturityDate: .now.addingTimeInterval(60 * 60 * 24 * 165)
        )
    )
}
