import Foundation

/// Text matching for Hebrew search — the forgiving part of the transactions
/// search, kept pure (strings in, verdicts out) so it can be unit-tested
/// without a store.
///
/// A plain `contains` fails a Hebrew user in several everyday ways, each
/// handled here:
///
/// * **Final letters.** "ירקן" and "ירקנ" are the same word to a reader, and a
///   prefix typed mid-word ("ירקנ…") would never match a title ending in ן.
///   Every final form is folded to its regular letter (ך→כ, ם→מ, ן→נ, ף→פ, ץ→צ).
/// * **Niqqud, geresh and gershayim.** Marks and quote-like punctuation are
///   dropped, so ע״וש, ע"וש and עוש all meet in the middle.
/// * **Full vs. defective spelling.** תוכנית / תכנית, צהריים / צהרים differ
///   only in the vowel letters ו and י, so each word also gets a *skeleton*
///   with those removed (except a leading one, which is usually a consonant).
/// * **Typos.** A misspelt token still matches when it's within a small edit
///   distance of a word, scaled to the token's length. A substitution between
///   two keys that sit next to each other on the Hebrew keyboard costs half —
///   so "יקקן" (ק is right beside ר) finds "ירקן", while unrelated letters
///   need a longer word before they're forgiven.
/// * **Wrong keyboard layout.** "hrei" is what "ירקן" comes out as with the
///   keyboard left on English. A query with Latin letters is also tried as if
///   it had been typed on the Hebrew layout.
enum HebrewSearch {

    // MARK: - Normalisation

