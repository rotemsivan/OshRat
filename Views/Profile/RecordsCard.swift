import SwiftUI

/// "השיאים שלי" — the all-time personal bests (biggest expense, busiest
/// month…), under the achievements on the profile tab. They're about the
/// person's history rather than any one period, which is why they moved here
/// from the analytics roadmap.
struct RecordsCard: View {
    let records: [FinancialRecord]
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Label {
                Text("השיאים שלי")
                    .font(Theme.Typography.amount)
                    .foregroundStyle(Theme.Colors.textPrimary)
            } icon: {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(Theme.Colors.accent)
            }
            .accessibilityAddTraits(.isHeader)

            if records.isEmpty {
                Text("עדיין אין שיאים — הם יופיעו ככל שתתעדו יותר.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                ForEach(records) { record in
                    RecordRow(record: record, code: currencyCode)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
