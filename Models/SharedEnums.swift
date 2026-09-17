import Foundation

// MARK: - Shared enums
// String-backed and Codable so SwiftData can persist them, and so we stay
// CloudKit-friendly if we turn on iCloud sync later.

/// Whether a transaction (or a planned budget line) is money coming in or going out.
enum TransactionKind: String, Codable, CaseIterable, Identifiable {
    case income   // הכנסה
    case expense  // הוצאה

    var id: String { rawValue }

    /// Temporary Hebrew label for the UI.
    /// TODO: move these strings into the String Catalog for proper localization.
    var hebrewLabel: String {
        switch self {
        case .income:  return "הכנסה"
        case .expense: return "הוצאה"
        }
    }
}

/// The kind of financial account the user is tracking.
///
/// Declaration order is also the order `allCases` feeds the type picker
/// and (see `sortRank` below) the dashboard list: everyday liquid money
/// first (current + digital wallet), then savings and investments.
enum AccountType: String, Codable, CaseIterable, Identifiable {
    case current        // עו״ש
    case digitalWallet  // ארנק דיגיטלי — Bit / PayBox / PayPal balance, etc.
    case savings        // חיסכון
    case investment     // השקעות

    var id: String { rawValue }

    /// TODO: move into the String Catalog later.
    var hebrewLabel: String {
        switch self {
        case .current:       return "עו״ש"
        case .digitalWallet: return "ארנק דיגיטלי"
        case .savings:       return "חיסכון"
        case .investment:    return "השקעות"
        }
    }

    /// SF Symbol shown for this account type, consistent everywhere an
    /// account appears (assets card, transaction editor, onboarding,
    /// analytics allocation list).
    var symbolName: String {
        switch self {
        case .current:       return "banknote"
        case .digitalWallet: return "wallet.bifold"
        case .savings:       return "lock"
        case .investment:    return "chart.line.uptrend.xyaxis"
        }
    }

    /// Fixed sort order for the dashboard and analytics allocation list:
    /// everyday liquid money first (current + digital wallet), then
    /// savings, then investments. Lower rank sorts earlier. Deliberately
    /// has no `default`, so adding a new case becomes a compile error
    /// here until it's given an explicit slot in the order.
    var sortRank: Int {
        switch self {
        case .current:       return 0
        case .digitalWallet: return 1   // liquid like cash, so it sits by current
        case .savings:       return 2
        case .investment:    return 3
        }
    }

    /// Whether money in this account type is spendable today.
    ///
    /// Drives the dashboard's **נזיל / נכסים** split: an עו״ש or a digital
    /// wallet is money you can use this afternoon; a deposit is locked until
    /// maturity and a portfolio has to be sold first, so both read as assets.
    /// Like `sortRank`, deliberately exhaustive with no `default` — a new
    /// account type has to be placed on one side of the line explicitly.
    var isLiquid: Bool {
        switch self {
        case .current, .digitalWallet: return true
        case .savings, .investment:    return false
        }
    }

    /// Whether an account of this type can carry the favourite star.
    ///
    /// "Favourite" means *the account a new transaction defaults to* — the
    /// one you log against without thinking. A deposit is money locked away
    /// until maturity: the user doesn't spend from it, and its only movement
    /// is the payout the app writes itself. Offering it as the default would
    /// hand the transaction sheet an account the user can never sensibly
    /// pick, so deposits are excluded from the star everywhere.
    ///
    /// Like `sortRank` and `isLiquid`, deliberately exhaustive with no
    /// `default`, so a new account type has to answer this question too.
    var allowsFavorite: Bool {
        switch self {
        case .current, .digitalWallet, .investment: return true
        case .savings:                              return false
        }
    }

    /// Decode unknown raw values to a safe fallback instead of throwing.
    ///
    /// SwiftData persists this enum as a composite (Codable) attribute, so
    /// if a case is ever removed or renamed, old rows still holding the old
    /// raw value would otherwise fail to decode and crash the *entire* store
    /// at launch (as happened when `.other` was removed). Falling back to
    /// `.current` degrades one stale field gracefully rather than bricking
    /// the app. Encoding stays the synthesized rawValue path, so storage is
    /// unchanged. (Not a substitute for a real migration once there are real
    /// users — there it would silently reclassify their accounts.)
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AccountType(rawValue: raw) ?? .current
    }
}

