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
