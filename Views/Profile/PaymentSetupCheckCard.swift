import SwiftUI

/// "בדיקת ההגדרה" — whether the user's Wallet automation actually works,
/// read from the last payment it delivered.
///
/// Text instructions alone left people unsure whether they'd done step 5
/// right, and a mistake only showed up as an empty sheet days later. This
/// closes the loop: the card shows what the newest payment brought, field by
/// field, with the step to fix when something's missing
/// (`PaymentPrefill.setupVerdict`). **Test mode** is the same check with a
/// start line: tap "התחלת בדיקה", pay once, come back, and the card answers
/// with a haptic — waiting only on a payment newer than the tap, so an old
/// one can't pass the test.
///
/// The test payment is a real one, so it also comes up for logging as usual.
struct PaymentSetupCheckCard: View {
    private let router = IncomingPaymentRouter.shared

    /// When the running test began, as seconds since 1970; 0 = no test.
    /// `@AppStorage` because the user leaves the app to pay, and the app may
    /// well be gone by the time they come back.
    @AppStorage("applePaySetupTestStartedAt") private var testStartedAt: TimeInterval = 0

    /// The verdict of a test that finished while the card was up, for the
    /// haptic and the "תוצאת הבדיקה" heading. Reset when a test starts, so a
    /// second identical result still answers.
    @State private var testResult: PaymentPrefill.SetupVerdict?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if isWaiting {
                waiting
            } else if let last = router.lastReceived {
                result(for: last)
            } else {
                notYet
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(Theme.Colors.accent)
        .cardStyle()
        // The payment usually arrives while the app is in the background;
        // `ContentView` reloads the router on return, which lands here.
        .onChange(of: router.lastReceived?.id) { finishTestIfAnswered() }
        .sensoryFeedback(trigger: testResult) { _, verdict in
            verdict.map { $0 == .working ? .success : .warning }
        }
    }

    // MARK: - State

    private var testStart: Date? {
        testStartedAt > 0 ? Date(timeIntervalSince1970: testStartedAt) : nil
    }

    /// A test is running and no payment has arrived since it began.
    private var isWaiting: Bool {
        guard let testStart else { return false }
        return (router.lastReceived?.receivedAt ?? .distantPast) < testStart
    }

    private func startTest() {
        testResult = nil
        testStartedAt = Date.now.timeIntervalSince1970
    }

    private func cancelTest() {
        testStartedAt = 0
    }

    private func finishTestIfAnswered() {
        guard let testStart, let last = router.lastReceived, last.receivedAt >= testStart else { return }
        testStartedAt = 0
        testResult = last.setupVerdict
        AccessibilityNotification.Announcement(title(for: last.setupVerdict)).post()
    }

    // MARK: - States

