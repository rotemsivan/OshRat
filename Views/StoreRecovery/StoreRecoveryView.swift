import SwiftUI

/// Shown instead of the app when the database can't be opened (see
/// `PersistentStore`). The job is to keep the user's data safe and give them
/// a way forward, in that order: try again, save a copy of the files, or set
/// them aside and start over. Nothing here deletes anything.
struct StoreRecoveryView: View {
    let store: PersistentStore
    let details: String

    @State private var isConfirmingFreshStart = false
    @State private var freshStartError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.Colors.expense)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("לא הצלחנו לפתוח את הנתונים שלך")
                        .font(Theme.Typography.screenTitle)
                    Text("הנתונים לא נמחקו. כנראה שהגרסה הזו של האפליקציה לא מצליחה לקרוא אותם. אפשר לנסות שוב, לשמור עותק שלהם, או להתחיל מחדש — והנתונים הישנים יישמרו בצד.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                VStack(spacing: Theme.Spacing.sm) {
                    Button {
                        store.retry()
                    } label: {
                        Label("ניסיון חוזר", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    if !store.storeFiles.isEmpty {
                        ShareLink(items: store.storeFiles) {
                            Label("שמירת עותק של הנתונים", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(role: .destructive) {
                        isConfirmingFreshStart = true
                    } label: {
                        Label("התחלה מחדש", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.Colors.expense)
                }
                .controlSize(.large)
                .font(Theme.Typography.body)

                if let freshStartError {
                    Text(freshStartError)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.expense)
                }

                DisclosureGroup("פרטים טכניים") {
                    Text(details)
                        .font(.system(.caption, design: .monospaced))
                        .environment(\.layoutDirection, .leftToRight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.top, Theme.Spacing.sm)
                }
                .font(Theme.Typography.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .tint(Theme.Colors.accent)
        .confirmationDialog("להתחיל מחדש?", isPresented: $isConfirmingFreshStart, titleVisibility: .visible) {
            Button("התחלה מחדש", role: .destructive) {
                do {
                    try store.startFresh()
                } catch {
                    freshStartError = "לא הצלחנו להעביר את הנתונים הישנים הצידה: \(error.localizedDescription)"
                }
            }
        } message: {
            Text("העותק במכשיר יועבר לתיקייה נפרדת ולא יימחק. אם הטלפון מחובר ל-iCloud, הנתונים שנשמרו שם יחזרו לבד; אחרת האפליקציה תיפתח ריקה. כדאי לשמור עותק קודם.")
        }
    }
}
