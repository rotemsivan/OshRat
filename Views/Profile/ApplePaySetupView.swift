import SwiftUI

/// "רישום אוטומטי מ-Apple Pay" — how to make a tap at the till leave a
/// notification that opens a pre-filled transaction.
///
/// iOS tells apps nothing about Apple Pay payments, so this can't be a
/// switch: the user builds a Shortcuts automation once, and this screen walks
/// them through it (see `LogPaymentIntent` for why this is the only route).
/// Pushed from Settings → רישום מ-Apple Pay.
///
/// A short promise, the numbered steps, then the one thing the app itself
/// needs — permission to post the payment's notification
/// (`PaymentNotificationsRow`) — and the way into Shortcuts. (An animated
/// walkthrough on a drawn phone was tried and dropped in favour of the text.)
///
/// A ready-made shortcut shared by iCloud link was tried and dropped: a
/// standalone shortcut doesn't accept a Wallet payment as its input, so the
/// automation handed it nothing. The action has to sit in the automation
/// itself, with its fields tied to the Shortcut Input.
struct ApplePaySetupView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                intro
                steps
                PaymentNotificationsRow()
                openShortcutsButton
                limits
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            // Clear the floating "+" as well as the bar, so nothing near the
            // end of the page sits under it.
            .padding(.bottom, HomeBottomBar.floatingButtonClearance)
        }
        .scrollIndicators(.hidden)
        .background(Theme.Colors.background)
        .navigationTitle(Text("רישום מ-Apple Pay"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var intro: some View {
        Label {
            Text("משלמים בארנק, מקישים על ההתראה — והתנועה כבר ממתינה, מולאה מהתשלום.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "wave.3.right.circle.fill")
                .foregroundStyle(Theme.Colors.accent)
        }
        .font(Theme.Typography.bodySmall)
        .foregroundStyle(Theme.Colors.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// The one-time automation, step by step.
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

    /// In the Shortcuts app's own order. The English names in brackets are
    /// what a phone set to English shows; their spaces are no-break, so a
    /// name like "Run Immediately" never splits across lines in the RTL text.
    /// Step 4 matters: the list after "Next" also offers existing shortcuts,
    /// and the action only gets fields to connect when it's added to a new
    /// one (step 5).
    private static let stepTexts: [LocalizedStringKey] = [
        "פתחו את **קיצורים** ועברו ללשונית **אוטומציה**.",
        "הקישו **+** ובחרו **ארנק** (Wallet).",
        "תחת **כשאני מקיש/ה** (When\u{00A0}I\u{00A0}tap) בחרו את הכרטיסים, סמנו **הפעלה מיידית** (Run\u{00A0}Immediately) והקישו **הבא** (Next).",
        "בחרו **קיצור חדש** (New\u{00A0}Shortcut).",
        "הקישו **הוספת פעולה** (Add\u{00A0}Action), חפשו **רישום תשלום** והקישו עליה.",
        "בפעולה, הקישו על המילה **סכום** ובחרו **קלט קיצור** (Shortcut\u{00A0}Input). הקישו על **קלט קיצור** שנכנס ובחרו **סכום** (Amount).",
        "עשו אותו דבר ב**בית עסק** (בחרו Merchant) וב**כרטיס** (בחרו Card\u{00A0}or\u{00A0}Pass). הכרטיס לא חובה — הוא רק עוזר לבחור את החשבון.",
        "הקישו **סיום** (Done)."
    ]

    private var limits: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("כדאי לדעת")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            limitLine("creditcard", "עובד בתשלום בהצמדת הטלפון או השעון בקופה — לא בקניות אונליין או בתוך אפליקציות.")
            limitLine("building.columns", "אילו פרטים מגיעים תלוי בחברת האשראי. מה שלא הגיע יישאר ריק ותוכלו להשלים.")
            limitLine("lock.shield", "הכול נשאר במכשיר: הפרטים עוברים מהארנק לאפליקציה בלי אינטרנט ובלי חיבור לבנק, וההתראה היא התראה מקומית.")
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
