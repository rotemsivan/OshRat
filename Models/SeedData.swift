import Foundation
import SwiftData

/// Creates a starter set of Hebrew categories the first time the app launches,
/// so the user isn't faced with an empty list. Runs only when none exist yet.
enum SeedData {
    static func seedDefaultCategoriesIfNeeded(in context: ModelContext) {
        // If any category already exists, assume we've seeded before — do nothing.
        let existing = try? context.fetch(FetchDescriptor<Category>())
        guard (existing?.isEmpty ?? true) else { return }

        let defaults: [Category] = [
            // Expenses — הוצאות
            Category(name: "מזון",        kind: .expense, colorHex: "#E57373", symbolName: "cart"),
            Category(name: "דיור",        kind: .expense, colorHex: "#64B5F6", symbolName: "house"),
            Category(name: "תחבורה",      kind: .expense, colorHex: "#FFB74D", symbolName: "car"),
            Category(name: "חשבונות",     kind: .expense, colorHex: "#BA68C8", symbolName: "doc.text"),
            Category(name: "בילויים",     kind: .expense, colorHex: "#4DB6AC", symbolName: "fork.knife"),
            Category(name: "בריאות",      kind: .expense, colorHex: "#F06292", symbolName: "cross.case"),
            // Income — הכנסות
            Category(name: "משכורת",      kind: .income,  colorHex: "#81C784", symbolName: "banknote"),
            Category(name: "הכנסה נוספת", kind: .income,  colorHex: "#AED581", symbolName: "plus.circle"),
        ]

        for category in defaults {
            context.insert(category)
        }
        try? context.save()
    }
}
