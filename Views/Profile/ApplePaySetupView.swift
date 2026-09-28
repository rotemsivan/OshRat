import SwiftUI

/// "רישום אוטומטי מ-Apple Pay" — how to make a tap at the till open the app on
/// a pre-filled transaction.
///
/// iOS tells apps nothing about Apple Pay payments, so this can't be a
/// switch: the user builds a Shortcuts automation once, and this screen walks
/// them through it (see `LogPaymentIntent` for why this is the only route).
/// Pushed from the profile tab's toolbar until a Settings screen exists.
///
/// The limits are stated up front rather than discovered: it fires on
/// in-store taps only, and what reaches the app depends on the card issuer.
struct ApplePaySetupView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                intro
                steps
                limits
                openShortcutsButton
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            // The button is the last element and is interactive, so clear the
            // floating "+" as well as the bar.
            .padding(.bottom, HomeBottomBar.floatingButtonClearance)
        }
        .scrollIndicators(.hidden)
        .background(Theme.Colors.background)
        .navigationTitle(Text("רישום מ-Apple Pay"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label {
                Text("משלמים — והתנועה כבר ממתינה")
                    .foregroundStyle(Theme.Colors.textPrimary)
            } icon: {
                Image(systemName: "wave.3.right.circle.fill")
                    .foregroundStyle(Theme.Colors.accent)
            }
            .font(Theme.Typography.amount)
            Text("אחרי תשלום בכרטיס מהארנק, עכבר עו״ש נפתח עם תנועה חדשה שכבר מולאו בה הסכום ובית העסק. נשאר רק להחליק. בפעם הבאה באותו בית עסק, גם השם, הקטגוריה והחשבון שבחרת יחכו מוכנים.")
                .font(Theme.Typography.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// The one-time automation, in the order the Shortcuts app asks for it.
    private var steps: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("הגדרה חד־פעמית באפליקציית קיצורים")
                .font(Theme.Typography.amount)
                .foregroundStyle(Theme.Colors.textPrimary)
            ForEach(Array(Self.stepTexts.enumerated()), id: \.offset) { index, text in
                SetupStep(number: index + 1, text: text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private static let stepTexts: [LocalizedStringKey] = [
        "פתחו את **קיצורים** ועברו ללשונית **אוטומציה**.",
        "הקישו **+** ובחרו **עסקה** (Transaction).",
        "בחרו את הכרטיסים שבהם אתם משלמים, וסמנו **הפעלה מיידית**.",
        "הוסיפו את הפעולה **רישום תשלום** של עכבר עו״ש.",
        "בשדות **סכום**, **בית עסק** ו**כרטיס** בחרו את הערכים מתוך **קלט הקיצור** — סכום, סוחר ושם הכרטיס.",
        "שמרו. מעכשיו כל תשלום בארנק יפתח את התנועה מוכנה."
    ]

    private var limits: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("כדאי לדעת")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            limitLine("creditcard", "עובד בתשלום בהצמדת הטלפון או השעון בקופה — לא בקניות אונליין או בתוך אפליקציות.")
            limitLine("building.columns", "אילו פרטים מגיעים תלוי בחברת האשראי. מה שלא הגיע יישאר ריק ותוכלו להשלים.")
            limitLine("lock.shield", "הכול נשאר במכשיר: הפרטים עוברים מהארנק לאפליקציה בלי אינטרנט ובלי חיבור לבנק.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func limitLine(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Theme.Colors.accent)
        }
        .font(Theme.Typography.bodySmall)
        .foregroundStyle(Theme.Colors.textPrimary)
    }

    private var openShortcutsButton: some View {
        // `shortcuts://` opens the Shortcuts app; iOS offers no deep link
        // straight into "new automation".
        Link(destination: URL(string: "shortcuts://")!) {
            Label("פתיחת קיצורים", systemImage: "arrow.up.forward.app")
                .font(Theme.Typography.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.Colors.accent)
    }
}

/// One numbered step: a filled circle with the number, then the text.
private struct SetupStep: View {
    let number: Int
    let text: LocalizedStringKey

    @ScaledMetric(relativeTo: .caption) private var badgeSize: CGFloat = 24

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Text(number, format: .number)
                .font(Theme.Typography.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: badgeSize, height: badgeSize)
                .background(Theme.Colors.accent, in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.bodySmall)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("שלב \(number)"))
        .accessibilityValue(Text(text))
    }
}

#Preview {
    NavigationStack {
        ApplePaySetupView()
    }
    .environment(\.layoutDirection, .rightToLeft)
}
