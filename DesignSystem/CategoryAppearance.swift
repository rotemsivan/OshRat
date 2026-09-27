import Foundation

/// The closed lists a category's look is chosen from in the category editor:
/// a set of SF Symbols, grouped by theme, and a palette of colours.
///
/// Closed on purpose. SF Symbols has thousands of glyphs, most of which read
/// as nothing at the 13–22pt the app draws categories at; a curated grid of
/// money-life icons is quicker to pick from and keeps every category looking
/// like part of the same set. Every symbol a default category uses is in
/// here, so editing one shows its current icon selected.
enum CategoryAppearance {

    struct SymbolGroup: Identifiable {
        let title: String
        let symbols: [String]
        var id: String { title }
    }

    static let symbolGroups: [SymbolGroup] = [
        SymbolGroup(title: "בית ומשפחה", symbols: [
            "house", "cart", "basket", "sofa", "bed.double", "lightbulb", "drop",
            "flame", "wifi", "phone", "stroller", "figure.2.and.child.holdinghands",
            "pawprint", "leaf", "wrench.and.screwdriver"
        ]),
        SymbolGroup(title: "תחבורה", symbols: [
            "car", "bus", "tram", "bicycle", "fuelpump", "parkingsign", "airplane"
        ]),
        SymbolGroup(title: "בריאות וטיפוח", symbols: [
            "cross.case", "pills", "stethoscope", "heart", "scissors",
            "figure.run", "dumbbell", "eyeglasses"
        ]),
        SymbolGroup(title: "פנאי", symbols: [
            "ticket", "fork.knife", "cup.and.saucer", "wineglass", "gamecontroller",
            "music.note", "film", "play.rectangle", "book", "paintpalette",
            "camera", "tshirt", "bag", "gift"
        ]),
        SymbolGroup(title: "כסף ועבודה", symbols: [
            "banknote", "creditcard", "doc.text", "shield", "building.columns",
            "briefcase", "laptopcomputer", "graduationcap", "percent", "plus.circle",
            "chart.line.uptrend.xyaxis", "chart.line.downtrend.xyaxis"
        ]),
        SymbolGroup(title: "כללי", symbols: [
            "tag", "star", "sparkles", "globe", "ellipsis.circle"
        ])
    ]

    static var allSymbols: [String] { symbolGroups.flatMap(\.symbols) }

    /// Hex colours, in the soft Material-ish tones the default categories use.
    static let colors: [String] = [
        "#E57373", "#E53935", "#F06292", "#F48FB1", "#BA68C8", "#9575CD",
        "#7986CB", "#64B5F6", "#4DB6AC", "#81C784", "#AED581", "#FFB74D",
        "#FF8A65", "#A1887F", "#90A4AE", "#546E7A"
    ]

    /// Defaults for a brand-new category.
    static let defaultSymbol = "tag"
    static let defaultColor = "#64B5F6"
}
