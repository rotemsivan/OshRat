import Foundation

// MARK: - The workbook, as plain values
//
// What an export *says*, with no file format in it: sheets made of blocks
// (KPI cards, tables), tables made of rows of cells, and each cell tagged
// with a semantic role (`ExportRole`) rather than a colour or a font. The
// writers decide what a role looks like — `XLSXWriter` dresses it in the
// app's palette, `CSVWriter` ignores it — so every design decision lives in
// one place and this side stays testable by value.
//
// `nonisolated` + `Sendable`: the workbook is built on the main actor (it
// reads SwiftData models) and then handed to a background task to encode.

/// One cell's content. Dates and times are already resolved to calendar
/// components, so the writers need no calendar or time zone of their own.
nonisolated enum ExportValue: Equatable, Sendable {
    case empty
    case text(String)
    case number(Decimal)
    case date(year: Int, month: Int, day: Int)
    case time(hour: Int, minute: Int)
}

/// What a figure means — the writer colours it from this.
nonisolated enum ExportTone: Hashable, Sendable {
    case neutral, income, expense, wants, muted

    /// Green when positive, red when negative: a net figure.
    static func signed(_ value: Decimal) -> ExportTone {
        value < 0 ? .expense : (value > 0 ? .income : .neutral)
    }
}

/// How a budget's "used" share reads — the same thresholds as the app's bar
/// (`TransactionsListView.budgetColor`): room left, close to the plan, over.
nonisolated enum ExportBudgetTone: Hashable, Sendable {
    case onTrack, nearLimit, over, income

    static func expense(planned: Decimal, actual: Decimal) -> ExportBudgetTone {
        guard planned > 0 else { return .onTrack }
        if actual > planned { return .over }
        return actual / planned >= Decimal(string: "0.9")! ? .nearLimit : .onTrack
    }
}

/// A cell's semantic role.
nonisolated enum ExportRole: Hashable, Sendable {
    case text
    case mutedText
    case date
    case time
    /// An amount in the account's own currency, with no symbol (the next
    /// column names the currency).
    case amount(ExportTone)
    /// An amount in the workbook's preferred currency, symbol included.
    case money(ExportTone)
    /// A budget difference: plain when there's room left, "חריגה של …" in red
    /// when it's negative.
    case budgetDifference
    case percent
    /// A budget's used share, drawn with a progress bar in its tone.
    case budgetPercent(ExportBudgetTone)
    case count
    /// A category name on a tint of the category's own colour
    /// — the app's category badge.
    case category(colorHex: String)
}

nonisolated struct ExportCell: Equatable, Sendable {
    var value: ExportValue
    var role: ExportRole
    /// How many columns the cell spans (merged to its left in an RTL sheet).
    var span: Int = 1

    static let empty = ExportCell(value: .empty, role: .text)

    static func text(_ string: String, _ role: ExportRole = .text, span: Int = 1) -> ExportCell {
        ExportCell(value: string.isEmpty ? .empty : .text(string), role: role, span: span)
    }

    /// A figure, or an empty cell when there isn't one (no FX rate, say) —
    /// never a misleading zero.
    static func number(_ value: Decimal?, _ role: ExportRole) -> ExportCell {
        ExportCell(value: value.map { .number($0) } ?? .empty, role: role)
    }
}

nonisolated struct ExportRow: Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        case body
        /// A group heading inside a table (a month, נזיל / נכסים), carrying the
        /// group's own subtotals.
        case group
        /// The table's closing total.
        case total
    }

    var cells: [ExportCell]
    var kind: Kind = .body
}

nonisolated struct ExportColumn: Equatable, Sendable {
    var header: String
    /// Width in Excel's character units.
    var width: Double
}

nonisolated struct ExportTable: Equatable, Sendable {
    /// A small heading above the table, for sheets holding more than one.
    var caption: String?
    var columns: [ExportColumn]
    var rows: [ExportRow]
    /// Shown as a single row when there are no rows at all.
    var emptyNote: String?
    /// The sheet's main table: its header row is frozen and filterable.
    var isPrimary = false
}

