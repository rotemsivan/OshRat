import SwiftUI

/// Above each payment of a queue in `PaymentQueueSheet`: where this one sits
/// in the line ("תשלום 2 מתוך 5"), and "רישום כולם" to log every payment
/// still waiting that already has what it needs (`PaymentLogger`). Once that
/// has run and this payment is the one missing something, it says how many
/// were logged and asks for this one.
struct PendingPaymentsBanner: View {
    let position: Int
    let total: Int
    /// Whether any payments wait behind this one to be logged at once.
    let canLogAll: Bool
    /// How many "רישום כולם" logged, once it has run on this payment.
    let loggedCount: Int?
    let onLogAll: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: loggedCount == nil ? "tray.full.fill" : "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(loggedCount == nil ? Theme.Colors.accent : Theme.Colors.income)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("תשלום \(position) מתוך \(total)")
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .contentTransition(.numericText())
                if let note {
                    Text(note)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if canLogAll && loggedCount == nil {
                Button("רישום כולם", action: onLogAll)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Theme.Colors.accent)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var note: String? {
        guard let loggedCount else {
            return canLogAll ? String(localized: "שומרים, מדלגים לאחר כך או מבטלים — או רושמים את כולם בבת אחת.") : nil
        }
        guard loggedCount > 0 else {
            return String(localized: "לכל התשלומים הממתינים חסרים פרטים — ממשיכים אחד אחד.")
        }
        let logged = loggedCount == 1
            ? String(localized: "נרשם תשלום אחד.")
            : String(localized: "נרשמו \(loggedCount) תשלומים.")
        return logged + " " + String(localized: "בתשלום הזה חסרים פרטים — השלימו ושמרו.")
    }
}
