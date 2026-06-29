import Foundation

/// A pure, testable snapshot of everything the analytics roadmap shows.
///
/// Built once from the user's transactions and accounts, with every
/// cross-currency figure converted into the preferred currency via the
/// cached FX snapshot (same rules as the dashboard cards). There is no
/// SwiftUI here on purpose — it's just numbers, so it can be unit-tested
/// and re-used without dragging a view in.
///
/// Most stations are scoped to a **selected period** — a single month or a
/// single year the user picks at the top of the screen (`AnalyticsPeriod`).
/// "Where the money goes", "needs vs wants", "income & expenses" and the
/// period-over-period comparison all reslice to that window. Records stay
/// all-time and assets stay "right now", since neither is a per-period idea.
struct AnalyticsReport {

    // MARK: Currency / FX

    let currencyCode: String
    /// True when at least one figure had to be dropped because we lacked
    /// an FX rate for its currency. Lets the UI show the same "FX
    /// unavailable" note the dashboard uses.
    let fxUnavailable: Bool

    // MARK: Selected period

    /// Whether the user is looking at a month or a year — lets stations
    /// phrase the previous-period comparison correctly.
    let scope: AnalyticsPeriod.Scope
    /// Hebrew label for the selected period ("יוני 2026" / "2026").
    let periodLabel: String

    // MARK: Totals

    /// All-time count, for the header's "you've logged N entries" line.
    let totalTransactions: Int

    // Selected period.
    let periodIncome: Decimal
    let periodExpense: Decimal
    let periodTransactionCount: Int

    // The period immediately before the selected one — the baseline for the
    // comparison station (previous month, or previous year).
    let prevPeriodIncome: Decimal
    let prevPeriodExpense: Decimal

    // Where the money goes (selected period, expenses only), biggest first.
    let categoryBreakdown: [CategorySlice]

    // Needs vs wants (selected period, expenses only).
    let needsTotal: Decimal
    let wantsTotal: Decimal

    // All-time achievements.
    let records: [FinancialRecord]

    // Assets
    let netWorth: Decimal
    let assetAllocation: [AssetSlice]

    // MARK: Derived

    var periodNet: Decimal { periodIncome - periodExpense }
    var prevPeriodNet: Decimal { prevPeriodIncome - prevPeriodExpense }

    /// Whether there's enough to render the roadmap at all. A brand-new
    /// user with no accounts and no transactions sees an empty state
    /// instead. Deliberately *not* period-scoped — the page still opens on
    /// an empty past month as long as the user has any history at all.
    var hasAnyData: Bool {
        totalTransactions > 0 || !assetAllocation.isEmpty
    }

    /// Signed period-over-period change of expenses, as a fraction
    /// (-0.2 == "20% less than the previous period"). `nil` when there's no
    /// prior-period baseline to compare against.
    var expenseChangeFraction: Double? {
        Self.changeFraction(from: prevPeriodExpense, to: periodExpense)
    }

    var incomeChangeFraction: Double? {
        Self.changeFraction(from: prevPeriodIncome, to: periodIncome)
    }

    static func changeFraction(from old: Decimal, to new: Decimal) -> Double? {
        guard old > 0 else { return nil }
        let delta = (new - old) / old
        return (delta as NSDecimalNumber).doubleValue
    }
}

// MARK: - Supporting value types

/// One slice of the "where my money goes" breakdown.
struct CategorySlice: Identifiable {
    let id: String
    let name: String
    let amount: Decimal
    let colorHex: String
    let symbolName: String
    /// Share of the total expense this slice represents, 0...1.
    let fraction: Double
}

/// One slice of the net-worth allocation, grouped by account type.
struct AssetSlice: Identifiable {
    let id: String
    let typeLabel: String
    let amount: Decimal
    let symbolName: String
    let fraction: Double
}

/// A gamified "personal record" — biggest expense, top category, etc.
struct FinancialRecord: Identifiable {
    let id: String
    let title: String
    let detail: String
    /// Optional headline figure. `nil` records (e.g. "busiest month")
    /// carry their value inside `detail` instead.
    let amount: Decimal?
    let currencyCode: String?
    let symbolName: String
    let tint: Tint

    /// Semantic colour the station maps onto the design system palette.
    enum Tint {
        case income
        case expense
        case gold
        case neutral
    }
}

// MARK: - Building the report

extension AnalyticsReport {

