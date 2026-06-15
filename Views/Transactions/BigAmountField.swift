import SwiftUI
import UIKit

/// Large, hero-sized decimal input used by the "תנועה חדשה" sheet.
///
/// Same plumbing as `DecimalField` (UIKit text field underneath, decimal
/// pad keyboard, bound `Decimal`), just sized large so the amount reads
/// as the headline of the sheet. The trailing slot is a compact wheel
/// picker over `supportedCurrencies` — sitting on the same row keeps
/// "amount + currency" reading as one editable unit, instead of a hero
/// number floating above a separate picker.
///
/// Kept as a sibling component instead of a configurable variant of
/// `DecimalField` so the small editor inputs elsewhere aren't affected
/// by changes here. They serve different roles in the UI.
struct BigAmountField: View {
    @Binding var value: Decimal
    @Binding var currencyCode: String
    /// Currency codes shown in the trailing wheel. Caller-supplied so
    /// the field doesn't bake in a list — different sheets may want a
    /// different set later.
    let supportedCurrencies: [String]

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            BigDecimalTextField(
                value: $value,
                placeholder: "0.00"
            )
            .frame(maxWidth: .infinity, alignment: .trailing)

            // Compact wheel — the default `.wheel` picker is taller than
            // a row, so we cap its height and clip the spillover. Width
            // is sized to comfortably fit 3-letter ISO codes (ILS/USD/
            // EUR/GBP) without truncation. The picker stays LTR because
            // currency codes are ASCII and read left-to-right.
            Picker("מטבע", selection: $currencyCode) {
                ForEach(supportedCurrencies, id: \.self) { code in
                    Text(code)
                        .font(Theme.Typography.body)
                        .tag(code)
                }
            }
            .labelsHidden()
            .pickerStyle(.wheel)
            .frame(width: 80, height: 80)
            .clipped()
            .environment(\.layoutDirection, .leftToRight)
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.Colors.separator, lineWidth: 1)
        )
    }
}

/// UIKit-backed text field — same reason as `DecimalField`: SwiftUI's
/// `TextField` has a live-typing glitch in this app's form context, and
/// sitting on `UITextField` directly avoids it.
private struct BigDecimalTextField: UIViewRepresentable {
    @Binding var value: Decimal
    let placeholder: String

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.keyboardType = .decimalPad
        field.borderStyle = .none
        field.font = UIFont(name: Theme.Fonts.bold, size: 36)
            ?? .boldSystemFont(ofSize: 36)
        field.textColor = .label
        field.adjustsFontSizeToFitWidth = true
        field.minimumFontSize = 18
        // Numbers stay LTR even in an RTL form — the caret and digits
        // line up where the user expects them.
        field.textAlignment = .right
        field.semanticContentAttribute = .forceLeftToRight

        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingDidEnd(_:)),
            for: .editingDidEnd
        )

        field.text = Self.format(value)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        guard !uiView.isFirstResponder else { return }
        let formatted = Self.format(value)
        if uiView.text != formatted {
            uiView.text = formatted
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    final class Coordinator: NSObject {
        let value: Binding<Decimal>

        init(value: Binding<Decimal>) {
            self.value = value
        }

        @objc func editingChanged(_ textField: UITextField) {
            let parsed = BigDecimalTextField.parse(textField.text ?? "")
            if parsed != value.wrappedValue {
                value.wrappedValue = parsed
            }
        }

        @objc func editingDidEnd(_ textField: UITextField) {
            textField.text = BigDecimalTextField.format(value.wrappedValue)
        }
    }

    private static func format(_ decimal: Decimal) -> String {
        decimal == 0 ? "" : decimal.formatted(.number.grouping(.never))
    }

    fileprivate static func parse(_ raw: String) -> Decimal {
        let normalised = raw
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        if let direct = Decimal(string: normalised) { return direct }
        let trimmed = normalised.hasSuffix(".")
            ? String(normalised.dropLast())
            : normalised
        return Decimal(string: trimmed) ?? 0
    }
}

#Preview {
    BigAmountField(
        value: .constant(0),
        currencyCode: .constant("ILS"),
        supportedCurrencies: ["ILS", "USD", "EUR"]
    )
    .padding()
    .background(Theme.Colors.background)
}