/// One of the dashboard-style figures on the overview sheet.
nonisolated struct ExportKPI: Equatable, Sendable {
    var label: String
    var value: Decimal
    var tone: ExportTone
}

nonisolated enum ExportBlock: Equatable, Sendable {
    case cards([ExportKPI])
    case table(ExportTable)
}

nonisolated struct ExportSheet: Equatable, Sendable {
    var name: String
    /// The line under the title — the range and the currency.
    var subtitle: String
    var blocks: [ExportBlock]

    /// The sheet's tables, in order.
    var tables: [ExportTable] {
        blocks.compactMap { if case .table(let table) = $0 { table } else { nil } }
    }
}

nonisolated struct ExportWorkbook: Equatable, Sendable {
    var sheets: [ExportSheet]
    var currencyCode: String
    /// "₪", "$", "€" — for the money cells' number format.
    var currencySymbol: String

    func sheet(named name: String) -> ExportSheet? {
        sheets.first { $0.name == name }
    }
}

// MARK: - Building it from the store

/// Turns the ledger, the budget and the accounts into an `ExportWorkbook`.
///
/// Every figure follows the rules the app's own screens use, so a number in
/// the file matches the number on the dashboard: transfers and manual balance
/// edits are listed but never counted as income or spending, a `.want`
/// category is a luxury and everything else spent is a need (as in
/// `BudgetVsActual`), the budget side is `CategoryBudgetBreakdown`'s, and
/// conversion goes through `CurrencyConverter` — a row with no rate is left
/// blank and counted, never guessed. Months are Gregorian, as `BudgetItem`'s
/// month numbers are.
///
/// Pure apart from reading the models it's handed; tested in
/// `OshRatTests/TransactionExportTests.swift`.
enum TransactionExport {

    enum SheetName {
        static let overview = "סקירה"
        static let transactions = "תנועות"
        static let monthly = "סיכום חודשי"
        static let categories = "לפי קטגוריה"
        static let budget = "תקציב מול ביצוע"
        static let accounts = "חשבונות"
    }

    /// - Parameters:
    ///   - transactions: the live ledger, any order; soft-deleted rows are
    ///     skipped anyway.
    ///   - interval: the exported window, half-open; `nil` for everything.
    ///   - calendar: Gregorian, in the user's time zone.
    static func workbook(
        transactions: [Transaction],
        budgetItems: [BudgetItem],
        accounts: [Account],
        preferredCurrency: String,
        fxSnapshot: FXRateSnapshot?,
        interval: DateInterval?,
        calendar: Calendar,
        now: Date = .now
    ) -> ExportWorkbook {
        var builder = Builder(
            budgetItems: budgetItems,
            accounts: accounts.filter { $0.deletedAt == nil },
            currency: preferredCurrency,
            fxSnapshot: fxSnapshot,
            calendar: calendar,
            now: now
        )
        let inRange = transactions
            .filter { tx in
                guard tx.deletedAt == nil else { return false }
                guard let interval else { return true }
                return tx.date >= interval.start && tx.date < interval.end
            }
            .sorted { $0.date < $1.date }
        builder.prepare(rows: inRange, interval: interval)

        let transactionsSheet = builder.transactionsSheet()
        return ExportWorkbook(
            sheets: [
                builder.overviewSheet(),
                transactionsSheet,
                builder.monthlySheet(),
                builder.categoriesSheet(),
                builder.budgetSheet(),
                builder.accountsSheet(),
            ],
            currencyCode: preferredCurrency,
            currencySymbol: currencySymbol(for: preferredCurrency)
        )
    }

    /// The symbol the app prints for a currency ("₪" for ILS).
    static func currencySymbol(for code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "he_IL")
        formatter.currencyCode = code
        return formatter.currencySymbol ?? code
    }
}