    private var notYet: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            heading(Text("בדיקת ההגדרה"), symbol: "checklist", color: Theme.Colors.accent)
            Text("אחרי ההגדרה, התחילו בדיקה ושלמו פעם אחת בארנק — נראה מה הגיע מהאוטומציה ומה צריך לתקן.")
                .font(Theme.Typography.bodySmall)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            testButton(Text("התחלת בדיקה"))
        }
    }

    private var waiting: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                ProgressView()
                Text("ממתינים לתשלום")
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            Text("שלמו פעם אחת בארנק, בהצמדת הטלפון או השעון בקופה, וחזרו לכאן. התוצאה תופיע מיד, והתשלום עצמו ייפתח לרישום כרגיל.")
                .font(Theme.Typography.bodySmall)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("שילמתם ושום דבר לא הגיע? בדקו שבשלב 3 סומן **הפעלה מיידית**, ושהאוטומציה פעילה ברשימה באפליקציית קיצורים.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("ביטול הבדיקה", action: cancelTest)
                .font(Theme.Typography.bodySmall)
        }
    }

    private func result(for payment: PaymentPrefill) -> some View {
        let verdict = payment.setupVerdict
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            heading(Text(title(for: verdict)), symbol: symbol(for: verdict), color: color(for: verdict))
            // Which payment this is about: the test's, or simply the newest.
            Group {
                if testResult != nil {
                    Text("תוצאת הבדיקה")
                } else {
                    Text("לפי התשלום האחרון · \(Text(payment.receivedAt, format: .relative(presentation: .named)))")
                }
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(PaymentPrefill.SetupField.allCases, id: \.self) { field in
                    SetupFieldRow(field: field, payment: payment)
                }
            }
            .padding(.vertical, Theme.Spacing.xs)

            ForEach(Array(advice(for: payment).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(Theme.Typography.bodySmall)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            testButton(Text("בדיקה חוזרת"))
        }
    }

    // MARK: - Pieces

    private func heading(_ text: Text, symbol: String, color: Color) -> some View {
        Label {
            text
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(color)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func testButton(_ label: Text) -> some View {
        Button(action: startTest) {
            label
                .font(Theme.Typography.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    private func title(for verdict: PaymentPrefill.SetupVerdict) -> String {
        switch verdict {
        case .working: String(localized: "ההגדרה עובדת")
        case .missing: String(localized: "חסרים פרטים")
        case .empty:   String(localized: "התשלום הגיע בלי פרטים")
        }
    }

    private func symbol(for verdict: PaymentPrefill.SetupVerdict) -> String {
        switch verdict {
        case .working: "checkmark.circle.fill"
        case .missing: "exclamationmark.triangle.fill"
        case .empty:   "xmark.octagon.fill"
        }
    }

    private func color(for verdict: PaymentPrefill.SetupVerdict) -> Color {
        switch verdict {
        case .working: Theme.Colors.income
        case .missing: Theme.Colors.wants
        case .empty:   Theme.Colors.expense
        }
    }

    /// What to do about it, pointing at the guide's numbered steps
    /// (`ApplePaySetupView.stepTexts`: 3 is "Run Immediately", 5 the amount,
    /// 6 the merchant and card — keep these in step if the guide changes).
    private func advice(for payment: PaymentPrefill) -> [LocalizedStringKey] {
        switch payment.setupVerdict {
        case .empty:
            return ["האוטומציה רצה, אבל אף שדה בפעולה **רישום תשלום** לא מחובר לתשלום. חזרו לשלב 5 וחברו כל שדה לפרט שלו בקלט הקיצור."]
        case .missing(let fields):
            return fields.compactMap { field -> LocalizedStringKey? in
                switch field {
                case .amount:
                    if let raw = payment.rawAmount?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                        // Text arrived but isn't a number: almost always the
                        // field tied to the whole Shortcut Input.
                        return "בשדה הסכום הגיע ״\(raw)״, שאינו סכום. בשלב 5, הקישו על **קלט קיצור** שבשדה **סכום** ובחרו **סכום** (Amount)."
                    }
                    return "הסכום לא הגיע. בשלב 5, ודאו שבשדה **סכום** מופיע **קלט קיצור** ושנבחר בו **סכום** (Amount)."
                case .merchant:
                    return "בית העסק לא הגיע. בשלב 6, ודאו שבשדה **בית עסק** נבחר **בית עסק** (Merchant). יש חברות אשראי שלא שולחות אותו — אז פשוט משלימים ברישום."
                case .card:
                    return nil  // optional — never reported missing
                }
            }
        case .working:
            var lines: [LocalizedStringKey] = ["מעכשיו כל תשלום בארנק ישאיר התראה, והתנועה תחכה מולאה."]
            if !payment.arrived(.card) {
                lines.append("הכרטיס לא הגיע — זה לא חובה, הוא רק עוזר לבחור את החשבון (שלב 6).")
            }
            return lines
        }
    }
}

/// One field of the delivered payment: a tick or a cross, the field's name,
/// and exactly what the shortcut sent for it — the raw value is the clue
/// when a field is wired to the wrong thing.
private struct SetupFieldRow: View {
    let field: PaymentPrefill.SetupField
    let payment: PaymentPrefill

    private var arrived: Bool { payment.arrived(field) }

    private var label: LocalizedStringKey {
        switch field {
        case .amount:   "סכום"
        case .merchant: "בית עסק"
        case .card:     "כרטיס"
        }
    }

    /// What came through, as sent. The amount shows its parsed value when it
    /// read, so the user sees what will be logged.
    private var value: String? {
        switch field {
        case .amount:
            if let amount = payment.amount, amount > 0 {
                return amount.formatted(.currency(code: payment.currencyCode ?? "ILS").locale(Locale(identifier: "he_IL")))
            }
            return payment.rawAmount.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        case .merchant: return payment.trimmedMerchant
        case .card:     return payment.trimmedCardName
        }
    }

    /// The card is optional, so its absence is a neutral dash, not a cross.
    private var symbol: (name: String, color: Color) {
        if arrived { return ("checkmark.circle.fill", Theme.Colors.income) }
        if field == .card { return ("minus.circle", Theme.Colors.textSecondary) }
        return ("xmark.circle.fill", Theme.Colors.expense)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Image(systemName: symbol.name)
                .foregroundStyle(symbol.color)
                .accessibilityHidden(true)
            Text(label)
                .foregroundStyle(Theme.Colors.textSecondary)
            if let value {
                Text(verbatim: value)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            } else {
                Text("ריק")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .font(Theme.Typography.bodySmall)
        .accessibilityElement(children: .combine)
        .accessibilityValue(arrived ? Text("התקבל") : Text("לא התקבל"))
    }
}

#Preview {
    PaymentSetupCheckCard()
        .padding()
        .background(Theme.Colors.background)
        .environment(\.layoutDirection, .rightToLeft)
}
