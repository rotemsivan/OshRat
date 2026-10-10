import Foundation
import SwiftData

/// Writes an export file from the store: Excel (the transactions plus the
/// summary sheets) or CSV (the transactions alone).
///
/// The workbook is built here on the main actor, because it reads SwiftData
/// models; encoding it and writing the file happen off it, so a long ledger
/// doesn't freeze the screen. The file goes to a fresh temporary folder and
/// is handed to the share sheet — the app never sends it anywhere itself.
enum ExportService {

    enum Format: String, CaseIterable, Identifiable {
        case excel
        case csv

        var id: String { rawValue }

        var fileExtension: String {
            switch self {
            case .excel: "xlsx"
            case .csv: "csv"
            }
        }
    }

    /// The live rows in `interval` — what the export screen counts.
    static func transactionCount(in interval: DateInterval?, context: ModelContext) -> Int {
        let descriptor: FetchDescriptor<Transaction>
        if let interval {
            let start = interval.start
            let end = interval.end
            descriptor = FetchDescriptor(predicate: #Predicate {
                $0.deletedAt == nil && $0.date >= start && $0.date < end
            })
        } else {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.deletedAt == nil })
        }
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Builds the export and writes it to a temporary file, returning its URL.
    static func export(
        _ format: Format,
        interval: DateInterval?,
        context: ModelContext,
        now: Date = .now
    ) async throws -> URL {
        let workbook = try workbook(interval: interval, context: context, now: now)
        let name = fileName(format: format, now: now)

        // CSV carries the transactions sheet alone; nil means the whole workbook.
        let csvTable: ExportTable? = format == .csv
            ? workbook.sheet(named: TransactionExport.SheetName.transactions)?.tables.first
                ?? ExportTable(columns: [], rows: [])
            : nil

        return try await Task.detached(priority: .userInitiated) {
            let data = csvTable.map { CSVWriter.data(for: $0) } ?? XLSXWriter.data(for: workbook)
            return try write(data, named: name)
        }.value
    }

    static func workbook(interval: DateInterval?, context: ModelContext, now: Date = .now) throws -> ExportWorkbook {
        var transactions = FetchDescriptor<Transaction>(predicate: #Predicate { $0.deletedAt == nil })
        // The rows read their category and accounts; prefetching them saves a
        // fault per row, as the transactions list does.
        transactions.relationshipKeyPathsForPrefetching = [\.category, \.account, \.destinationAccount]
        let profile = try context.fetch(FetchDescriptor<UserProfile>(sortBy: [SortDescriptor(\.createdAt)])).first
        let snapshot = try context.fetch(
            FetchDescriptor<FXRateSnapshot>(sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)])
        ).first

        return TransactionExport.workbook(
            transactions: try context.fetch(transactions),
            budgetItems: try context.fetch(FetchDescriptor<BudgetItem>()),
            accounts: try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.deletedAt == nil })),
            preferredCurrency: profile?.preferredCurrencyCode ?? "ILS",
            fxSnapshot: snapshot,
            interval: interval,
            calendar: TransactionFilters.calendar,
            now: now
        )
    }

    /// "עכבר עוש – 2026-10-10.xlsx". The gershayim is left out of the file
    /// name: some mail and cloud services mangle it.
    static func fileName(format: Format, now: Date) -> String {
        let parts = TransactionFilters.calendar.dateComponents([.year, .month, .day], from: now)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 2000, parts.month ?? 1, parts.day ?? 1)
        return "עכבר עוש – \(day).\(format.fileExtension)"
    }

    /// A folder of its own under the temporary directory, cleared on each
    /// export so old files don't pile up.
    nonisolated private static func write(_ data: Data, named name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Export", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try data.write(to: url, options: .atomic)
        return url
    }
}