// MARK: - Builder

private struct Builder {
    let budgetItems: [BudgetItem]
    let accounts: [Account]
    let currency: String
    let fxSnapshot: FXRateSnapshot?
    let calendar: Calendar
    let now: Date

    /// The window's rows, oldest first.
    private(set) var rows: [Transaction] = []
    /// The months the summaries cover: from the window's first month to its
    /// last, stopping at the current one (a "this year" window shouldn't list
    /// December's empty plan in October).
    private(set) var months: [DateInterval] = []
    private(set) var subtitle = ""
    /// Rows whose amount couldn't be brought into the preferred currency.
    private(set) var unconvertedCount = 0
    /// Each row's amount in the preferred currency, by position in `rows`.
    private var converted: [Decimal?] = []

    init(
        budgetItems: [BudgetItem],
        accounts: [Account],
        currency: String,
        fxSnapshot: FXRateSnapshot?,
        calendar: Calendar,
        now: Date
    ) {
        self.budgetItems = budgetItems
        self.accounts = accounts
        self.currency = currency
        self.fxSnapshot = fxSnapshot
        self.calendar = calendar
        self.now = now
    }

    mutating func prepare(rows: [Transaction], interval: DateInterval?) {
        self.rows = rows
        converted = rows.map { convert($0.amount, from: $0.currencyCode) }
        unconvertedCount = converted.filter { $0 == nil }.count

        // With no window, the export runs from the first row to today.
        let start = interval?.start ?? rows.first?.date ?? now
        let end = interval?.end ?? now
        let last = min(end.addingTimeInterval(-1), max(now, start))
        var months: [DateInterval] = []
        var cursor = calendar.dateInterval(of: .month, for: start)
        while let month = cursor, month.start <= last {
            months.append(month)
            cursor = calendar.dateInterval(of: .month, for: month.end)
        }
        self.months = months

        let first = interval?.start ?? rows.first?.date
        let rangeText: String
        if let first {
            let lastDay = interval.map { $0.end.addingTimeInterval(-1) } ?? rows.last?.date ?? now
            rangeText = "\(dayText(first)) – \(dayText(min(lastDay, now)))"
        } else {
            rangeText = "אין תנועות"
        }
        subtitle = "\(rangeText) · \(TransactionExport.currencySymbol(for: currency))"
    }

    // MARK: Shared rules

    func convert(_ amount: Decimal, from code: String) -> Decimal? {
        if code == currency { return amount }
        guard let fxSnapshot,
              let value = CurrencyConverter.convert(amount, from: code, to: currency, using: fxSnapshot)
        else { return nil }
        return Self.rounded(value)
    }

    /// Income and spending only — what every total counts.
    static func isReal(_ tx: Transaction) -> Bool {
        !tx.isTransfer && !tx.isManualBalanceEdit
    }

    static func isWant(_ tx: Transaction) -> Bool {
        tx.category?.nature == .want
    }

