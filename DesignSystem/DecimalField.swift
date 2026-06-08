import SwiftUI
import UIKit

/// A `Decimal`-bound text input.
///
/// Implemented as a `UIViewRepresentable` around `UITextField` rather
/// than a SwiftUI `TextField`. We tried several SwiftUI variants and
/// they all reproduced a live-typing rendering bug in this app's
/// context — typed characters didn't appear until the next layout
/// pass (the user had to press backspace to "force" the render).
/// Sitting directly on top of `UITextField` removes SwiftUI's text
/// editing layer from the equation: every keystroke shows immediately,
/// the way it does in any other UIKit form.
///
/// The bound `Decimal` is updated live via the `.editingChanged`
/// target-action, and the visible text is re-canonicalised on
/// editing-end so stray formatting (e.g. trailing ".") is cleaned up.
struct DecimalField: UIViewRepresentable {
    let placeholder: String
    @Binding var value: Decimal

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.keyboardType = .decimalPad
        field.borderStyle = .none
        field.font = UIFont(name: Theme.Fonts.regular, size: 14)
            ?? .systemFont(ofSize: 14)
        field.textColor = .label
        // Numbers are inherently left-to-right. The surrounding form
        // is RTL Hebrew, but forcing the field itself to LTR keeps the
        // caret and typed digits anchored to the leading edge of the
        // field (the left), where the user expects them.
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
        // Don't clobber in-flight typing. Only push the bound value
        // back into the field when the user isn't actively editing it
        // (e.g. the parent loaded a different draft into the editor).
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
            let parsed = DecimalField.parse(textField.text ?? "")
            if parsed != value.wrappedValue {
                value.wrappedValue = parsed
            }
        }

        @objc func editingDidEnd(_ textField: UITextField) {
            // Canonicalise on blur — "5." becomes "5", " 5 " becomes
            // "5". The user keeps whatever they typed while editing.
            textField.text = DecimalField.format(value.wrappedValue)
        }
    }

    // MARK: - Decimal <-> String

    /// Render `0` as the empty string so the placeholder stays
    /// visible; otherwise use a plain numeric form with no grouping
    /// separators (the surrounding form supplies context like the
    /// currency picker).
    private static func format(_ decimal: Decimal) -> String {
        decimal == 0 ? "" : decimal.formatted(.number.grouping(.never))
    }

    /// Tolerate both "." and "," as decimal separators and ignore any
    /// other character. Also accepts a trailing "." while the user is
    /// mid-type, treating it as the integer part.
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
