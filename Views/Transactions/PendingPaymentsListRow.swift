import SwiftUI

/// At the top of the transactions list while card payments wait to be logged
/// — skipped ones ("דילוג") and any not yet seen: how many, and that they
/// don't wait forever. Tapping it brings the line back up in
/// `PaymentQueueSheet` (`IncomingPaymentRouter.requestReview`), skipped ones
/// included.
struct PendingPaymentsListRow: View {
    let count: Int
    let onReview: () -> Void

    var body: some View {
        Button(action: onReview) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typography.body.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("תשלומים שלא נרשמו נמחקים אחרי שבוע")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("פותח את התשלומים לרישום"))
    }

    private var title: String {
        count == 1
            ? String(localized: "תשלום אחד ממתין לרישום")
            : String(localized: "\(count) תשלומים ממתינים לרישום")
    }
}
