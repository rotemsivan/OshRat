import SwiftUI

/// The big button at the bottom of the brand screens ("בוא נתחיל",
/// "לחשבון שלי"). A tap gives a small press bounce and a haptic, then waits
/// long enough for the spring to be seen before running `action`, which
/// usually cross-fades the whole screen away.
///
/// `isPressed` is owned by the caller so it can disable its other buttons
/// for the same beat (the welcome screen's "להתחיל מחדש").
struct HeroPrimaryButton: View {
    let title: LocalizedStringKey
    @Binding var isPressed: Bool
    let action: () -> Void

    init(_ title: LocalizedStringKey, isPressed: Binding<Bool>, action: @escaping () -> Void) {
        self.title = title
        self._isPressed = isPressed
        self.action = action
    }

    var body: some View {
        Button(action: press) {
            Text(title)
                // `amount` (bold 18, scaling with .title2) rather than the
                // section-title size: the button reads as the next step, not
                // as a second headline under the app name.
                .font(Theme.Typography.amount)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Theme.Colors.accent)
        .scaleEffect(isPressed ? 1.06 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.55), value: isPressed)
        .sensoryFeedback(.impact(weight: .medium), trigger: isPressed)
        .disabled(isPressed)
    }

    /// Two beats: bounce + haptic, then hand over. The 220 ms delay matches
    /// the spring's perceived peak so the user actually sees the squish.
    private func press() {
        isPressed = true
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            action()
        }
    }
}
