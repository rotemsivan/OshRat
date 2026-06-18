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
    /// When true the trailing currency wheel is replaced by a static
    /// label. Used where the currency is fixed and must not change — e.g.
    /// editing a *persisted* account, whose stored balance, transaction
    /// history and running-balance snapshots are all denominated in it,
    /// with no sensible conversion to apply. Defaults to off so existing
    /// callers (the new-transaction sheet) keep the editable wheel.
    var isCurrencyLocked: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            BigDecimalTextField(
                value: $value,
                placeholder: "0.00"
            )
            .frame(maxWidth: .infinity, alignment: .trailing)

            if isCurrencyLocked {
                // Read-only currency: a static code instead of the wheel.
                // Same 80pt slot so the big number's width doesn't shift
                // between the editable and locked layouts.
                Text(currencyCode)
                    .font(Theme.Typography.amount)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .monospacedDigit()
                    .frame(width: 80)
                    .environment(\.layoutDirection, .leftToRight)
            } else {
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
///
/// Formats **as the user types**: the integer part gains thousands
/// separators and the fraction is capped at two digits on every
/// keystroke, while the caret is kept beside the same digit it was next
/// to (so an inserted separator doesn't make the cursor jump). An
/// in-progress fraction — a lone trailing "." or trailing zeros like
/// "12.50" — is preserved while editing, then snapped to a canonical
/// grouped form when editing ends. Separators are read off the current
/// locale so they match what the decimal-pad keyboard shows.
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

        field.text = Self.canonical(value)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        // Skip while the user is typing — the coordinator owns the text
        // then, and overwriting it would fight the caret logic.
        guard !uiView.isFirstResponder else { return }
        let formatted = Self.canonical(value)
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

        @objc func editingChanged(_ field: UITextField) {
            let old = field.text ?? ""
            // Anchor the caret by counting *significant* characters
            // (digits + the decimal separator) to its left. Grouping
            // separators we add or remove don't change this count, so the
            // caret lands beside the same digit after reformatting.
            let caret = field.offset(
                from: field.beginningOfDocument,
                to: field.selectedTextRange?.start ?? field.endOfDocument
            )
            let significantBefore = BigDecimalTextField.significantCount(in: old, utf16Prefix: caret)

            let result = BigDecimalTextField.liveFormat(old)
            field.text = result.text
            if value.wrappedValue != result.value {
                value.wrappedValue = result.value
            }

            let newOffset = BigDecimalTextField.utf16Offset(in: result.text, afterSignificant: significantBefore)
            if let pos = field.position(from: field.beginningOfDocument, offset: newOffset) {
                field.selectedTextRange = field.textRange(from: pos, to: pos)
            }
        }

        @objc func editingDidEnd(_ field: UITextField) {
            field.text = BigDecimalTextField.canonical(value.wrappedValue)
        }
    }

    // MARK: - Formatting helpers

    /// Locale-driven separators so the grouped/decimal display matches the
    /// glyphs the decimal-pad keyboard produces.
    private static let decimalSeparator = Locale.current.decimalSeparator ?? "."
    private static let groupingSeparator = Locale.current.groupingSeparator ?? ","

    private static let canonicalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    /// At-rest display (not mid-typing): grouped, up to two decimals, no
    /// trailing separator. Empty for zero so the placeholder shows through.
    static func canonical(_ decimal: Decimal) -> String {
        guard decimal != 0 else { return "" }
        return canonicalFormatter.string(from: decimal as NSDecimalNumber) ?? ""
    }

    /// Live, mid-typing reformat: grouped integer + the fraction exactly as
    /// far as the user has typed it. Returns the display text and the value
    /// it parses to.
    static func liveFormat(_ raw: String) -> (text: String, value: Decimal) {
        // Keep only digits and decimal separators — strips our grouping
        // characters and anything stray the keyboard might emit.
        let cleaned = raw.filter { $0.isNumber || String($0) == decimalSeparator }
        let hasDecimal = cleaned.contains(decimalSeparator)

        // Split on the first decimal separator; ignore any extra ones.
        let segments = cleaned.components(separatedBy: decimalSeparator)
        var intDigits = segments.first ?? ""
        let fractionDigits = hasDecimal
            ? String(segments.dropFirst().joined().filter(\.isNumber).prefix(2))
            : ""

        // Drop leading zeros, but keep a single "0".
        while intDigits.count > 1 && intDigits.first == "0" { intDigits.removeFirst() }

        var text = group(intDigits)
        if hasDecimal { text += decimalSeparator + fractionDigits }

        // Rebuild with a POSIX "." so `Decimal(string:)` parses regardless
        // of the locale separator. Empty integer with a fraction is "0.xx".
        let intForValue = intDigits.isEmpty ? "0" : intDigits
        let valueString = intForValue + (hasDecimal ? "." + fractionDigits : "")
        return (text, Decimal(string: valueString) ?? 0)
    }

    /// Number of digits + decimal separators within the first
    /// `utf16Prefix` UTF-16 units of `text` (used to anchor the caret).
    static func significantCount(in text: String, utf16Prefix: Int) -> Int {
        let ns = text as NSString
        let bound = max(0, min(utf16Prefix, ns.length))
        return ns.substring(to: bound).reduce(0) { count, character in
            count + (character.isNumber || String(character) == decimalSeparator ? 1 : 0)
        }
    }

    /// UTF-16 offset just past the `target`-th significant character — the
    /// caret position that keeps the cursor beside the same digit.
    static func utf16Offset(in text: String, afterSignificant target: Int) -> Int {
        guard target > 0 else { return 0 }
        var seen = 0
        var offset = 0
        for character in text {
            offset += String(character).utf16.count
            if character.isNumber || String(character) == decimalSeparator { seen += 1 }
            if seen == target { return offset }
        }
        return (text as NSString).length
    }

    /// Groups an all-digits string into threes using `groupingSeparator`.
    private static func group(_ digits: String) -> String {
        let count = digits.count
        guard count > 3 else { return digits }
        var out = ""
        for (index, character) in digits.enumerated() {
            if index != 0 && (count - index).isMultiple(of: 3) { out += groupingSeparator }
            out.append(character)
        }
        return out
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
