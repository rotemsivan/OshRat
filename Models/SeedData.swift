import Foundation
import SwiftData

/// Creates a starter set of Hebrew categories the first time the app launches,
/// so the user isn't faced with an empty list. Runs only when none exist yet.
///
/// Each expense category is tagged as a *need* (צרכים) or a *want* (רצונות)
/// so the budget builder during onboarding — and the dashboard later — can
/// visually distinguish "must-pay" lines from discretionary spending.
/// Income categories use `.neutral`.
enum SeedData {
    static func seedDefaultCategoriesIfNeeded(in context: ModelContext) {
        // If any category already exists, assume we've seeded before — do nothing.
        let existing = try? context.fetch(FetchDescriptor<Category>())
        guard (existing?.isEmpty ?? true) else { return }

        for category in defaultCategories() {
            context.insert(category)
        }
        try? context.save()
    }

    /// Returns a fresh batch of the starter categories. Pulled out so the
    /// dev "reset" flow can re-seed without going through the
    /// "only if empty" gate above.
    static func defaultCategories() -> [Category] {
        return [
            // NEEDS — צרכים
            Category(name: "מזון",              kind: .expense, colorHex: "#E57373", symbolName: "cart",            nature: .need),
            Category(name: "שכירות",            kind: .expense, colorHex: "#64B5F6", symbolName: "house",           nature: .need),
            Category(name: "חשבונות",           kind: .expense, colorHex: "#BA68C8", symbolName: "doc.text",        nature: .need),
            Category(name: "ביטוחים",           kind: .expense, colorHex: "#9575CD", symbolName: "shield",          nature: .need),
            Category(name: "לימודים",           kind: .expense, colorHex: "#7986CB", symbolName: "graduationcap",   nature: .need),
            Category(name: "תחבורה ציבורית",   kind: .expense, colorHex: "#FFB74D", symbolName: "bus",             nature: .need),
            Category(name: "הוצאות רכב",        kind: .expense, colorHex: "#FF8A65", symbolName: "car",             nature: .need),
            Category(name: "בריאות",            kind: .expense, colorHex: "#F06292", symbolName: "cross.case",      nature: .need),

            // WANTS — רצונות
            Category(name: "בילויים",                 kind: .expense, colorHex: "#4DB6AC", symbolName: "ticket",     nature: .want),
            Category(name: "מסעדות ובתי קפה",       kind: .expense, colorHex: "#81C784", symbolName: "fork.knife", nature: .want),
            Category(name: "קניות בגדים",            kind: .expense, colorHex: "#F48FB1", symbolName: "tshirt",      nature: .want),
            Category(name: "מתנות",                    kind: .expense, colorHex: "#FFB74D", symbolName: "gift",       nature: .want),
            Category(name: "טיפוח",                    kind: .expense, colorHex: "#CE93D8", symbolName: "scissors",   nature: .want),
            Category(name: "אימונים",                 kind: .expense, colorHex: "#A1887F", symbolName: "figure.run",  nature: .want),

            // INCOME — הכנסות
            Category(name: "משכורת",      kind: .income, colorHex: "#81C784", symbolName: "banknote",    nature: .neutral),
            Category(name: "הכנסה נוספת", kind: .income, colorHex: "#AED581", symbolName: "plus.circle", nature: .neutral),
        ]
    }
}
