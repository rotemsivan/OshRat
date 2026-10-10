import Foundation

/// Just enough of the ZIP format to package an `.xlsx`, which is a ZIP of
/// XML parts.
///
/// Written by hand rather than pulled in as a dependency. The app has no
/// third-party packages, and an export needs only the simplest case: a few
/// small files, stored uncompressed ("stored", method 0), in one pass. That
/// takes local headers, a central directory and a CRC-32, about a hundred
/// lines. Excel and Numbers open stored archives fine; a workbook with
/// thousands of rows is still well under a few MB.
nonisolated struct ZipArchiveWriter {

    private struct Entry {
        let name: Data
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
    }

    private var archive = Data()
    private var entries: [Entry] = []

    /// Appends one file. `path` uses forward slashes, e.g. `xl/workbook.xml`.
    mutating func add(_ path: String, _ contents: Data) {
        let name = Data(path.utf8)
        let crc = Self.crc32(contents)
        let entry = Entry(
            name: name,
            crc: crc,
            size: UInt32(contents.count),
            offset: UInt32(archive.count)
        )

        // Local file header.
        archive.append(le32: 0x0403_4B50)
        archive.append(le16: 20)              // version needed: 2.0
        archive.append(le16: 1 << 11)         // flags: names are UTF-8
        archive.append(le16: 0)               // method: stored
        archive.append(le16: Self.dosTime)
        archive.append(le16: Self.dosDate)
        archive.append(le32: crc)
        archive.append(le32: entry.size)      // compressed size
        archive.append(le32: entry.size)      // uncompressed size
        archive.append(le16: UInt16(name.count))
        archive.append(le16: 0)               // extra field length
        archive.append(name)
        archive.append(contents)

        entries.append(entry)
    }

    /// The finished archive: the files, then the central directory and its
    /// end record.
    func finished() -> Data {
        var data = archive
        let directoryStart = UInt32(data.count)
        for entry in entries {
            data.append(le32: 0x0201_4B50)
            data.append(le16: 20)             // version made by
            data.append(le16: 20)             // version needed
            data.append(le16: 1 << 11)
            data.append(le16: 0)
            data.append(le16: Self.dosTime)
            data.append(le16: Self.dosDate)
            data.append(le32: entry.crc)
            data.append(le32: entry.size)
            data.append(le32: entry.size)
            data.append(le16: UInt16(entry.name.count))
            data.append(le16: 0)              // extra field length
            data.append(le16: 0)              // comment length
            data.append(le16: 0)              // disk number
            data.append(le16: 0)              // internal attributes
            data.append(le32: 0)              // external attributes
            data.append(le32: entry.offset)
            data.append(entry.name)
        }
        let directorySize = UInt32(data.count) - directoryStart

        data.append(le32: 0x0605_4B50)
        data.append(le16: 0)                  // this disk
        data.append(le16: 0)                  // disk with the directory
        data.append(le16: UInt16(entries.count))
        data.append(le16: UInt16(entries.count))
        data.append(le32: directorySize)
        data.append(le32: directoryStart)
        data.append(le16: 0)                  // comment length
        return data
    }

    // MARK: - Details

    /// A fixed timestamp (1 Jan 2026, midnight) — the parts' modification
    /// time means nothing to a spreadsheet, and a constant keeps the output
    /// deterministic for tests.
    private static let dosTime: UInt16 = 0
    private static let dosDate: UInt16 = UInt16((2026 - 1980) << 9 | 1 << 5 | 1)

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    /// The standard CRC-32 (IEEE 802.3) the ZIP format checks each file with.
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    nonisolated mutating func append(le16 value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    nonisolated mutating func append(le32 value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
