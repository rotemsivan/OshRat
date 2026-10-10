import Foundation

/// Encodes an `ExportWorkbook` as an Excel `.xlsx`, dressed like the app.
///
/// An `.xlsx` is a ZIP (`ZipArchiveWriter`) of SpreadsheetML parts: a
/// workbook listing the sheets, a stylesheet, and one XML part per sheet.
/// Strings are written inline (`t="inlineStr"`) instead of through a shared
/// strings table — slightly bigger files, but no second pass over the data.
///
/// **The look** is the app's, light mode, from `DesignSystem/Theme.swift`:
/// a warm off-white page (`background`) with the gridlines off, tables as
/// white cards with hairline separators, an accent header row, the money
/// colours (income green, expense red, luxuries orange), each category on a
/// tint of its own colour (the app's badge),
/// and budget usage drawn as data bars in the budget bar's colours. Every
/// sheet reads right to left.
///
/// The model only says what each cell *means* (`ExportRole`, row kinds,
/// KPI cards); everything about how that looks is decided here, in
/// `Palette` and `StyleBook`. Excel can't embed fonts, so the app's Heebo is
/// named with a sans-serif family as the fallback on machines without it.
nonisolated enum XLSXWriter {

    static func data(for workbook: ExportWorkbook) -> Data {
        var styles = StyleBook()
        let sheets = workbook.sheets.enumerated().map { index, sheet in
            SheetLayout.render(sheet, isFirst: index == 0, symbol: workbook.currencySymbol, styles: &styles)
        }

        var zip = ZipArchiveWriter()
        zip.add("[Content_Types].xml", Data(contentTypes(sheetCount: sheets.count).utf8))
        zip.add("_rels/.rels", Data(rootRelationships.utf8))
        zip.add("xl/workbook.xml", Data(workbookXML(workbook.sheets, layouts: sheets).utf8))
        zip.add("xl/_rels/workbook.xml.rels", Data(workbookRelationships(sheetCount: sheets.count).utf8))
        zip.add("xl/styles.xml", Data(styles.xml().utf8))
        for (index, sheet) in sheets.enumerated() {
            zip.add("xl/worksheets/sheet\(index + 1).xml", Data(sheet.xml.utf8))
        }
        return zip.finished()
    }

    // MARK: - Package parts

    private static let header = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# + "\n"
    private static let mainNS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    private static let relNS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    private static func contentTypes(sheetCount: Int) -> String {
        var xml = header + #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">"#
        xml += #"<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>"#
        xml += #"<Default Extension="xml" ContentType="application/xml"/>"#
        xml += #"<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>"#
        xml += #"<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>"#
        for index in 1..<(sheetCount + 1) {
            xml += #"<Override PartName="/xl/worksheets/sheet\#(index).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"#
        }
        return xml + "</Types>"
    }

    private static let rootRelationships = header
        + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
        + #"<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>"#
        + "</Relationships>"

    private static func workbookRelationships(sheetCount: Int) -> String {
        var xml = header + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
        for index in 0..<sheetCount {
            xml += #"<Relationship Id="rId\#(index + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet\#(index + 1).xml"/>"#
        }
        xml += #"<Relationship Id="rId\#(sheetCount + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>"#
        return xml + "</Relationships>"
    }

    private static func workbookXML(_ sheets: [ExportSheet], layouts: [SheetLayout.Result]) -> String {
        var xml = header + #"<workbook xmlns="\#(mainNS)" xmlns:r="\#(relNS)">"#
        xml += #"<bookViews><workbookView activeTab="0"/></bookViews><sheets>"#
        for (index, sheet) in sheets.enumerated() {
            xml += #"<sheet name="\#(escape(sheet.name))" sheetId="\#(index + 1)" r:id="rId\#(index + 1)"/>"#
        }
        xml += "</sheets>"
        // Excel keeps an autofilter's range as a hidden defined name too.
        let filters = layouts.enumerated().compactMap { index, layout in
            layout.autoFilterRef.map { (index, sheets[index].name, $0) }
        }
        if !filters.isEmpty {
            xml += "<definedNames>"
            for (index, name, ref) in filters {
                let absolute = ref.split(separator: ":").map { cell -> String in
                    let letters = cell.prefix { $0.isLetter }
                    return "$\(letters)$\(cell.dropFirst(letters.count))"
                }.joined(separator: ":")
                xml += #"<definedName name="_xlnm._FilterDatabase" localSheetId="\#(index)" hidden="1">'\#(escape(name))'!\#(absolute)</definedName>"#
            }
            xml += "</definedNames>"
        }
        return xml + "</workbook>"
    }

    // MARK: - Helpers shared by the layout

    /// XML-escaped, with the control characters XML 1.0 forbids dropped (a
    /// note pasted from elsewhere can carry them, and one stray character
    /// would make the whole file unreadable).
    static func escape(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.count)
        for scalar in string.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "\t", "\n", "\r": result.unicodeScalars.append(scalar)
            default:
                if scalar.value >= 0x20, scalar.value != 0xFFFE, scalar.value != 0xFFFF {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }

    /// "A", "B", … "Z", "AA" — a zero-based column index as Excel names it.
    static func columnName(_ index: Int) -> String {
        var index = index
        var name = ""
        repeat {
            name = String(UnicodeScalar(UInt8(65 + index % 26))) + name
            index = index / 26 - 1
        } while index >= 0
        return name
    }

    /// Excel's day number: days since 30 Dec 1899 (the 1900 system).
    static func serial(year: Int, month: Int, day: Int) -> Int {
        daysFromCivil(year, month, day) - daysFromCivil(1899, 12, 30)
    }

    /// Days since 1 Jan 1970 for a proleptic Gregorian date — Howard Hinnant's
    /// `days_from_civil`. Arithmetic only, so no calendar or time zone can
    /// shift a date by a day.
    private static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}

