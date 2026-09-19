import Foundation

/// A deposit made of several sub-deposits, each running its own term — the
/// maths behind a **replenishable** deposit (`DepositKind.replenishable`).
///
/// A one-time deposit is just a ladder with a single rung, so every screen can
/// read the ladder and stop caring which kind it is looking at.
///
/// Pure value type, no SwiftData and no SwiftUI, so it can be unit-tested on
/// its own (and compiled into the test targets) exactly like `DepositTerms`,
/// whose per-rung maths it sums.
///
/// **Each rung earns simple interest on its own principal.** Nothing compounds
/// and nothing rolls over: money added in March earns from March on its own
/// terms, and money added in June earns from June on its. The deposit as a
/// whole pays out on the **latest** maturity of its rungs — the rest simply
/// stop accruing when their own term ends (`DepositTerms.value(asOf:)` caps
/// accrual at maturity) and wait.
struct DepositLadder: Equatable {

    /// The rungs, oldest start date first. Never contains a rung the account
    /// balance can't back — see `make(balance:opening:additions:)`.
    let tranches: [DepositTerms]

    init(tranches: [DepositTerms]) {
        self.tranches = tranches.sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Building

    /// Build a ladder for an account, reconciling the rungs against the
    /// balance the user actually holds.
    ///
    /// - Parameters:
    ///   - balance: the account's balance — the source of truth for net worth
    ///     in this app, so the ladder is fitted to it rather than the other way
    ///     round.
    ///   - opening: the account's *own* terms (rate, start, maturity). Its
    ///     `principal` is ignored: the opening deposit is whatever the recorded
    ///     additions don't account for.
    ///   - additions: one rung per sub-deposit (a transfer into the account).
    ///
    /// **Why the opening rung is a plug rather than a stored row.** The money
    /// that was in the deposit when it was created has no funding transfer to
    /// hang a rung off, and inventing one at creation would double-count the
    /// balance the user typed. Deriving it keeps a single source of truth: the
    /// rungs sum to the balance by construction, whatever else touched it (a
    /// hand-corrected balance, a deleted transfer, a partial withdrawal logged
    /// as an ordinary expense).
    ///
    /// When the additions *exceed* the balance — money left the deposit by some
    /// route that isn't a rung — the shortfall comes off the **newest** rungs
    /// first, on the reading that the oldest money is the most committed. The
    /// alternative (scaling every rung down) would fabricate a term structure
    /// that never existed.
    static func make(balance: Decimal, opening: DepositTerms, additions: [DepositTerms]) -> DepositLadder {
        let sorted = additions.sorted { $0.startDate < $1.startDate }
        let additionsTotal = sorted.reduce(Decimal(0)) { $0 + $1.principal }

        // The common case: the recorded sub-deposits fit inside the balance,
        // and the remainder is the opening deposit (possibly zero — a
        // replenishable deposit can legitimately start empty and be funded
        // entirely by transfers).
        if additionsTotal <= balance {
            let openingRung = DepositTerms(
                principal: balance - additionsTotal,
                annualRatePercent: opening.annualRatePercent,
                startDate: opening.startDate,
                maturityDate: opening.maturityDate
            )
            return DepositLadder(tranches: [openingRung] + sorted)
        }

        // Over-allocated: fill oldest-first from what's actually there and drop
        // whatever falls off the newest end.
        var remaining = balance
        var kept: [DepositTerms] = []
        for rung in sorted where remaining > 0 {
            let funded = min(rung.principal, remaining)
            remaining -= funded
            kept.append(
                DepositTerms(
                    principal: funded,
                    annualRatePercent: rung.annualRatePercent,
                    startDate: rung.startDate,
                    maturityDate: rung.maturityDate
                )
            )
        }
        return DepositLadder(tranches: kept)
    }

    // MARK: - Term state

    /// Total principal across the ladder — equal to the account balance it was
    /// built from, by construction.
    var principal: Decimal {
        tranches.reduce(Decimal(0)) { $0 + $1.principal }
    }

    /// When the *first* money went in.
    var startDate: Date? {
        tranches.map(\.startDate).min()
    }

    /// When the deposit as a whole pays out: the **latest** maturity of its
    /// rungs, which is what the user asked for.
    ///
    /// `nil` when any rung is open-ended — a deposit that still holds money
    /// with no end date never comes due, so it must not raise a payout prompt
    /// just because an earlier rung has matured.
    var maturityDate: Date? {
        guard !tranches.isEmpty else { return nil }
        var latest: Date?
        for rung in tranches {
            guard let maturity = rung.maturityDate else { return nil }
            latest = max(latest ?? maturity, maturity)
        }
        return latest
    }

    /// The whole deposit read as one term — first money in to last money out.
    /// Lets the state questions below reuse `DepositTerms`' day-granularity
    /// logic instead of re-deriving it.
    private var span: DepositTerms {
        DepositTerms(
            principal: principal,
            annualRatePercent: nil,
            startDate: startDate ?? .now,
            maturityDate: maturityDate
        )
    }

    func isMatured(asOf now: Date = .now, calendar: Calendar = .current) -> Bool {
        span.isMatured(asOf: now, calendar: calendar)
    }

    func daysRemaining(asOf now: Date = .now, calendar: Calendar = .current) -> Int? {
        span.daysRemaining(asOf: now, calendar: calendar)
    }

    func progress(asOf now: Date = .now, calendar: Calendar = .current) -> Double? {
        span.progress(asOf: now, calendar: calendar)
    }

    // MARK: - Value

    /// What the whole deposit is worth on a date: every rung's own value,
    /// summed. Each stops accruing at its own maturity.
    func value(asOf date: Date, calendar: Calendar = .current) -> Decimal {
        tranches.reduce(Decimal(0)) { $0 + $1.value(asOf: date, calendar: calendar) }
    }

    /// What the deposit pays out at the end — every rung run to its own
    /// maturity. The figure the payout prompt pre-fills.
    var projectedValue: Decimal {
        tranches.reduce(Decimal(0)) { $0 + $1.projectedValue }
    }

    /// Interest earned over the full term, across every rung.
    var projectedInterest: Decimal { projectedValue - principal }
}
