import Foundation

/// Encodes one `ExportTable` (the transactions) as CSV — the plain format
/// for tools other than a spreadsheet, so none of the workbook's styling
/// applies here.
///
/// - **UTF-8 with a byte-order mark.** Without it Excel reads the file as
///   the machine's legacy code page and every Hebrew letter turns to noise.
/// - **RFC 4180**: CRLF line ends, fields quoted when they hold a comma, a
///   quote or a line break, quotes doubled.
/// - **Locale-free values**: ISO dates (`2026-10-10`), 24-hour times, and
///   numbers with a "." point and no grouping, so any program parses them.
/// - **No formulas**: a text field starting with `=`, `+`, `-` or `@` gets a
///   leading `'`, or a spreadsheet would run a title like "=HYPERLINK(…)" as
///   a formula. Number fields are left alone — a negative amount must stay a
///   number.
nonisolated enum CSVWriter {

    static func data(for table: ExportTable) -> Data {
        var lines = [table.columns.map { field($0.header) }.joined(separator: ",")]
        for row in table.rows {
            lines.append(row.cells.map { text(for: $0) }.joined(separator: ","))
        }
        // A trailing line break, as most tools write it.
        let body = lines.joined(separator: "\r\n") + "\r\n"
        return Data([0xEF, 0xBB, 0xBF]) + Data(body.utf8)
    }

    private static func text(for cell: ExportCell) -> String {
        switch cell.value {
        case .empty:
            return ""
        case .text(let string):
            return field(string)
        case .number(let value):
            return plain(value, fractionDigits: fractionDigits(for: cell.role))
        case .date(let year, let month, let day):
            return String(format: "%04d-%02d-%02d", year, month, day)
        case .time(let hour, let minute):
            return String(format: "%02d:%02d", hour, minute)
        }
    }

    private static func fractionDigits(for role: ExportRole) -> Int? {
        switch role {
        case .amount, .money, .budgetDifference: 2
        case .count: 0
        default: nil
        }
    }

    /// A quoted-if-needed text field, defused against formula injection.
    static func field(_ string: String) -> String {
        var value = string
        if let first = value.first, "=+-@".contains(first) {
            value = "'" + value
        }
        // Scalars, not Characters: "\r\n" is one Character, so a lone "\n"
        // would never match it.
        guard value.unicodeScalars.contains(where: { ",\"\r\n".unicodeScalars.contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// `1234.5` → `"1234.50"` with two digits; as stored when `nil`.
    static func plain(_ value: Decimal, fractionDigits: Int?) -> String {
        guard let fractionDigits else { return value.description }
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, fractionDigits, .plain)
        var text = rounded.description
        guard fractionDigits > 0 else { return text }
        if let point = text.firstIndex(of: ".") {
            let existing = text.distance(from: text.index(after: point), to: text.endIndex)
            text += String(repeating: "0", count: max(fractionDigits - existing, 0))
        } else {
            text += "." + String(repeating: "0", count: fractionDigits)
        }
        return text
    }
}
