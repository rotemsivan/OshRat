import Foundation
import SwiftData

/// The budget editor's expense lines, nested the way a budget is read:
/// צרכים / מותרות / אחר → category → line. Pure and testable — the editor
/// (`BudgetEditorSheet`) only draws it.
///
/// Every row is a **value snapshot**, never the `BudgetItem` itself: deleting a
/// budget line is a hard delete, and a row still animating out that reads a
/// model's properties traps (the hard-delete trap in CLAUDE.md). The editor
/// turns a line's `id` back into the model only when it acts on it.
struct BudgetLineGroups {
    /// Needs, wants, other — in that order, empty ones left out.
    let sections: [Section]
    /// Some line couldn't be converted to the preferred currency, so a total
    /// leaves it out.
    let fxUnavailable: Bool

    enum Bucket: String, CaseIterable {
        case needs, wants, other
    }

    struct Section: Identifiable {
        let bucket: Bucket
        /// Per month, in the preferred currency: recurring lines only.
        let monthlyTotal: Decimal
        let groups: [CategoryGroup]
        var id: Bucket { bucket }
    }

    struct CategoryGroup: Identifiable {
        /// Name + nature, so two not-yet-merged copies of one category (two
        /// devices seeding before they sync) share a group. "" for lines with
        /// no category.
        let id: String
        /// `nil` for lines with no category ("ללא קטגוריה").
        let name: String?
        let symbolName: String
        let colorHex: String
        let monthlyTotal: Decimal
        let lines: [Line]
    }

    struct Line: Identifiable {
        let id: PersistentIdentifier
        /// The line's note, or its schedule when it has none — the category
        /// is already the row above it.
        let title: String
        /// The schedule, when it isn't already the title.
        let subtitle: String?
        let amount: Decimal
        let currencyCode: String
        /// "~₪X חודשי" for a line that repeats more often than monthly.
        let averagedMonthly: Decimal?
    }

    init(items: [BudgetItem], preferredCurrency: String, fxSnapshot: FXRateSnapshot?) {
        var fxMissing = false
        /// A recurring line's share of a month, in the preferred currency.
        /// One-time lines aren't monthly, so they count as nothing.
        func monthly(_ item: BudgetItem) -> Decimal {
            guard !item.isOneTime else { return 0 }
            if item.currencyCode == preferredCurrency { return item.monthlyEquivalent }
            guard let fxSnapshot,
                  let converted = CurrencyConverter.convert(
                      item.monthlyEquivalent, from: item.currencyCode, to: preferredCurrency, using: fxSnapshot
                  )
            else {
                fxMissing = true
                return 0
            }
            return converted
        }

        var byBucket: [Bucket: [String: [(item: BudgetItem, monthly: Decimal)]]] = [:]
        for item in items where item.kind == .expense {
            let bucket: Bucket
            switch item.category?.nature {
            case .need: bucket = .needs
            case .want: bucket = .wants
            case .neutral, nil: bucket = .other
            }
            let key = item.category.map { "\($0.name)|\($0.natureRaw)" } ?? ""
            byBucket[bucket, default: [:]][key, default: []].append((item, monthly(item)))
        }

        sections = Bucket.allCases.compactMap { bucket in
            guard let byCategory = byBucket[bucket] else { return nil }
            let groups = byCategory.map { key, entries in
                let category = entries.first?.item.category
                let lines = entries
                    .sorted { $0.monthly > $1.monthly }
                    .map { Self.line(for: $0.item) }
                return CategoryGroup(
                    id: key,
                    name: category?.name,
                    symbolName: category?.symbolName ?? "questionmark.circle",
                    colorHex: category?.colorHex ?? "#9E9E9E",
                    monthlyTotal: entries.reduce(0) { $0 + $1.monthly },
                    lines: lines
                )
            }
            .sorted { a, b in
                if a.monthlyTotal != b.monthlyTotal { return a.monthlyTotal > b.monthlyTotal }
                return (a.name ?? "").localizedStandardCompare(b.name ?? "") == .orderedAscending
            }
            return Section(bucket: bucket, monthlyTotal: groups.reduce(0) { $0 + $1.monthlyTotal }, groups: groups)
        }
        fxUnavailable = fxMissing
    }

    /// The group a line sits in — so the editor can open it after a save.
    func groupID(containing lineID: PersistentIdentifier) -> String? {
        for section in sections {
            for group in section.groups where group.lines.contains(where: { $0.id == lineID }) {
                return group.id
            }
        }
        return nil
    }

    private static func line(for item: BudgetItem) -> Line {
        let note = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let schedule = item.scheduleDescription
        return Line(
            id: item.persistentModelID,
            title: note.isEmpty ? schedule : note,
            subtitle: note.isEmpty ? nil : schedule,
            amount: item.plannedAmount,
            currencyCode: item.currencyCode,
            averagedMonthly: !item.isOneTime && item.recurrenceUnit.isAveraged ? item.monthlyEquivalent : nil
        )
    }
}