    /// Crunches the raw model objects into the report for a given `period`.
    /// `calendar` and `now` are injectable so tests can pin a deterministic
    /// "today" (and so records/assets, which ignore the period, stay stable).
    init(
        transactions: [Transaction],
        accounts: [Account],
        preferredCurrency: String,
        fxSnapshot: FXRateSnapshot?,
        period: AnalyticsPeriod,
        calendar: Calendar = .current,
        now: Date = .now
    ) {
        var fxMissing = false

        // Nested helper so every conversion funnels through one place and
        // flips `fxMissing` consistently when a rate is missing. A nested
        // function can capture and mutate `fxMissing` from this scope.
        func convert(_ amount: Decimal, _ code: String) -> Decimal? {
            if code == preferredCurrency { return amount }
            guard let snapshot = fxSnapshot,
                  let value = CurrencyConverter.convert(
                    amount, from: code, to: preferredCurrency, using: snapshot
                  ) else {
                fxMissing = true
                return nil
            }
            return value
        }

        // Manual balance-edit rows are bookkeeping artefacts, not real
        // income/expense — exclude them everywhere, exactly like the
        // monthly summary card does. Transfers (money moving between the
        // user's own accounts) are excluded for the same reason: they're
        // neither income nor expense and would distort every statistic.
        let real = transactions.filter { !$0.isManualBalanceEdit && !$0.isTransfer }

        let periodInterval = period.interval(calendar)
        let prevInterval = period.previous(calendar).interval(calendar)

        // MARK: Selected period + previous period + category + needs/wants

        var income = Decimal(0), expense = Decimal(0)
        var prevIncome = Decimal(0), prevExpense = Decimal(0)
        var periodCount = 0
        var needs = Decimal(0), wants = Decimal(0)
        // Keyed by category name so two transactions in "כלכלת בית" merge.
        var categoryTotals: [String: (amount: Decimal, color: String, symbol: String)] = [:]

        for tx in real {
            if let periodInterval, periodInterval.contains(tx.date) {
                periodCount += 1
                guard let value = convert(tx.amount, tx.currencyCode) else { continue }
                switch tx.kind {
                case .income:
                    income += value
                case .expense:
                    expense += value
                    let name = tx.category?.name ?? "ללא קטגוריה"
                    let color = tx.category?.colorHex ?? "#9E9E9E"
                    let symbol = tx.category?.symbolName ?? "questionmark"
                    let existing = categoryTotals[name]?.amount ?? 0
                    categoryTotals[name] = (amount: existing + value, color: color, symbol: symbol)

                    switch tx.category?.nature {
                    case .need: needs += value
                    case .want: wants += value
                    default: break
                    }
                }
            } else if let prevInterval, prevInterval.contains(tx.date) {
                guard let value = convert(tx.amount, tx.currencyCode) else { continue }
                if tx.kind == .income { prevIncome += value } else { prevExpense += value }
            }
        }

        let categorySlices: [CategorySlice] = categoryTotals
            .map { name, entry in
                CategorySlice(
                    id: name,
                    name: name,
                    amount: entry.amount,
                    colorHex: entry.color,
                    symbolName: entry.symbol,
                    fraction: expense > 0
                        ? (entry.amount as NSDecimalNumber).doubleValue / (expense as NSDecimalNumber).doubleValue
                        : 0
                )
            }
            .sorted { $0.amount > $1.amount }

        // MARK: All-time records

        let records = Self.buildRecords(
            real: real,
            calendar: calendar,
            convert: convert
        )

        // MARK: Assets

        var worth = Decimal(0)
        var byType: [AccountType: Decimal] = [:]
        for account in accounts {
            var accountTotal = Decimal(0)
            if let value = convert(account.balance, account.currencyCode) {
                accountTotal += value
            }
            for holding in account.holdings {
                if let value = convert(holding.marketValue, holding.currencyCode) {
                    accountTotal += value
                }
            }
            worth += accountTotal
            byType[account.type, default: 0] += accountTotal
        }

        // Ordered by the same fixed account-type rank the assets summary card
        // uses (everyday → wallet → savings → investment), not by amount, so
        // the two screens read the asset mix in the same order.
        let allocation: [AssetSlice] = byType
            .filter { $0.value > 0 }
            .map { type, amount in
                AssetSlice(
                    id: type.rawValue,
                    typeLabel: type.hebrewLabel,
                    amount: amount,
                    symbolName: Self.symbol(for: type),
                    fraction: worth > 0
                        ? (amount as NSDecimalNumber).doubleValue / (worth as NSDecimalNumber).doubleValue
                        : 0
                )
            }
            .sorted { Self.typeRank($0.id) < Self.typeRank($1.id) }

        // MARK: Assign

        self.currencyCode = preferredCurrency
        self.scope = period.scope
        self.periodLabel = period.label(calendar)
        self.totalTransactions = real.count
        self.periodIncome = income
        self.periodExpense = expense
        self.periodTransactionCount = periodCount
        self.prevPeriodIncome = prevIncome
        self.prevPeriodExpense = prevExpense
        self.categoryBreakdown = categorySlices
        self.needsTotal = needs
        self.wantsTotal = wants
        self.records = records
        self.netWorth = worth
        self.assetAllocation = allocation
        // Set last so every `convert` call above has had its chance to
        // flip the flag.
        self.fxUnavailable = fxMissing
    }