    static func rounded(_ value: Decimal, places: Int = 2) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, places, .plain)
        return result
    }

    /// The real rows of one month, with their converted amounts.
    func realRows(in month: DateInterval) -> [(tx: Transaction, amount: Decimal)] {
        rows.indices.compactMap { index in
            let tx = rows[index]
            guard Self.isReal(tx), tx.date >= month.start, tx.date < month.end,
                  let amount = converted[index] else { return nil }
            return (tx, amount)
        }
    }

    struct Totals {
        var income = Decimal(0)
        var needs = Decimal(0)
        var wants = Decimal(0)
        var count = 0
        var expense: Decimal { needs + wants }
        var net: Decimal { income - expense }
    }

    func totals(in month: DateInterval?) -> Totals {
        var totals = Totals()
        for (index, tx) in rows.enumerated() where Self.isReal(tx) {
            if let month, !(tx.date >= month.start && tx.date < month.end) { continue }
            totals.count += 1
            guard let amount = converted[index] else { continue }
            switch tx.kind {
            case .income: totals.income += amount
            case .expense:
                if Self.isWant(tx) { totals.wants += amount } else { totals.needs += amount }
            }
        }
        return totals
    }

    func breakdown(for month: DateInterval) -> CategoryBudgetBreakdown {
        CategoryBudgetBreakdown(
            budgetItems: budgetItems,
            transactions: rows,
            interval: month,
            preferredCurrency: currency,
            fxSnapshot: fxSnapshot,
            calendar: calendar,
            now: now
        )
    }

    var netWorth: Decimal {
        accounts.reduce(Decimal(0)) { $0 + (convert($1.balance, from: $1.currencyCode) ?? 0) }
    }

    // MARK: Formatting

    func dayText(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.day ?? 1).\(parts.month ?? 1).\(parts.year ?? 2000)"
    }

    func monthText(_ month: DateInterval) -> String {
        var style = Date.FormatStyle.dateTime.month(.wide).year().locale(Locale(identifier: "he_IL"))
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return month.start.formatted(style)
    }

    func dateValue(_ date: Date) -> ExportValue {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return .date(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    func dateCell(_ date: Date?) -> ExportCell {
        guard let date else { return .empty }
        return ExportCell(value: dateValue(date), role: .date)
    }

    private var symbol: String { TransactionExport.currencySymbol(for: currency) }

    // MARK: Sheets

    func overviewSheet() -> ExportSheet {
        let totals = totals(in: nil)
        let cards = [
            ExportKPI(label: "שווי נקי (היום)", value: netWorth, tone: .neutral),
            ExportKPI(label: "הכנסות", value: totals.income, tone: .income),
            ExportKPI(label: "הוצאות", value: totals.expense, tone: .expense),
            ExportKPI(label: "נטו", value: totals.net, tone: .signed(totals.net)),
            ExportKPI(label: "צרכים", value: totals.needs, tone: .expense),
            ExportKPI(label: "מותרות", value: totals.wants, tone: .wants),
        ]

        var details: [ExportRow] = [
            detail("הופק", .text(dayText(now), span: 3)),
            detail("טווח", .text(subtitle, span: 3)),
            detail("מטבע", .text("\(currency) (\(symbol))", span: 3)),
            detail("תנועות", .text(rows.count.formatted(), span: 3)),
        ]
        if let fxSnapshot {
            details.append(detail("שערי חליפין מתאריך", .text(dayText(fxSnapshot.fetchedAt), span: 3)))
        }
        if unconvertedCount > 0 {
            details.append(detail(
                "לא הומרו",
                .text("\(unconvertedCount) תנועות במטבע אחר, ללא שער חליפין — לא נספרו בסיכומים", .mutedText, span: 3)
            ))
        }

        return ExportSheet(
            name: TransactionExport.SheetName.overview,
            subtitle: subtitle,
            blocks: [
                .cards(cards),
                .table(ExportTable(
                    caption: "פרטי הייצוא",
                    columns: [ExportColumn(header: "", width: 24), ExportColumn(header: "", width: 24)],
                    rows: details
                )),
            ]
        )
    }

    private func detail(_ label: String, _ value: ExportCell) -> ExportRow {
        ExportRow(cells: [.text(label, .mutedText), value])
    }

    func transactionsSheet() -> ExportSheet {
        let columns = [
            ExportColumn(header: "תאריך", width: 11),
            ExportColumn(header: "שעה", width: 7),
            ExportColumn(header: "סוג", width: 11),
            ExportColumn(header: "כותרת", width: 24),
            ExportColumn(header: "קטגוריה", width: 18),
            ExportColumn(header: "סיווג", width: 9),
            ExportColumn(header: "חשבון", width: 16),
            ExportColumn(header: "לחשבון", width: 16),
            ExportColumn(header: "סכום", width: 12),
            ExportColumn(header: "מטבע", width: 7),
            ExportColumn(header: "סכום (\(symbol))", width: 13),
            ExportColumn(header: "יתרה אחרי", width: 13),
            ExportColumn(header: "הערה", width: 28),
            ExportColumn(header: "בית עסק (Apple Pay)", width: 20),
            ExportColumn(header: "מתוך התקציב", width: 11),
        ]

        let body = rows.enumerated().map { index, tx in
            let isBookkeeping = !Self.isReal(tx)
            let type: String
            if tx.isTransfer {
                type = "העברה"
            } else if tx.isManualBalanceEdit {
                type = "עריכה ידנית"
            } else {
                type = tx.kind.hebrewLabel
            }
            // Signed the way money moved: income in, expense out. A transfer
            // only moves money between the user's own accounts, so it stays
            // unsigned, as the list shows it.
            let sign: Decimal = tx.isTransfer || tx.kind == .income ? 1 : -1
            let tone: ExportTone = isBookkeeping ? .muted : (tx.kind == .income ? .income : .expense)

            let time: ExportCell
            if tx.hasTimeOfDay {
                let parts = calendar.dateComponents([.hour, .minute], from: tx.date)
                time = ExportCell(value: .time(hour: parts.hour ?? 0, minute: parts.minute ?? 0), role: .time)
            } else {
                time = .empty
            }

            let category: ExportCell = tx.category.map {
                .text($0.name, .category(colorHex: $0.colorHex))
            } ?? .empty
            let nature = tx.category.flatMap { $0.kind == .expense ? $0.nature.hebrewLabel : nil } ?? ""

            return ExportRow(cells: [
                dateCell(tx.date),
                time,
                .text(type, isBookkeeping ? .mutedText : .text),
                .text(tx.title.isEmpty ? (tx.category?.name ?? "") : tx.title),
                category,
                .text(nature),
                .text(tx.account?.name ?? ""),
                .text(tx.destinationAccount?.name ?? ""),
                .number(tx.amount * sign, .amount(tone)),
                .text(tx.currencyCode),
                .number(converted[index].map { $0 * sign }, .money(tone)),
                .number(tx.balanceAfter, .amount(.neutral)),
                .text(tx.note),
                .text(tx.paymentMerchant ?? ""),
                .text(tx.budgetItem != nil || tx.budgetOccurrenceDate != nil ? "✓" : ""),
            ])
        }

        return ExportSheet(
            name: TransactionExport.SheetName.transactions,
            subtitle: subtitle,
            blocks: [.table(ExportTable(
                columns: columns,
                rows: body,
                emptyNote: "אין תנועות בטווח הזה",
                isPrimary: true
            ))]
        )
    }

    func monthlySheet() -> ExportSheet {
        let columns = [
            ExportColumn(header: "חודש", width: 15),
            ExportColumn(header: "הכנסות", width: 13),
            ExportColumn(header: "צרכים", width: 13),
            ExportColumn(header: "מותרות", width: 13),
            ExportColumn(header: "סה״כ הוצאות", width: 13),
            ExportColumn(header: "נטו", width: 13),
            ExportColumn(header: "תנועות", width: 8),
            ExportColumn(header: "הכנסות מתוכננות", width: 15),
            ExportColumn(header: "הוצאות מתוכננות", width: 15),
        ]

        var all = Totals()
        var plannedIncome = Decimal(0)
        var plannedExpense = Decimal(0)
        var body: [ExportRow] = []
        for month in months {
            let totals = totals(in: month)
            let plan = breakdown(for: month)
            all.income += totals.income
            all.needs += totals.needs
            all.wants += totals.wants
            all.count += totals.count
            plannedIncome += plan.plannedIncome
            plannedExpense += plan.plannedExpense
            body.append(monthlyRow(
                .text(monthText(month)), totals,
                plannedIncome: plan.plannedIncome, plannedExpense: plan.plannedExpense
            ))
        }
        if months.count > 1 {
            var total = monthlyRow(
                .text("סה״כ"), all, plannedIncome: plannedIncome, plannedExpense: plannedExpense
            )
            total.kind = .total
            body.append(total)
        }

        return ExportSheet(
            name: TransactionExport.SheetName.monthly,
            subtitle: subtitle,
            blocks: [.table(ExportTable(columns: columns, rows: body, isPrimary: true))]
        )
    }

    private func monthlyRow(
        _ label: ExportCell,
        _ totals: Totals,
        plannedIncome: Decimal,
        plannedExpense: Decimal
    ) -> ExportRow {
        ExportRow(cells: [
            label,
            .number(totals.income, .money(.income)),
            .number(totals.needs, .money(.expense)),
            .number(totals.wants, .money(.wants)),
            .number(totals.expense, .money(.expense)),
            .number(totals.net, .money(.signed(totals.net))),
            .number(Decimal(totals.count), .count),
            .number(plannedIncome, .money(.muted)),
            .number(plannedExpense, .money(.muted)),
        ])
    }

    func categoriesSheet() -> ExportSheet {
        struct Entry {
            var name: String
            var colorHex: String
            var kind: TransactionKind
            var nature: CategoryNature?
            var total = Decimal(0)
            var count = 0
            var byMonth: [Int: Decimal] = [:]
        }

        var entries: [CategoryKey: Entry] = [:]
        for (index, tx) in rows.enumerated() where Self.isReal(tx) {
            let key = CategoryKey(tx.category)
            var entry = entries[key] ?? Entry(
                name: tx.category?.name ?? CategoryKey.uncategorisedName,
                colorHex: tx.category?.colorHex ?? "#9E9E9E",
                kind: tx.kind,
                nature: tx.category?.nature
            )
            entry.count += 1
            if let amount = converted[index] {
                entry.total += amount
                if let month = months.firstIndex(where: { tx.date >= $0.start && tx.date < $0.end }) {
                    entry.byMonth[month, default: 0] += amount
                }
            }
            entries[key] = entry
        }

        let monthCount = Decimal(max(months.count, 1))
        func ordered(_ kind: TransactionKind) -> [Entry] {
            entries.values
                .filter { $0.kind == kind }
                .sorted { $0.total != $1.total ? $0.total > $1.total : $0.name < $1.name }
        }

        let columns = [
            ExportColumn(header: "קטגוריה", width: 20),
            ExportColumn(header: "סיווג", width: 9),
            ExportColumn(header: "סה״כ", width: 13),
            ExportColumn(header: "תנועות", width: 8),
            ExportColumn(header: "אחוז", width: 8),
            ExportColumn(header: "ממוצע לחודש", width: 13),
        ]
        var summary: [ExportRow] = []
        for (kind, label) in [(TransactionKind.expense, "הוצאות"), (.income, "הכנסות")] {
            let group = ordered(kind)
            guard !group.isEmpty else { continue }
            let total = group.reduce(Decimal(0)) { $0 + $1.total }
            let tone: ExportTone = kind == .income ? .income : .expense
            summary.append(ExportRow(cells: [
                .text(label), .empty,
                .number(total, .money(tone)),
                .number(Decimal(group.reduce(0) { $0 + $1.count }), .count),
                .empty,
                .number(Builder.rounded(total / monthCount), .money(tone)),
            ], kind: .group))
            for entry in group {
                let entryTone: ExportTone = kind == .income ? .income : (entry.nature == .want ? .wants : .expense)
                summary.append(ExportRow(cells: [
                    .text(entry.name, .category(colorHex: entry.colorHex)),
                    .text(kind == .expense ? (entry.nature ?? .need).hebrewLabel : ""),
                    .number(entry.total, .money(entryTone)),
                    .number(Decimal(entry.count), .count),
                    .number(total > 0 ? Builder.rounded(entry.total / total, places: 4) : nil, .percent),
                    .number(Builder.rounded(entry.total / monthCount), .money(entryTone)),
                ]))
            }
        }

        // The table people otherwise build by hand: spending per category
        // per month.
        let expenses = ordered(.expense)
        var pivotColumns = [ExportColumn(header: "קטגוריה", width: 20)]
        pivotColumns += months.map { ExportColumn(header: monthText($0), width: 13) }
        pivotColumns.append(ExportColumn(header: "סה״כ", width: 13))
        var pivot: [ExportRow] = expenses.map { entry in
            ExportRow(cells:
                [.text(entry.name, .category(colorHex: entry.colorHex))]
                + months.indices.map { .number(entry.byMonth[$0], .money(.expense)) }
                + [.number(entry.total, .money(.expense))]
            )
        }
        if !expenses.isEmpty {
            pivot.append(ExportRow(cells:
                [.text("סה״כ")]
                + months.indices.map { month in
                    .number(expenses.reduce(Decimal(0)) { $0 + ($1.byMonth[month] ?? 0) }, .money(.expense))
                }
                + [.number(expenses.reduce(Decimal(0)) { $0 + $1.total }, .money(.expense))],
                kind: .total
            ))
        }

        return ExportSheet(
            name: TransactionExport.SheetName.categories,
            subtitle: subtitle,
            blocks: [
                .table(ExportTable(
                    caption: "סיכום לפי קטגוריה", columns: columns, rows: summary,
                    emptyNote: "אין הכנסות או הוצאות בטווח הזה"
                )),
                .table(ExportTable(
                    caption: "הוצאות לפי חודש", columns: pivotColumns, rows: pivot,
                    emptyNote: "אין הוצאות בטווח הזה"
                )),
            ]
        )
    }

    func budgetSheet() -> ExportSheet {
        let columns = [
            ExportColumn(header: "קטגוריה", width: 20),
            ExportColumn(header: "מתוכנן", width: 13),
            ExportColumn(header: "בפועל", width: 13),
            ExportColumn(header: "הפרש", width: 17),
            ExportColumn(header: "ניצול", width: 9),
        ]

        var body: [ExportRow] = []
        for month in months {
            let plan = breakdown(for: month)
            let hasActivity = plan.actualExpense > 0 || plan.actualIncome > 0
            guard plan.hasPlanInPeriod || hasActivity else { continue }

            body.append(budgetRow(
                .text(monthText(month)),
                planned: plan.plannedExpense, actual: plan.actualExpense, kind: .group
            ))
            for row in plan.rows {
                body.append(budgetRow(
                    .text(row.name, .category(colorHex: row.colorHex)),
                    planned: row.planned, actual: row.actual
                ))
            }
            for row in plan.unbudgeted {
                body.append(budgetRow(
                    .text(row.name, .category(colorHex: row.colorHex)),
                    planned: 0, actual: row.actual
                ))
            }
            if plan.plannedIncome > 0 || plan.actualIncome > 0 {
                body.append(ExportRow(cells: [
                    .text("הכנסות"),
                    .number(plan.plannedIncome, .money(.income)),
                    .number(plan.actualIncome, .money(.income)),
                    .number(plan.actualIncome - plan.plannedIncome, .money(.signed(plan.actualIncome - plan.plannedIncome))),
                    .number(
                        plan.plannedIncome > 0 ? Builder.rounded(plan.actualIncome / plan.plannedIncome, places: 4) : nil,
                        .budgetPercent(.income)
                    ),
                ]))
            }
        }

        return ExportSheet(
            name: TransactionExport.SheetName.budget,
            subtitle: subtitle,
            blocks: [.table(ExportTable(
                columns: columns,
                rows: body,
                emptyNote: "אין תקציב או תנועות בטווח הזה",
                isPrimary: true
            ))]
        )
    }

    /// One expense line: the difference is what's left (negative once over),
    /// and the used share is drawn as a bar only where there's a plan.
    private func budgetRow(
        _ label: ExportCell,
        planned: Decimal,
        actual: Decimal,
        kind: ExportRow.Kind = .body
    ) -> ExportRow {
        let tone = ExportBudgetTone.expense(planned: planned, actual: actual)
        return ExportRow(cells: [
            label,
            .number(planned > 0 ? planned : nil, .money(.muted)),
            .number(actual, .money(.expense)),
            .number(planned > 0 ? planned - actual : nil, .budgetDifference),
            .number(planned > 0 ? Builder.rounded(actual / planned, places: 4) : nil, .budgetPercent(tone)),
        ], kind: kind)
    }

    func accountsSheet() -> ExportSheet {
        let columns = [
            ExportColumn(header: "חשבון", width: 20),
            ExportColumn(header: "סוג", width: 12),
            ExportColumn(header: "יתרה", width: 13),
            ExportColumn(header: "מטבע", width: 7),
            ExportColumn(header: "יתרה (\(symbol))", width: 13),
            ExportColumn(header: "עודכן", width: 11),
            ExportColumn(header: "ריבית", width: 8),
            ExportColumn(header: "תחילה", width: 11),
            ExportColumn(header: "פדיון", width: 11),
            ExportColumn(header: "צפי בפדיון", width: 13),
            ExportColumn(header: "מצב", width: 13),
        ]

        let sorted = accounts.sorted {
            $0.type.sortRank != $1.type.sortRank ? $0.type.sortRank < $1.type.sortRank : $0.name < $1.name
        }
        var body: [ExportRow] = []
        // The assets card's split: money to spend, then money put away.
        for (isLiquid, label) in [(true, "נזיל"), (false, "נכסים")] {
            let group = sorted.filter { $0.type.isLiquid == isLiquid }
            guard !group.isEmpty else { continue }
            let subtotal = group.reduce(Decimal(0)) { $0 + (convert($1.balance, from: $1.currencyCode) ?? 0) }
            var heading = Array(repeating: ExportCell.empty, count: columns.count)
            heading[0] = .text(label)
            heading[4] = .number(subtotal, .money(.neutral))
            body.append(ExportRow(cells: heading, kind: .group))

            for account in group {
                let ladder = account.isDeposit ? account.depositLadder : nil
                let status: String
                if account.payoutCompletedAt != nil {
                    status = "נפדה"
                } else if account.isAwaitingPayout(asOf: now) {
                    status = "ממתין לפדיון"
                } else {
                    status = ""
                }
                body.append(ExportRow(cells: [
                    .text(account.name),
                    .text(account.type.hebrewLabel, .mutedText),
                    .number(account.balance, .amount(.neutral)),
                    .text(account.currencyCode),
                    .number(convert(account.balance, from: account.currencyCode), .money(.neutral)),
                    dateCell(account.lastUpdated),
                    .number(account.isDeposit ? account.interestRatePercent.map { Builder.rounded($0 / 100, places: 6) } : nil, .percent),
                    dateCell(account.isDeposit ? (ladder?.startDate ?? account.depositStartDate) : nil),
                    dateCell(account.isDeposit ? account.effectiveMaturityDate : nil),
                    .number(ladder.map { Builder.rounded($0.projectedValue) }, .amount(.income)),
                    .text(status, .mutedText),
                ]))
            }
        }
        if !body.isEmpty {
            var total = Array(repeating: ExportCell.empty, count: columns.count)
            total[0] = .text("סה״כ")
            total[4] = .number(netWorth, .money(.neutral))
            body.append(ExportRow(cells: total, kind: .total))
        }

        // Balances are today's whatever the range — the subtitle says so.
        return ExportSheet(
            name: TransactionExport.SheetName.accounts,
            subtitle: "יתרות נכון ליום \(dayText(now)) · \(symbol)",
            blocks: [.table(ExportTable(columns: columns, rows: body, emptyNote: "אין חשבונות"))]
        )
    }
}
