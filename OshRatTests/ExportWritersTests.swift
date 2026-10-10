import Testing
import Foundation
@testable import OshRat

/// The file formats: the CSV's encoding and escaping, and that the `.xlsx`
/// is a sound ZIP of well-formed, right-to-left sheets.
@MainActor
struct ExportWritersTests {

    private static func table(_ rows: [[ExportCell]]) -> ExportTable {
        ExportTable(
            columns: (0..<(rows.first?.count ?? 1)).map { ExportColumn(header: "עמודה \($0)", width: 10) },
            rows: rows.map { ExportRow(cells: $0) }
        )
    }

    // MARK: - CSV

    @Test func csvStartsWithABOMAndUsesCRLF() throws {
        let data = CSVWriter.data(for: Self.table([[.text("סופר")]]))
        #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        let text = String(decoding: data.dropFirst(3), as: UTF8.self)
        #expect(text == "עמודה 0\r\nסופר\r\n")
    }

    @Test func csvQuotesWhatNeedsQuoting() {
        #expect(CSVWriter.field("a,b") == "\"a,b\"")
        #expect(CSVWriter.field("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSVWriter.field("two\nlines") == "\"two\nlines\"")
        #expect(CSVWriter.field("plain") == "plain")
    }

    @Test func csvDefusesFormulasInTextButNotInNumbers() {
        #expect(CSVWriter.field("=HYPERLINK(\"x\")") == "\"'=HYPERLINK(\"\"x\"\")\"")
        #expect(CSVWriter.field("-dash") == "'-dash")
        #expect(CSVWriter.field("@who") == "'@who")
        let data = CSVWriter.data(for: Self.table([[.number(-12.5, .money(.expense))]]))
        let text = String(decoding: data.dropFirst(3), as: UTF8.self)
        #expect(text.hasSuffix("\r\n-12.50\r\n"))
    }

    @Test func csvWritesLocaleFreeValues() {
        #expect(CSVWriter.plain(1234.5, fractionDigits: 2) == "1234.50")
        #expect(CSVWriter.plain(7, fractionDigits: 2) == "7.00")
        #expect(CSVWriter.plain(Decimal(string: "0.125")!, fractionDigits: 2) == "0.13")
        #expect(CSVWriter.plain(42, fractionDigits: 0) == "42")
        let data = CSVWriter.data(for: Self.table([[
            ExportCell(value: .date(year: 2026, month: 3, day: 7), role: .date),
            ExportCell(value: .time(hour: 9, minute: 5), role: .time),
        ]]))
        let text = String(decoding: data.dropFirst(3), as: UTF8.self)
        #expect(text.hasSuffix("\r\n2026-03-07,09:05\r\n"))
    }

    // MARK: - XLSX

    private static let workbook = ExportWorkbook(
        sheets: [
            ExportSheet(name: "סקירה", subtitle: "טווח", blocks: [
                .cards([ExportKPI(label: "הכנסות", value: 100, tone: .income)]),
            ]),
            ExportSheet(name: "תנועות", subtitle: "טווח & <עוד>", blocks: [
                .table(ExportTable(
                    columns: [ExportColumn(header: "כותרת", width: 20), ExportColumn(header: "סכום", width: 12)],
                    rows: [
                        ExportRow(cells: [.text("קפה \u{1} & מאפה", .category(colorHex: "#E0654B")), .number(-12.5, .money(.expense))]),
                        ExportRow(cells: [.text("ניצול"), .number(0.95, .budgetPercent(.nearLimit))]),
                    ],
                    isPrimary: true
                )),
            ]),
        ],
        currencyCode: "ILS",
        currencySymbol: "₪"
    )

    /// The archive's parts by name, read back through its central directory
    /// with each CRC checked.
    private static func parts(_ data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }

        let end = bytes.count - 22
        #expect(u32(end) == 0x0605_4B50)
        let count = u16(end + 10)
        var cursor = u32(end + 16)
        var parts: [String: Data] = [:]
        for _ in 0..<count {
            #expect(u32(cursor) == 0x0201_4B50)
            let crc = UInt32(u32(cursor + 16))
            let size = u32(cursor + 24)
            let nameLength = u16(cursor + 28)
            let offset = u32(cursor + 42)
            let name = String(decoding: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)
            let start = offset + 30 + u16(offset + 26) + u16(offset + 28)
            let contents = Data(bytes[start..<(start + size)])
            #expect(ZipArchiveWriter.crc32(contents) == crc, "CRC mismatch in \(name)")
            parts[name] = contents
            cursor += 46 + nameLength
        }
        return parts
    }

    @Test func crc32MatchesTheStandard() {
        #expect(ZipArchiveWriter.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test func xlsxHoldsEveryPartWellFormed() throws {
        let parts = try Self.parts(XLSXWriter.data(for: Self.workbook))
        #expect(Set(parts.keys) == [
            "[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels",
            "xl/styles.xml", "xl/worksheets/sheet1.xml", "xl/worksheets/sheet2.xml",
        ])
        for (name, data) in parts {
            let parser = XMLParser(data: data)
            #expect(parser.parse(), "\(name) is not well-formed")
        }
    }

    @Test func xlsxSheetsReadRightToLeftWithoutGridlines() throws {
        let parts = try Self.parts(XLSXWriter.data(for: Self.workbook))
        for index in 1...2 {
            let xml = String(decoding: parts["xl/worksheets/sheet\(index).xml"]!, as: UTF8.self)
            #expect(xml.contains(#"rightToLeft="1""#))
            #expect(xml.contains(#"showGridLines="0""#))
        }
        let ledger = String(decoding: parts["xl/worksheets/sheet2.xml"]!, as: UTF8.self)
        // Escaped, with the control character dropped.
        #expect(ledger.contains("קפה  &amp; מאפה"))
        #expect(ledger.contains("<autoFilter"))
        #expect(ledger.contains(#"state="frozen""#))
        #expect(ledger.contains(#"type="dataBar""#))
        #expect(ledger.contains("FFF58220"))   // the near-limit bar is orange
    }

    @Test func excelSerialsCountFromTheRightEpoch() {
        #expect(XLSXWriter.serial(year: 1900, month: 3, day: 1) == 61)
        #expect(XLSXWriter.serial(year: 2026, month: 1, day: 1) == 46023)
        #expect(XLSXWriter.columnName(0) == "A")
        #expect(XLSXWriter.columnName(25) == "Z")
        #expect(XLSXWriter.columnName(26) == "AA")
    }
}