    // MARK: - Records

    /// Scans the whole (real) ledger once per record type to surface the
    /// gamified "personal bests". Kept static and parameterised by the
    /// same `convert` closure so the FX handling stays consistent.
    private static func buildRecords(
        real: [Transaction],
        calendar: Calendar,
        convert: (Decimal, String) -> Decimal?
    ) -> [FinancialRecord] {
        var records: [FinancialRecord] = []

        // Biggest single expense / income, by converted value.
        var biggestExpense: (tx: Transaction, value: Decimal)?
        var biggestIncome: (tx: Transaction, value: Decimal)?
        // Per-month buckets for "busiest" and "best saving" records.
        var monthNet: [Int: Decimal] = [:]
        var monthCount: [Int: Int] = [:]
        var monthSample: [Int: Date] = [:]
        // All-time category totals for the "favourite category" record.
        var categoryAllTime: [String: (amount: Decimal, symbol: String)] = [:]

        for tx in real {
            let comps = calendar.dateComponents([.year, .month], from: tx.date)
            let key = (comps.year ?? 0) * 100 + (comps.month ?? 0)
            monthCount[key, default: 0] += 1
            monthSample[key] = tx.date

            guard let value = convert(tx.amount, tx.currencyCode) else { continue }

            switch tx.kind {
            case .income:
                monthNet[key, default: 0] += value
                if value > (biggestIncome?.value ?? -1) {
                    biggestIncome = (tx, value)
                }
            case .expense:
                monthNet[key, default: 0] -= value
                if value > (biggestExpense?.value ?? -1) {
                    biggestExpense = (tx, value)
                }
                let name = tx.category?.name ?? "ללא קטגוריה"
                let symbol = tx.category?.symbolName ?? "questionmark"
                let existing = categoryAllTime[name]?.amount ?? 0
                categoryAllTime[name] = (amount: existing + value, symbol: symbol)
            }
        }

        if let biggest = biggestExpense {
            records.append(
                FinancialRecord(
                    id: "biggestExpense",
                    title: "ההוצאה הגדולה ביותר",
                    detail: Self.recordDetail(for: biggest.tx, calendar: calendar),
                    amount: biggest.value,
                    currencyCode: nil,
                    symbolName: "flame.fill",
                    tint: .expense
                )
            )
        }

        if let biggest = biggestIncome {
            records.append(
                FinancialRecord(
                    id: "biggestIncome",
                    title: "ההכנסה הגדולה ביותר",
                    detail: Self.recordDetail(for: biggest.tx, calendar: calendar),
                    amount: biggest.value,
                    currencyCode: nil,
                    symbolName: "sparkles",
                    tint: .income
                )
            )
        }

        if let top = categoryAllTime.max(by: { $0.value.amount < $1.value.amount }) {
            records.append(
                FinancialRecord(
                    id: "topCategory",
                    title: "הקטגוריה המובילה",
                    detail: top.key,
                    amount: top.value.amount,
                    currencyCode: nil,
                    symbolName: top.value.symbol,
                    tint: .gold
                )
            )
        }

        if let busiest = monthCount.max(by: { $0.value < $1.value }),
           let sample = monthSample[busiest.key] {
            records.append(
                FinancialRecord(
                    id: "busiestMonth",
                    title: "החודש העמוס ביותר",
                    detail: Self.monthLabel(for: sample),
                    amount: nil,
                    currencyCode: nil,
                    symbolName: "calendar",
                    tint: .neutral
                )
            )
        }

        if let best = monthNet.max(by: { $0.value < $1.value }),
           best.value > 0,
           let sample = monthSample[best.key] {
            records.append(
                FinancialRecord(
                    id: "bestSavingMonth",
                    title: "חודש החיסכון הגדול ביותר",
                    detail: Self.monthLabel(for: sample),
                    amount: best.value,
                    currencyCode: nil,
                    symbolName: "trophy.fill",
                    tint: .gold
                )
            )
        }

        return records
    }

