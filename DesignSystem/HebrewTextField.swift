import SwiftUI
import UIKit

// MARK: - UIKit subclasses

/// `UITextField` subclass that hints to iOS that the Hebrew input mode
/// should be the default when this field becomes first responder.
///
/// Apple doesn't expose a SwiftUI API for setting the keyboard language
/// — the canonical workaround is to override `textInputMode` on a
/// UIKit field, which iOS reads when picking the keyboard. If the
/// user hasn't installed the Hebrew keyboard we fall back to the
/// system default rather than forcing a broken state.
final class HebrewUITextField: UITextField {
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first(where: {
            ($0.primaryLanguage ?? "").hasPrefix("he")
        }) ?? super.textInputMode
    }
}

/// Multi-line counterpart to `HebrewUITextField`. Same trick — the
/// `textInputMode` override is what biases the system keyboard.
final class HebrewUITextView: UITextView {
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first(where: {
            ($0.primaryLanguage ?? "").hasPrefix("he")
        }) ?? super.textInputMode
    }
}

// MARK: - SwiftUI single-line wrapper

/// Drop-in replacement for SwiftUI's `TextField` when the expected
/// content is Hebrew. The keyboard defaults to Hebrew (if installed),
/// text + caret + placeholder are right-aligned, and the underlying
/// field is set to `forceRightToLeft` so the cursor sits on the right
/// edge from the first tap.
struct HebrewTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var submitLabel: UIReturnKeyType
    var textContentType: UITextContentType?
    var autocapitalizationType: UITextAutocapitalizationType
    var autocorrectionType: UITextAutocorrectionType

    init(
        _ placeholder: String,
        text: Binding<String>,
        submitLabel: UIReturnKeyType = .default,
        textContentType: UITextContentType? = nil,
        autocapitalizationType: UITextAutocapitalizationType = .sentences,
        autocorrectionType: UITextAutocorrectionType = .default
    ) {
        self.placeholder = placeholder
        self._text = text
        self.submitLabel = submitLabel
        self.textContentType = textContentType
        self.autocapitalizationType = autocapitalizationType
        self.autocorrectionType = autocorrectionType
    }

    func makeUIView(context: Context) -> HebrewUITextField {
        let field = HebrewUITextField()
        field.placeholder = placeholder
        field.borderStyle = .none
        field.font = UIFont(name: Theme.Fonts.regular, size: 14)
            ?? .systemFont(ofSize: 14)
        field.textColor = .label
        // Right-align text + caret so Hebrew flows from the right and
        // the placeholder doesn't appear stranded on the left.
        field.textAlignment = .right
        field.semanticContentAttribute = .forceRightToLeft
        field.returnKeyType = submitLabel
        field.textContentType = textContentType
        field.autocapitalizationType = autocapitalizationType
        field.autocorrectionType = autocorrectionType
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        field.text = text
        // Hug horizontally so the field stretches to fill its container
        // (matches how SwiftUI's TextField behaves in a Form row).
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ uiView: HebrewUITextField, context: Context) {
        // Only push external changes when the user isn't actively typing
        // — overwriting the field mid-keystroke would erase the caret.
        guard !uiView.isFirstResponder else { return }
        if uiView.text != text {
            uiView.text = text
        }
        if uiView.placeholder != placeholder {
            uiView.placeholder = placeholder
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject {
        let text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        @objc func editingChanged(_ textField: UITextField) {
            text.wrappedValue = textField.text ?? ""
        }
    }
}

// MARK: - SwiftUI multi-line wrapper

/// Multi-line text input with the Hebrew-default keyboard. The
/// placeholder is rendered as an overlay because `UITextView` doesn't
/// expose one natively. The wrapper grows with content (no scroll
/// inside) and clamps to `minHeight` so empty rows still look like
/// editable boxes.
struct HebrewTextEditor: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat

    init(_ placeholder: String, text: Binding<String>, minHeight: CGFloat = 80) {
        self.placeholder = placeholder
        self._text = text
        self.minHeight = minHeight
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HebrewTextEditorRepresentable(text: $text)
                .frame(minHeight: minHeight)

            // Placeholder sits behind the text view; pinned to the top-
            // trailing corner so it lines up with the caret in RTL.
            // `.allowsHitTesting(false)` so taps fall through to the
            // text view rather than getting eaten by the overlay.
            if text.isEmpty {
                Text(placeholder)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Color(uiColor: .placeholderText))
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct HebrewTextEditorRepresentable: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> HebrewUITextView {
        let view = HebrewUITextView()
        view.font = UIFont(name: Theme.Fonts.regular, size: 14)
            ?? .systemFont(ofSize: 14)
        view.textColor = .label
        view.textAlignment = .right
        view.semanticContentAttribute = .forceRightToLeft
        view.backgroundColor = .clear
        // Disable internal scrolling so the view grows with its content
        // and its intrinsic content size feeds back to SwiftUI.
        view.isScrollEnabled = false
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.delegate = context.coordinator
        view.text = text
        return view
    }

    func updateUIView(_ uiView: HebrewUITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }
    }
}

#Preview {
    @Previewable @State var single = ""
    @Previewable @State var multi = ""
    return VStack(spacing: 16) {
        HebrewTextField("שם", text: $single)
            .padding()
            .background(Color.gray.opacity(0.1))
        HebrewTextEditor("פרטים נוספים", text: $multi)
            .padding()
            .background(Color.gray.opacity(0.1))
    }
    .padding()
}
