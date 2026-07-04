import WidgetKit
import SwiftUI

/// Home-screen shortcut for logging a transaction: tapping the widget
/// deep-links into the app via `oshrat://new-transaction`, which `HomeView`
/// answers by presenting `NewTransactionSheet`.
///
/// The widget is deliberately *static* — it shows no live data, so there is
/// no SwiftData / app-group plumbing here and the timeline never refreshes.
/// That keeps the extension a pure launcher and the app's "no data leaves
/// the device" story untouched.
struct NewTransactionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "NewTransactionWidget",
            provider: NewTransactionProvider()
        ) { _ in
            NewTransactionWidgetView()
        }
        .configurationDisplayName("תנועה חדשה")
        .description("קיצור דרך מהיר להוספת הכנסה או הוצאה")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Timeline

struct NewTransactionEntry: TimelineEntry {
    let date: Date
}

/// A do-nothing provider: one entry, `.never` policy. The widget's content
/// is constant, so WidgetKit never needs to wake the extension again.
/// Methods are `nonisolated` because WidgetKit calls them off the main
/// actor and the target defaults new types to `@MainActor`.
struct NewTransactionProvider: TimelineProvider {
    nonisolated func placeholder(in context: Context) -> NewTransactionEntry {
        NewTransactionEntry(date: .now)
    }

    nonisolated func getSnapshot(in context: Context, completion: @escaping (NewTransactionEntry) -> Void) {
        completion(NewTransactionEntry(date: .now))
    }

    nonisolated func getTimeline(in context: Context, completion: @escaping (Timeline<NewTransactionEntry>) -> Void) {
        completion(Timeline(entries: [NewTransactionEntry(date: .now)], policy: .never))
    }
}

// MARK: - View

/// The widget face: a large "+" in the brand accent over the widget
/// background, with the Hebrew label underneath. The whole face is one tap
/// target — `widgetURL` routes the tap into the app.
struct NewTransactionWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Brand accent, mirrored from `Theme.Colors.accent` — the extension
    /// doesn't compile the app's DesignSystem, so the two hex values are
    /// duplicated here on purpose. Keep in sync with `Theme.swift`.
    private var accent: Color {
        colorScheme == .dark ? Color(red: 0x2B / 255, green: 0xA0 / 255, blue: 0xC7 / 255)
                             : Color(red: 0x00 / 255, green: 0x66 / 255, blue: 0x99 / 255)
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(accent)
                    .frame(width: 52, height: 52)
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text("תנועה חדשה")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The app is pinned to Hebrew/RTL; the widget follows suit so the
        // label renders the same regardless of the device language.
        .environment(\.layoutDirection, .rightToLeft)
        .widgetURL(URL(string: "oshrat://new-transaction"))
        // Adaptive system background — white in light mode, dark in dark.
        .containerBackground(.background, for: .widget)
    }
}

#Preview(as: .systemSmall) {
    NewTransactionWidget()
} timeline: {
    NewTransactionEntry(date: .now)
}