    private static func recordDetail(for tx: Transaction, calendar: Calendar) -> String {
        let title = tx.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = !title.isEmpty ? title : (tx.category?.name ?? "ללא שם")
        return "\(name) • \(monthLabel(for: tx.date))"
    }

    private static func monthLabel(for date: Date) -> String {
        date.formatted(
            .dateTime
                .locale(Locale(identifier: "he_IL"))
                .month(.wide)
                .year()
        )
    }

    private static func symbol(for type: AccountType) -> String {
        switch type {
        case .current:       return "banknote"
        case .digitalWallet: return "wallet.bifold"
        case .savings:       return "lock"
        case .investment:    return "chart.line.uptrend.xyaxis"
        }
    }

    /// Lower rank sorts earlier, mirroring `AssetsSummaryCard.typeRank` so the
    /// allocation list reads in the same order on both screens. Keyed off the
    /// stored `AccountType.rawValue`; unknown values sort last.
    private static func typeRank(_ typeRaw: String) -> Int {
        switch AccountType(rawValue: typeRaw) {
        case .current:       return 0
        case .digitalWallet: return 1
        case .savings:       return 2
        case .investment:    return 3
        case .none:          return 4
        }
    }
}

// MARK: - Selected period

/// The window the analytics roadmap is scoped to: a single month or a single
/// year, anchored on a date inside it. A small value type (no SwiftUI) so the
/// view can step it, toggle its scope, and hand it to `AnalyticsReport`.
struct AnalyticsPeriod: Equatable {
    enum Scope: String, CaseIterable, Identifiable {
        case month, year
        var id: String { rawValue }
        var hebrewLabel: String { self == .month ? "חודש" : "שנה" }
    }

    var scope: Scope
    /// Any date inside the selected period; the period is the whole month or
    /// year that contains it.
    var anchor: Date

    /// The current month, the sensible default the screen opens on.
    static func current(_ now: Date = .now) -> AnalyticsPeriod {
        AnalyticsPeriod(scope: .month, anchor: now)
    }

    private var unit: Calendar.Component { scope == .month ? .month : .year }

    /// The date range this period covers.
    func interval(_ calendar: Calendar = .current) -> DateInterval? {
        calendar.dateInterval(of: unit, for: anchor)
    }

    /// The same scope, shifted one unit earlier / later.
    func previous(_ calendar: Calendar = .current) -> AnalyticsPeriod {
        shifted(by: -1, calendar)
    }

    func next(_ calendar: Calendar = .current) -> AnalyticsPeriod {
        shifted(by: 1, calendar)
    }

    private func shifted(by amount: Int, _ calendar: Calendar) -> AnalyticsPeriod {
        let components = scope == .month
            ? DateComponents(month: amount)
            : DateComponents(year: amount)
        let moved = calendar.date(byAdding: components, to: anchor) ?? anchor
        return AnalyticsPeriod(scope: scope, anchor: moved)
    }

    /// Whether we can step forward without entering a period that's entirely
    /// in the future — there's no data there, so the screen stops at "now".
    func canStepForward(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let interval = interval(calendar) else { return false }
        // Already showing the live period? Then forward would be the future.
        // Otherwise we're in the past (the period ended before now) and may
        // advance. `end` is exclusive, so a past period satisfies `end <= now`.
        return !interval.contains(now) && interval.end <= now
    }

    /// Hebrew label for the period: "יוני 2026" for a month, "2026" for a year.
    func label(_ calendar: Calendar = .current) -> String {
        let locale = Locale(identifier: "he_IL")
        switch scope {
        case .month:
            return anchor.formatted(.dateTime.locale(locale).month(.wide).year())
        case .year:
            return anchor.formatted(.dateTime.locale(locale).year())
        }
    }
}

// MARK: - Currency formatting helpers

extension Decimal {
    /// Plain currency string in the given ISO code.
    func formattedCurrency(_ code: String) -> String {
        formatted(.currency(code: code))
    }

    /// Currency string whose leading +/- sign is forced to the visual
    /// left even inside an RTL (Hebrew) view. The bidi-neutral sign would
    /// otherwise inherit RTL direction and land on the visual right of the
    /// number. Same U+2066 LRI … U+2069 PDI trick the dashboard cards use.
    func formattedSignedCurrency(_ code: String) -> String {
        let body = Swift.abs(self).formatted(.currency(code: code))
        let sign: String
        if self > 0 { sign = "+" } else if self < 0 { sign = "-" } else { sign = "" }
        return "\u{2066}\(sign)\(body)\u{2069}"
    }
}