/// Whether a spending category is a "need" or a "want". Lets the budget
/// builder visually group planned expenses and lets the dashboard tell
/// the user "you allocate X to needs and Y to wants".
///
/// `neutral` is the default for income categories and for anything the
/// user creates manually later — we never want to silently mislabel.
enum CategoryNature: String, Codable, CaseIterable, Identifiable {
    case need      // צרכים
    case want      // רצונות
    case neutral   // לא מסווג / הכנסה

    var id: String { rawValue }

    var hebrewLabel: String {
        switch self {
        case .need:    return "צרכים"
        case .want:    return "רצונות"
        case .neutral: return "אחר"
        }
    }
}

/// The unit of a budget line's recurrence interval. Combined with a count
/// it expresses "every N <unit>" (every 3 days, every 2 weeks, every month,
/// every 2 years…). This is the modern cadence model; it supersedes the
/// legacy `BudgetFrequencyKind`/`BudgetScheduleKind` pair, which is kept only
/// so old rows still migrate cleanly (see `BudgetItem.recurrenceUnit`).
///
/// The two scales behave differently in the month-based budget:
/// * **Averaged** (`day`, `week`) — shorter than a month, so we spread the
///   amount into a smooth monthly equivalent and count it in *every* month.
/// * **Landing** (`month`, `year`) — the full amount lands only on the
///   months the line actually occurs in (e.g. a quarterly bill shows its
///   whole amount in those months and ₪0 in the rest).
enum RecurrenceUnit: String, Codable, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    /// True for sub-monthly units, which are spread into a monthly average
    /// rather than landing their full amount on specific months.
    var isAveraged: Bool { self == .day || self == .week }
}

/// How often a planned expense recurs. **Legacy** — superseded by
/// `RecurrenceUnit` + a count. Retained because existing `BudgetItem` rows
/// persisted their cadence here; `BudgetItem.recurrenceUnit` falls back to
/// it when the newer `recurrenceUnitRaw` field is absent.
enum BudgetFrequencyKind: String, Codable, CaseIterable, Identifiable {
    case monthly       // חודשי
    case everyXWeeks   // כל X שבועות

    var id: String { rawValue }

    var hebrewLabel: String {
        switch self {
        case .monthly:     return "חודשי"
        case .everyXWeeks: return "כל כמה שבועות"
        }
    }
}

/// *When* a budget line lands on the calendar — the dimension that lets a
/// single budget feed every month correctly:
///
/// * `recurringMonthly` — counts toward **every** month (rent, salary). May
///   optionally pin a day-of-month ("salary on the 10th") for the calendar.
/// * `recurringYearly` — counts toward **one** month each year ("car test
///   every February"), with an optional day inside that month.
/// * `oneTime` — a single dated event ("anniversary gift, 22 Aug"), counted
///   only in its own month.
///
/// Since the move to `RecurrenceUnit` + a count, this enum's live job is
/// narrower: it flags whether a line is `oneTime` versus recurring (the
/// recurring *cadence* now lives in `recurrenceUnit`/`recurrenceCount`). It
/// is still persisted and still distinguishes monthly vs. yearly for **old**
/// rows that predate `recurrenceUnitRaw`, so `BudgetItem.recurrenceUnit` can
/// reconstruct their cadence. A brand-new or migrated row defaults to
/// `recurringMonthly`.
enum BudgetScheduleKind: String, Codable, CaseIterable, Identifiable {
    case recurringMonthly   // כל חודש
    case recurringYearly    // כל שנה
    case oneTime            // חד־פעמי

    var id: String { rawValue }

    var hebrewLabel: String {
        switch self {
        case .recurringMonthly: return "כל חודש"
        case .recurringYearly:  return "כל שנה"
        case .oneTime:          return "חד־פעמי"
        }
    }

    var systemImage: String {
        switch self {
        case .recurringMonthly: return "arrow.clockwise"
        case .recurringYearly:  return "calendar"
        case .oneTime:          return "1.circle"
        }
    }
}
