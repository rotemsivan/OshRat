import Foundation

/// A pure, testable snapshot of everything the analytics roadmap shows.
///
/// Built once from the user's transactions and accounts, with every
/// cross-currency figure converted into the preferred currency via the
/// cached FX snapshot (same rules as the dashboard cards). There is no
/// SwiftUI here on purpose — it's just numbers, so it can be unit-tested
/// and re-used without dragging a view in.
///
/// The roadmap is meant to read *gradually*, from basic to advanced, so
/// the fields are grouped in the order the user meets them:
///   1. This month → 2. This year → 3. Month-over-month comparison →
///   4. Spending by category → 5. Needs vs wants → 6. All-time records →
///   7. Assets.
struct AnalyticsReport {

    // MARK: Currency / FX

    let currencyCode: String
    /// True when at least one figure had to be dropped because we lacked
    /// an FX rate for its currency. Lets the UI show the same "FX
    /// unavailable" note the dashboard uses.
    let fxUnavailable: Bool

    // MARK: Totals

    let totalTransactions: Int

    // This month
    let monthIncome: Decimal
    let monthExpense: Decimal
    let monthTransactionCount: Int

    // Previous calendar month — the baseline for the comparison station.
    let prevMonthIncome: Decimal
    let prevMonthExpense: Decimal

    // This year
    let yearIncome: Decimal
    let yearExpense: Decimal
    /// Number of distinct months *this year* that have at least one real
    /// transaction. Used as the divisor for a fair "typical month"
    /// average instead of always dividing by 12.
    let activeMonthsThisYear: Int

    // Where the money goes (this year, expenses only), biggest first.
    let categoryBreakdown: [CategorySlice]

    // Needs vs wants (this year, expenses only).
    let needsTotal: Decimal
    let wantsTotal: Decimal

    // All-time achievements.
    let records: [FinancialRecord]

    // Assets
    let netWorth: Decimal
    let assetAllocation: [AssetSlice]

    // MARK: Derived

    var monthNet: Decimal { monthIncome - monthExpense }
    var prevMonthNet: Decimal { prevMonthIncome - prevMonthExpense }
    var yearNet: Decimal { yearIncome - yearExpense }

    var avgMonthlyExpenseThisYear: Decimal {
        guard activeMonthsThisYear > 0 else { return 0 }
        return yearExpense / Decimal(activeMonthsThisYear)
    }

    /// Whether there's enough to render the roadmap at all. A brand-new
    /// user with no accounts and no transactions sees an empty state
    /// instead.
    var hasAnyData: Bool {
        totalTransactions > 0 || !assetAllocation.isEmpty
    }

    /// Signed month-over-month change of expenses, as a fraction
    /// (-0.2 == "20% less than last month"). `nil` when there's no
    /// prior-month baseline to compare against.
    var expenseChangeFraction: Double? {
        Self.changeFraction(from: prevMonthExpense, to: monthExpense)
    }

    var incomeChangeFraction: Double? {
        Self.changeFraction(from: prevMonthIncome, to: monthIncome)
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

    /// Crunches the raw model objects into the report. `calendar` and
    /// `now` are injectable so tests can pin a deterministic "today".
    init(
        transactions: [Transaction],
        accounts: [Account],
        preferredCurrency: String,
        fxSnapshot: FXRateSnapshot?,
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

        let monthInterval = calendar.dateInterval(of: .month, for: now)
        let yearInterval = calendar.dateInterval(of: .year, for: now)
        let prevMonthInterval = calendar.date(byAdding: .month, value: -1, to: now)
            .flatMap { calendar.dateInterval(of: .month, for: $0) }

        // MARK: This month / previous month

        var mIncome = Decimal(0), mExpense = Decimal(0)
        var pIncome = Decimal(0), pExpense = Decimal(0)
        var monthCount = 0

        for tx in real {
            if let interval = monthInterval, interval.contains(tx.date) {
                monthCount += 1
                if let value = convert(tx.amount, tx.currencyCode) {
                    if tx.kind == .income { mIncome += value } else { mExpense += value }
                }
            } else if let interval = prevMonthInterval, interval.contains(tx.date) {
                if let value = convert(tx.amount, tx.currencyCode) {
                    if tx.kind == .income { pIncome += value } else { pExpense += value }
                }
            }
        }

        // MARK: This year + category + needs/wants

        var yIncome = Decimal(0), yExpense = Decimal(0)
        var needs = Decimal(0), wants = Decimal(0)
        var activeMonths = Set<Int>()
        // Keyed by category name so two transactions in "כלכלת בית" merge.
        var categoryTotals: [String: (amount: Decimal, color: String, symbol: String)] = [:]

        for tx in real {
            guard let interval = yearInterval, interval.contains(tx.date) else { continue }
            activeMonths.insert(calendar.component(.month, from: tx.date))
            guard let value = convert(tx.amount, tx.currencyCode) else { continue }

            switch tx.kind {
            case .income:
                yIncome += value
            case .expense:
                yExpense += value
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
        }

        let categorySlices: [CategorySlice] = categoryTotals
            .map { name, entry in
                CategorySlice(
                    id: name,
                    name: name,
                    amount: entry.amount,
                    colorHex: entry.color,
                    symbolName: entry.symbol,
                    fraction: yExpense > 0
                        ? (entry.amount as NSDecimalNumber).doubleValue / (yExpense as NSDecimalNumber).doubleValue
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
            .sorted { $0.amount > $1.amount }

        // MARK: Assign

        self.currencyCode = preferredCurrency
        self.totalTransactions = real.count
        self.monthIncome = mIncome
        self.monthExpense = mExpense
        self.monthTransactionCount = monthCount
        self.prevMonthIncome = pIncome
        self.prevMonthExpense = pExpense
        self.yearIncome = yIncome
        self.yearExpense = yExpense
        self.activeMonthsThisYear = activeMonths.count
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
