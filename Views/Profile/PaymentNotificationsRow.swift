import SwiftUI

/// The Apple Pay setup's one in-app step: letting עכבר עו״ש post the
/// payment notification. `LogPaymentIntent` runs in the background where no
/// permission prompt can appear, so it's asked for here. Already allowed
/// shows a quiet tick; turned down sends the user to the app's page in
/// Settings, the only place it can be changed afterwards.
struct PaymentNotificationsRow: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var permission: PaymentNotifier.Permission?

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: permission == .allowed ? "bell.badge.fill" : "bell.slash")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(permission == .allowed ? Theme.Colors.income : Theme.Colors.accent)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("התראה אחרי תשלום")
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(statusText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Spacing.sm)

            switch permission {
            case .notAsked:
                Button("הפעלה", action: requestPermission)
                    .buttonStyle(.borderedProminent)
            case .denied:
                Button("הגדרות", action: openSettings)
                    .buttonStyle(.bordered)
            case .allowed, nil:
                EmptyView()
            }
        }
        .tint(Theme.Colors.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        // Re-read on return from Settings, where it may have been switched on.
        .task(id: scenePhase) { await refresh() }
    }

    private var statusText: LocalizedStringKey {
        switch permission {
        case .allowed:  "פעיל — התשלום יחכה לכם בהתראה."
        case .denied:   "ההתראות כבויות. אפשר להפעיל אותן בהגדרות."
        case .notAsked: "בלעדיה התשלום נשמר, אבל שום דבר לא יזכיר לכם לרשום אותו."
        case nil:       " "
        }
    }

    private func refresh() async {
        permission = await PaymentNotifier.permission()
    }

    private func requestPermission() {
        Task { permission = await PaymentNotifier.requestPermission() }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
