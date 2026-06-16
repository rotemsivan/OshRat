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
enum AccountType: String, Codable, CaseIterable, Identifiable {
    case current      // עו״ש
    case savings      // חיסכון
    case investment   // השקעות
    case other        // אחר

    var id: String { rawValue }

    /// TODO: move into the String Catalog later.
    var hebrewLabel: String {
        switch self {
        case .current:    return "עו״ש"
        case .savings:    return "חיסכון"
        case .investment: return "השקעות"
        case .other:      return "אחר"
        }
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

/// How often a planned expense recurs. `monthly` is by far the common
/// case (rent, subscriptions, bills). `everyXWeeks` covers things like
/// "barber every 3 weeks" — the dashboard converts these to a monthly
/// equivalent so totals line up.
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
/// Orthogonal to `BudgetFrequencyKind`: frequency answers "how big is the
/// monthly slice" for recurring-monthly lines, while this answers "which
/// months does the line appear in at all". A brand-new or migrated row
/// defaults to `recurringMonthly`, so existing budgets behave exactly as
/// before.
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