// MARK: - Palette

/// The app's light-mode colours (`Theme.Colors`), as ARGB hex.
nonisolated enum Palette {
    static let background = "F6F5F2"
    static let surface = "FFFFFF"
    static let textPrimary = "1F1F24"
    static let textSecondary = "7A7A82"
    static let separator = "E7E6E2"
    static let accent = "006699"
    static let graphite = "3B3B45"
    static let income = "2FA36B"
    static let expense = "E0654B"
    static let wants = "F58220"
    /// The accent at ~10% on white — a group row's wash.
    static let accentWash = tint("006699", 0.10)

    static func color(_ tone: ExportTone) -> String {
        switch tone {
        case .neutral: textPrimary
        case .income: income
        case .expense: expense
        case .wants: wants
        case .muted: textSecondary
        }
    }

    static func color(_ tone: ExportBudgetTone) -> String {
        switch tone {
        case .onTrack: accent
        case .nearLimit: wants
        case .over: expense
        case .income: income
        }
    }

    /// `hex` mixed into white at `strength` (0…1).
    static func tint(_ hex: String, _ strength: Double) -> String {
        let rgb = components(hex)
        return rgb.map { channel in
            let mixed = 255 - (255 - Double(channel)) * strength
            return String(format: "%02X", Int(mixed.rounded()))
        }.joined()
    }

    /// A category's stored "#RRGGBB" (or "RRGGBB"), normalised; grey if it
    /// doesn't parse.
    static func normalised(_ hex: String) -> String {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard cleaned.count == 6, UInt32(cleaned, radix: 16) != nil else { return "9E9E9E" }
        return cleaned
    }

    private static func components(_ hex: String) -> [Int] {
        let value = Int(normalised(hex), radix: 16) ?? 0x9E9E9E
        return [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF]
    }
}

// MARK: - Styles