    /// Lowercased, marks stripped, final letters folded, quote-like
    /// punctuation removed and every other separator collapsed to a single
    /// space. The one canonical form both the query and the haystack go
    /// through, so they can only ever disagree about letters.
    static func fold(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in text.lowercased().unicodeScalars {
            if scalar.properties.generalCategory == .nonspacingMark { continue } // niqqud, cantillation
            if droppedPunctuation.contains(scalar) { continue }                  // ״ ׳ " ' `
            if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
                if pendingSpace, !result.isEmpty { result.append(" ") }
                pendingSpace = false
                result.append(finalLetters[scalar] ?? scalar)
            } else {
                pendingSpace = true // spaces, hyphens, maqaf, commas, slashes…
            }
        }
        return String(result)
    }

    /// The whitespace-separated words of an already-folded string.
    static func words(ofFolded folded: String) -> [String] {
        folded.split(separator: " ").map(String.init)
    }

    /// A folded word without its vowel letters (ו, י) after the first letter,
    /// so plene and defective spellings of the same word coincide.
    static func skeleton(_ word: String) -> String {
        guard let first = word.first else { return word }
        return String(first) + word.dropFirst().filter { $0 != "ו" && $0 != "י" }
    }

    /// The same keystrokes read on the Hebrew layout, folded — or `nil` when
    /// the text has no Latin letters to reinterpret. Takes the *raw* query,
    /// not a folded one: folding would already have thrown away the `,` `.`
    /// and `;` keys, which carry ת, ץ and ף.
    static func hebrewLayoutVariant(ofRaw text: String) -> String? {
        let lowered = text.lowercased()
        guard lowered.contains(where: { $0.isLetter && latinToHebrew[$0] != nil }) else { return nil }
        return fold(String(lowered.map { latinToHebrew[$0] ?? $0 }))
    }

    // MARK: - Typo tolerance

    /// How much editing a token of this length may need and still match.
    /// Short tokens must be exact — two letters are a prefix, not a typo — a
    /// three-letter token forgives only a slip onto a neighbouring key, and
    /// longer ones a full edit or two.
    static func typoBudget(forLength length: Int) -> Double {
        switch length {
        case ..<3: return 0
        case 3:    return 0.5
        case 4...6: return 1
        default:   return 2
        }
    }

    /// Whether `token` is within its typo budget of `word`, or of a prefix of
    /// it (the user may still be typing — "יקק" should already find "ירקן").
    static func fuzzyMatches(_ token: String, word: String) -> Bool {
        let budget = typoBudget(forLength: token.count)
        guard budget > 0 else { return false }
        let t = Array(token)
        let w = Array(word)
        // A prefix at most one letter shorter or longer than the token, or the
        // whole word when it's shorter than that.
        let lengths = Set([t.count - 1, t.count, t.count + 1].map { min(max($0, 1), w.count) })
        return lengths.contains { distance(t, Array(w.prefix($0)), limit: budget) <= budget }
    }

    /// Weighted optimal-string-alignment distance (Damerau–Levenshtein with
    /// adjacent transpositions): insert, delete, transpose and substitute cost
    /// 1, except a substitution between neighbouring keys, which costs 0.5.
    /// Gives up early — returning something over `limit` — once every cell in
    /// a row is already past it.
    static func distance(_ a: [Character], _ b: [Character], limit: Double) -> Double {
        if a.isEmpty { return Double(b.count) }
        if b.isEmpty { return Double(a.count) }
        var previousPrevious = [Double](repeating: 0, count: b.count + 1)
        var previous = (0...b.count).map(Double.init)
        var current = [Double](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = Double(i)
            var rowMinimum = current[0]
            for j in 1...b.count {
                let substitution: Double
                if a[i - 1] == b[j - 1] {
                    substitution = 0
                } else if keyboardNeighbours[a[i - 1]]?.contains(b[j - 1]) == true {
                    substitution = 0.5
                } else {
                    substitution = 1
                }
                var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + substitution)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    value = min(value, previousPrevious[j - 2] + 1)
                }
                current[j] = value
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > limit { return rowMinimum }
            (previousPrevious, previous, current) = (previous, current, previousPrevious)
        }
        return previous[b.count]
    }

    // MARK: - Tables

    private static let droppedPunctuation: Set<Unicode.Scalar> = [
        "\u{05F3}", "\u{05F4}", // Hebrew geresh ׳ and gershayim ״
        "\"", "'", "`", "\u{2018}", "\u{2019}", "\u{201C}", "\u{201D}",
    ]

    private static let finalLetters: [Unicode.Scalar: Unicode.Scalar] = [
        "ך": "כ", "ם": "מ", "ן": "נ", "ף": "פ", "ץ": "צ",
    ]

    /// The standard Israeli keyboard, row by row, in QWERTY key order. `nil`
    /// marks keys that carry no Hebrew letter (/ and ' on the top row).
    private static let hebrewRows: [(latin: String, hebrew: [Character?], offset: Double)] = [
        ("qwertyuiop", [nil, nil, "ק", "ר", "א", "ט", "ו", "ן", "ם", "פ"], 0),
        ("asdfghjkl;", ["ש", "ד", "ג", "כ", "ע", "י", "ח", "ל", "ך", "ף"], 0.25),
        ("zxcvbnm,.", ["ז", "ס", "ב", "ה", "נ", "מ", "צ", "ת", "ץ"], 0.75),
    ]

    /// Latin key → the Hebrew letter on the same key.
    private static let latinToHebrew: [Character: Character] = {
        var map: [Character: Character] = [:]
        for row in hebrewRows {
            for (latin, hebrew) in zip(row.latin, row.hebrew) {
                if let hebrew { map[latin] = hebrew }
            }
        }
        return map
    }()

    /// Folded letter → the folded letters on physically adjacent keys: the
    /// same row either side, and the rows above and below within a key's
    /// width. Built on folded letters because that's what gets compared, so ן
    /// (folded to נ) lends נ its neighbours as well.
    private static let keyboardNeighbours: [Character: Set<Character>] = {
        var keys: [(letter: Character, row: Int, x: Double)] = []
        for (rowIndex, row) in hebrewRows.enumerated() {
            for (column, hebrew) in row.hebrew.enumerated() {
                guard let hebrew, let folded = fold(String(hebrew)).first else { continue }
                keys.append((folded, rowIndex, Double(column) + row.offset))
            }
        }
        var neighbours: [Character: Set<Character>] = [:]
        for a in keys {
            for b in keys where a.letter != b.letter {
                let sameRow = a.row == b.row && abs(a.x - b.x) == 1
                let adjacentRow = abs(a.row - b.row) == 1 && abs(a.x - b.x) <= 1
                if sameRow || adjacentRow {
                    neighbours[a.letter, default: []].insert(b.letter)
                }
            }
        }
        return neighbours
    }()
}
