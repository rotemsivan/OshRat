import SwiftUI

/// The small "חובה" mark a required field shows when the user tried to save
/// without it.
///
/// Forms used to just grey out their save button (or the slide-to-confirm)
/// until every required field was filled, which left the user guessing
/// *which* field was missing. Now the save stays tappable: a tap with
/// something missing turns on the form's `showsMissingFields` flag, and every
/// empty required field puts this badge beside its label. Each badge goes
/// away by itself as its field is filled — it's driven by the field's own
/// emptiness, not by the attempt.
///
/// Shown only *after* an attempt, never up front: a fresh form full of red
/// marks reads as a telling-off before the user has done anything.
struct MissingFieldBadge: View {
    var body: some View {
        Label("חובה", systemImage: "exclamationmark.circle.fill")
            .labelStyle(MissingFieldLabelStyle())
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.expense)
            // Form section headers uppercase their text; Hebrew has no case,
            // but keep the badge out of it in case a Latin header ever wraps it.
            .textCase(nil)
            .fixedSize()
            .accessibilityLabel(Text("שדה חובה"))
    }
}

/// Icon and word close together — a `Label`'s default spacing reads as two
/// separate things at caption size.
private struct MissingFieldLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon
            configuration.title
        }
    }
}

extension View {
    /// Lays `MissingFieldBadge` beside this view — a section label, a header,
    /// or a text field — while `isMissing`. Under RTL the badge lands on the
    /// visual left, after the label as Hebrew reads it, or opposite a text
    /// field's placeholder where the two can't overlap.
    func missingFieldBadge(_ isMissing: Bool) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            self
            if isMissing {
                MissingFieldBadge()
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: isMissing)
    }
}

enum MissingFields {
    /// Tells the user a save was refused: a warning buzz, and for VoiceOver
    /// a spoken line — the badges are visual, and nothing else on screen
    /// says why the tap did nothing. One call so every form signals alike.
    @MainActor
    static func signalRefusedSave() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        AccessibilityNotification.Announcement(String(localized: "יש למלא את השדות המסומנים")).post()
    }
}
