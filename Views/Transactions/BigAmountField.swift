import SwiftUI
import UIKit

/// Large, hero-sized decimal input used by the "תנועה חדשה" sheet.
///
/// Same plumbing as `DecimalField` (UIKit text field underneath, decimal
/// pad keyboard, bound `Decimal`), just sized large so the amount reads
/// as the headline of the sheet. The trailing currency code is rendered
/// inside the same row as a muted label, so a placeholder like
/// "0.00 ILS" appears as a single visual unit.
///
/// Kept as a sibling component instead of a configurable variant of
/// `DecimalField` so the small editor inputs elsewhere aren't affected
/// by changes here. They serve different roles in the UI.
struct BigAmountField: View {
    @Binding var value: Decimal
    let currencyCode: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            BigDecimalTextField(
                value: $value,
                placeholder: "0.00"
            )
            .frame(maxWidth: .infinity, alignment: .trailing)

            Text(currencyCode)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Colors.textSecondary)
                .monospacedDigit()
        }
        .padding(.vertical, Theme.Spacing.md)
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
    BigAmountField(value: .constant(0), currencyCode: "ILS")
        .padding()
        .background(Theme.Colors.background)
}