/// Interns every distinct look into the stylesheet's tables and hands back
/// its `cellXfs` index — so a layout can ask for any combination (a bold
/// group row holding an income figure, say) without a fixed style list.
nonisolated struct StyleBook {

    nonisolated struct Font: Hashable {
        var bold = false
        var size: Double = 11
        var color = Palette.textPrimary
    }

    nonisolated struct Edge: Hashable {
        var style: String   // "thin", "medium", "thick"
        var color: String
    }

    nonisolated struct Border: Hashable {
        var sides: Edge?    // both sides; a card's gap needs no direction
        var top: Edge?
        var bottom: Edge?
    }

    nonisolated struct Look: Hashable {
        var font = Font()
        var fill: String?
        var border = Border()
        var numberFormat: String?
        var horizontal: String?
        var wrap = false
    }

    private var fonts: [Font] = [Font()]
    /// Excel reserves the first two fills ("none" and "gray125").
    private var fills: [String?] = [nil, nil]
    private var borders: [Border] = [Border()]
    private var formats: [String] = []
    private var looks: [Look] = []
    private var lookIndex: [Look: Int] = [:]

    init() {
        // xf 0: the page itself — every cell nothing else styles.
        _ = index(Look(fill: Palette.background))
    }

    /// The page look, for the columns' default style.
    var pageStyle: Int { 0 }

    mutating func index(_ look: Look) -> Int {
        if let existing = lookIndex[look] { return existing }
        let index = looks.count
        looks.append(look)
        lookIndex[look] = index
        if !fonts.contains(look.font) { fonts.append(look.font) }
        if let fill = look.fill, !fills.contains(fill) { fills.append(fill) }
        if !borders.contains(look.border) { borders.append(look.border) }
        if let format = look.numberFormat, !formats.contains(format) { formats.append(format) }
        return index
    }

    func xml() -> String {
        var xml = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# + "\n"
        xml += #"<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">"#

        if !formats.isEmpty {
            xml += #"<numFmts count="\#(formats.count)">"#
            for (offset, format) in formats.enumerated() {
                xml += #"<numFmt numFmtId="\#(164 + offset)" formatCode="\#(XLSXWriter.escape(format))"/>"#
            }
            xml += "</numFmts>"
        }

        xml += #"<fonts count="\#(fonts.count)">"#
        for font in fonts {
            xml += "<font>" + (font.bold ? "<b/>" : "")
            xml += #"<sz val="\#(font.size)"/><color rgb="FF\#(font.color)"/>"#
            // Heebo is the app's font; family 2 (swiss) makes the fallback a
            // sans-serif where it isn't installed, charset 177 is Hebrew.
            xml += #"<name val="Heebo"/><family val="2"/><charset val="177"/></font>"#
        }
        xml += "</fonts>"

        xml += #"<fills count="\#(fills.count)">"#
        xml += #"<fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>"#
        for fill in fills.dropFirst(2) {
            xml += #"<fill><patternFill patternType="solid"><fgColor rgb="FF\#(fill ?? Palette.surface)"/><bgColor indexed="64"/></patternFill></fill>"#
        }
        xml += "</fills>"

        xml += #"<borders count="\#(borders.count)">"#
        for border in borders {
            xml += "<border>"
            xml += edge("left", border.sides) + edge("right", border.sides)
            xml += edge("top", border.top) + edge("bottom", border.bottom)
            xml += "<diagonal/></border>"
        }
        xml += "</borders>"

        xml += #"<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>"#
        xml += #"<cellXfs count="\#(looks.count)">"#
        for look in looks {
            let format = look.numberFormat.flatMap { formats.firstIndex(of: $0) }.map { 164 + $0 } ?? 0
            let font = fonts.firstIndex(of: look.font) ?? 0
            let fill = look.fill.flatMap { fills.firstIndex(of: $0) } ?? 0
            let border = borders.firstIndex(of: look.border) ?? 0
            xml += #"<xf numFmtId="\#(format)" fontId="\#(font)" fillId="\#(fill)" borderId="\#(border)" xfId="0""#
            xml += #" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">"#
            // Text reads right to left (readingOrder 2), so Hebrew punctuation
            // lands right. Numbers, dates and times read left to right (1):
            // under RTL a minus sign moves to the number's visual right
            // ("6,100.00-"), where the app never puts it.
            xml += "<alignment"
            if let horizontal = look.horizontal { xml += #" horizontal="\#(horizontal)""# }
            xml += #" vertical="center""#
            if look.wrap { xml += #" wrapText="1""# }
            xml += #" readingOrder="\#(look.numberFormat == nil ? 2 : 1)"/></xf>"#
        }
        xml += "</cellXfs>"
        xml += #"<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>"#
        xml += #"<dxfs count="0"/><tableStyles count="0"/>"#
        return xml + "</styleSheet>"
    }

    private func edge(_ name: String, _ edge: Edge?) -> String {
        guard let edge else { return "<\(name)/>" }
        return #"<\#(name) style="\#(edge.style)"><color rgb="FF\#(edge.color)"/></\#(name)>"#
    }
}

// MARK: - Sheet layout

/// Places one `ExportSheet` on a grid: a margin column and row, the title
/// band, then each block with a blank row after it.
nonisolated enum SheetLayout {

    nonisolated struct Result {
        var xml: String
        /// The primary table's header-and-body range, if it has one.
        var autoFilterRef: String?
    }

    /// Content starts in column B; A is the page's margin.
    private static let firstColumn = 1
    private static let marginWidth = 2.5
    private static let cardsPerRow = 3
    private static let cardWidth = 26.0

    nonisolated private struct Cell {
        var column: Int
        var xml: String
    }

    nonisolated private struct Row {
        var height: Double?
        var cells: [Cell] = []
    }

    static func render(_ sheet: ExportSheet, isFirst: Bool, symbol: String, styles: inout StyleBook) -> Result {
        var builder = Builder(symbol: symbol, styles: styles)
        builder.build(sheet)
        styles = builder.styles
        return Result(xml: builder.xml(isFirst: isFirst), autoFilterRef: builder.autoFilterRef)
    }

    nonisolated private struct Builder {
        let symbol: String
        var styles: StyleBook

        private var rows: [Row] = []
        private var widths: [Int: Double] = [:]
        private var merges: [String] = []
        /// Data-bar cells by colour.
        private var bars: [String: [String]] = [:]
        private(set) var autoFilterRef: String?
        private var frozenRows: Int?

        init(symbol: String, styles: StyleBook) {
            self.symbol = symbol
            self.styles = styles
        }

        // MARK: Building

        mutating func build(_ sheet: ExportSheet) {
            appendRow(height: 10)                                  // top margin
            appendRow(height: 34, [(SheetLayout.firstColumn, text(sheet.name, styles.index(.init(
                font: .init(bold: true, size: 20), fill: Palette.background
            ))))])
            appendRow(height: 18, [(SheetLayout.firstColumn, text(sheet.subtitle, styles.index(.init(
                font: .init(size: 11, color: Palette.textSecondary), fill: Palette.background
            ))))])
            appendRow(height: 12)

            for block in sheet.blocks {
                switch block {
                case .cards(let cards): addCards(cards)
                case .table(let table): addTable(table)
                }
                appendRow(height: 16)
            }
        }

        private mutating func addCards(_ cards: [ExportKPI]) {
            // Neighbouring white cards are kept apart by thick borders in the
            // page's own colour, which reads as a gap without a gap column.
            let gap = StyleBook.Edge(style: "thick", color: Palette.background)
            let hairline = StyleBook.Edge(style: "thin", color: Palette.separator)
            let label = styles.index(.init(
                font: .init(size: 10, color: Palette.textSecondary),
                fill: Palette.surface, border: .init(sides: gap), horizontal: "center"
            ))

            for start in stride(from: 0, to: cards.count, by: SheetLayout.cardsPerRow) {
                let chunk = Array(cards[start..<min(start + SheetLayout.cardsPerRow, cards.count)])
                var labels: [(Int, String)] = []
                var values: [(Int, String)] = []
                for (offset, card) in chunk.enumerated() {
                    let column = SheetLayout.firstColumn + offset
                    widths[column] = max(widths[column] ?? 0, SheetLayout.cardWidth)
                    labels.append((column, text(card.label, label)))
                    let value = styles.index(.init(
                        font: .init(bold: true, size: 18, color: Palette.color(card.tone)),
                        fill: Palette.surface, border: .init(sides: gap, bottom: hairline),
                        numberFormat: Self.wholeMoneyFormat(symbol), horizontal: "center"
                    ))
                    values.append((column, number(card.value, value)))
                }
                appendRow(height: 24, labels)
                appendRow(height: 34, values)
                appendRow(height: 10)
            }
        }

        private mutating func addTable(_ table: ExportTable) {
            let columnCount = table.columns.count
            for (index, column) in table.columns.enumerated() {
                widths[SheetLayout.firstColumn + index] = max(widths[SheetLayout.firstColumn + index] ?? 0, column.width)
            }

            if let caption = table.caption {
                appendRow(height: 24, [(SheetLayout.firstColumn, text(caption, styles.index(.init(
                    font: .init(bold: true, size: 13), fill: Palette.background
                ))))])
            }

            let hasHeader = table.columns.contains { !$0.header.isEmpty }
            var headerRow: Int?
            if hasHeader {
                let style = styles.index(.init(
                    font: .init(bold: true, size: 11, color: Palette.surface),
                    fill: Palette.accent, horizontal: "center", wrap: true
                ))
                appendRow(height: 26, table.columns.enumerated().map { index, column in
                    (SheetLayout.firstColumn + index, text(column.header, style))
                })
                headerRow = rows.count
            }

            if table.rows.isEmpty, let note = table.emptyNote {
                let style = styles.index(.init(
                    font: .init(color: Palette.textSecondary), fill: Palette.surface,
                    border: .init(bottom: .init(style: "thin", color: Palette.separator))
                ))
                var cells = [(SheetLayout.firstColumn, text(note, style))]
                for index in 1..<max(columnCount, 1) { cells.append((SheetLayout.firstColumn + index, empty(style))) }
                appendRow(height: 22, cells)
                if columnCount > 1 { merge(row: rows.count, from: SheetLayout.firstColumn, span: columnCount) }
            }

            for row in table.rows {
                addRow(row)
            }

            if table.isPrimary, let headerRow {
                frozenRows = frozenRows ?? headerRow
                if autoFilterRef == nil {
                    let last = max(rows.count, headerRow)
                    autoFilterRef = "\(XLSXWriter.columnName(SheetLayout.firstColumn))\(headerRow):"
                        + "\(XLSXWriter.columnName(SheetLayout.firstColumn + columnCount - 1))\(last)"
                }
            }
        }

        private mutating func addRow(_ row: ExportRow) {
            var cells: [(Int, String)] = []
            var column = SheetLayout.firstColumn
            let rowNumber = rows.count + 1
            for cell in row.cells {
                let style = look(for: cell, in: row.kind)
                let index = styles.index(style)
                cells.append((column, xml(for: cell, style: index, symbol: symbol)))
                if case .budgetPercent(let tone) = cell.role, case .number = cell.value {
                    bars[Palette.color(tone), default: []].append("\(XLSXWriter.columnName(column))\(rowNumber)")
                }
                if cell.span > 1 {
                    // The covered cells carry the same look so the card stays
                    // white (and keeps its separator) under the merge.
                    let covered = styles.index(StyleBook.Look(
                        font: style.font, fill: style.fill, border: style.border
                    ))
                    for offset in 1..<cell.span { cells.append((column + offset, empty(covered))) }
                    merge(row: rowNumber, from: column, span: cell.span)
                }
                column += cell.span
            }
            appendRow(height: row.kind == .body ? 21 : 24, cells)
        }

        // MARK: Looks

        private func look(for cell: ExportCell, in kind: ExportRow.Kind) -> StyleBook.Look {
            let hairline = StyleBook.Edge(style: "thin", color: Palette.separator)
            var look = StyleBook.Look(fill: Palette.surface, border: .init(bottom: hairline))
            switch kind {
            case .body: break
            case .group:
                look.font.bold = true
                look.fill = Palette.accentWash
            case .total:
                look.font.bold = true
                look.border = .init(top: .init(style: "thin", color: Palette.graphite), bottom: hairline)
            }

            switch cell.role {
            case .text:
                break
            case .mutedText:
                look.font.color = Palette.textSecondary
            case .date:
                look.numberFormat = "d.m.yyyy"
                look.horizontal = "center"
            case .time:
                look.numberFormat = "hh:mm"
                look.horizontal = "center"
            case .amount(let tone):
                look.numberFormat = "#,##0.00"
                look.font.color = Palette.color(tone)
            case .money(let tone):
                look.numberFormat = Self.moneyFormat(symbol)
                look.font.color = Palette.color(tone)
            case .budgetDifference:
                look.numberFormat = Self.differenceFormat(symbol)
                if case .number(let value) = cell.value, value < 0 {
                    look.font.color = Palette.expense
                }
            case .percent:
                look.numberFormat = "0.0%"
                look.horizontal = "center"
            case .budgetPercent(let tone):
                look.numberFormat = "0%"
                look.horizontal = "center"
                look.font.color = Palette.color(tone)
            case .count:
                look.numberFormat = "#,##0"
                look.horizontal = "center"
            case .category(let hex):
                // The badge: the name on a tint of the category's colour. (A
                // coloured dot as a rich-text run was tried: viewers dropped
                // its colour and placed it inconsistently under RTL.)
                if kind == .body { look.fill = Palette.tint(Palette.normalised(hex), 0.18) }
            }
            if case .text(let string) = cell.value, string.count > 40 {
                look.wrap = true
            }
            return look
        }

        // One section only, no explicit negative one: Excel *replaces* the sign
        // with a negative section's own "-", but Numbers and some viewers add
        // the value's sign too and showed "--184.00". With a single section
        // every app prefixes the minus itself, once.
        private static func moneyFormat(_ symbol: String) -> String {
            #"#,##0.00 "\#(symbol)""#
        }

        private static func wholeMoneyFormat(_ symbol: String) -> String {
            #"#,##0 "\#(symbol)""#
        }

        /// What's left reads as an amount; an overrun reads "חריגה של …"
        /// (in red, from the cell's font), as the app's budget bar says it.
        private static func differenceFormat(_ symbol: String) -> String {
            ##"#,##0.00 "\##(symbol)";"חריגה של "#,##0.00 "\##(symbol)";0.00 "\##(symbol)""##
        }

        // MARK: Cells

        private func xml(for cell: ExportCell, style: Int, symbol: String) -> String {
            switch cell.value {
            case .empty:
                return empty(style)
            case .number(let value):
                return number(value, style)
            case .date(let year, let month, let day):
                return #"<c s="\#(style)"><v>\#(XLSXWriter.serial(year: year, month: month, day: day))</v></c>"#
            case .time(let hour, let minute):
                let fraction = (Double(hour) * 60 + Double(minute)) / 1440
                return #"<c s="\#(style)"><v>\#(fraction)</v></c>"#
            case .text(let string):
                return text(string, style)
            }
        }

        private func text(_ string: String, _ style: Int) -> String {
            #"<c s="\#(style)" t="inlineStr"><is><t xml:space="preserve">\#(XLSXWriter.escape(string))</t></is></c>"#
        }

        private func number(_ value: Decimal, _ style: Int) -> String {
            // `Decimal.description` is locale-independent: always a "." point.
            #"<c s="\#(style)"><v>\#(value.description)</v></c>"#
        }

        private func empty(_ style: Int) -> String {
            #"<c s="\#(style)"/>"#
        }

        // MARK: Rows

        private mutating func appendRow(height: Double? = nil, _ cells: [(Int, String)] = []) {
            rows.append(Row(height: height, cells: cells.map { Cell(column: $0.0, xml: $0.1) }))
        }

        private mutating func merge(row: Int, from column: Int, span: Int) {
            merges.append("\(XLSXWriter.columnName(column))\(row):\(XLSXWriter.columnName(column + span - 1))\(row)")
        }

        // MARK: Output

        func xml(isFirst: Bool) -> String {
            var xml = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"# + "\n"
            xml += #"<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">"#

            // Right to left, no gridlines — the page is the app's background.
            xml += #"<sheetViews><sheetView rightToLeft="1" showGridLines="0""#
            if isFirst { xml += #" tabSelected="1""# }
            xml += #" workbookViewId="0">"#
            if let frozenRows {
                xml += #"<pane ySplit="\#(frozenRows)" topLeftCell="A\#(frozenRows + 1)" activePane="bottomLeft" state="frozen"/>"#
            }
            xml += "</sheetView></sheetViews>"
            xml += #"<sheetFormatPr defaultRowHeight="18" customHeight="1"/>"#

            // Every column — the used ones at their widths, the rest to the
            // edge of the sheet — defaults to the page look, so the whole
            // visible sheet is the app's background, not just the used cells.
            let page = styles.pageStyle
            let lastUsed = max(widths.keys.max() ?? SheetLayout.firstColumn, SheetLayout.firstColumn)
            xml += "<cols>"
            xml += #"<col min="1" max="1" width="\#(SheetLayout.marginWidth)" style="\#(page)" customWidth="1"/>"#
            for column in SheetLayout.firstColumn...lastUsed {
                let width = widths[column] ?? 10
                xml += #"<col min="\#(column + 1)" max="\#(column + 1)" width="\#(width)" style="\#(page)" customWidth="1"/>"#
            }
            xml += #"<col min="\#(lastUsed + 2)" max="16384" width="10" style="\#(page)"/>"#
            xml += "</cols>"

            xml += "<sheetData>"
            for (index, row) in rows.enumerated() {
                let number = index + 1
                xml += #"<row r="\#(number)""#
                if let height = row.height { xml += #" ht="\#(height)" customHeight="1""# }
                if row.cells.isEmpty {
                    xml += "/>"
                    continue
                }
                xml += ">"
                for cell in row.cells.sorted(by: { $0.column < $1.column }) {
                    // Insert the reference into the prepared `<c` tag.
                    let reference = "\(XLSXWriter.columnName(cell.column))\(number)"
                    xml += #"<c r="\#(reference)""# + cell.xml.dropFirst(2)
                }
                xml += "</row>"
            }
            xml += "</sheetData>"

            if let autoFilterRef {
                xml += #"<autoFilter ref="\#(autoFilterRef)"/>"#
            }
            if !merges.isEmpty {
                xml += #"<mergeCells count="\#(merges.count)">"#
                for merge in merges { xml += #"<mergeCell ref="\#(merge)"/>"# }
                xml += "</mergeCells>"
            }
            // The budget bar: a data bar per used-share cell, 0–100%, in the
            // colour the app's bar would be.
            var priority = 1
            for (color, cells) in bars.sorted(by: { $0.key < $1.key }) {
                xml += #"<conditionalFormatting sqref="\#(cells.joined(separator: " "))">"#
                xml += #"<cfRule type="dataBar" priority="\#(priority)"><dataBar>"#
                xml += #"<cfvo type="num" val="0"/><cfvo type="num" val="1"/><color rgb="FF\#(color)"/>"#
                xml += "</dataBar></cfRule></conditionalFormatting>"
                priority += 1
            }
            xml += #"<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/>"#
            return xml + "</worksheet>"
        }
    }
}
