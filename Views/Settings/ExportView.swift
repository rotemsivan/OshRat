import SwiftUI
import SwiftData
import UIKit

/// "ייצוא נתונים" — pushed from Settings → ניהול.
///
/// Pick a window and a format, tap ייצוא, and the file comes up in the share
/// sheet (Files, Mail, WhatsApp, AirDrop…). Excel carries the transactions
/// plus the summary sheets, dressed like the app; CSV is the transactions
/// alone, for other tools. Building and encoding is `ExportService`'s.
struct ExportView: View {
    @Environment(\.modelContext) private var modelContext

    /// Its own filters, used only for their date window — so the presets,
    /// the custom range and its description work exactly as in the list's
    /// filter sheet. Starts at "everything".
    @State private var filters = TransactionFilters()
    @State private var format: ExportService.Format = .excel
    @State private var isExporting = false
    @State private var exportedFile: ExportedFile?
    @State private var failed = false

    var body: some View {
        Form {
            rangeSection
            formatSection
            exportSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .tint(Theme.Colors.accent)
        .contentMargins(.bottom, HomeBottomBar.floatingButtonClearance, for: .scrollContent)
        .navigationTitle(Text("ייצוא נתונים"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportedFile) { file in
            ActivityView(items: [file.url])
                .ignoresSafeArea()
        }
        .alert("לא הצלחנו ליצור את הקובץ", isPresented: $failed) {
            Button("אישור", role: .cancel) {}
        }
    }

    private var rangeSection: some View {
        Section {
            DatePresetGrid(selection: filters.range, onSelect: select)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: Theme.Spacing.xs, leading: 0, bottom: Theme.Spacing.xs, trailing: 0))

            if filters.range == .custom {
                DatePicker("מתאריך", selection: $filters.customStart, in: ...Date.now, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "he_IL"))
                DatePicker("עד תאריך", selection: $filters.customEnd, in: filters.customStart...Date.now, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "he_IL"))
            }
        } header: {
            Text("טווח")
        } footer: {
            if filters.range != .custom, let description = filters.rangeDescription() {
                Text(description)
            }
        }
    }

    private var formatSection: some View {
        Section {
            Picker("פורמט", selection: $format) {
                Text("Excel").tag(ExportService.Format.excel)
                Text("CSV").tag(ExportService.Format.csv)
            }
            .pickerStyle(.segmented)
        } header: {
            HStack(spacing: Theme.Spacing.xs) {
                Text("פורמט")
                InfoButton("Excel כולל את התנועות ודפי סיכום: סקירה, סיכום חודשי, קטגוריות, תקציב מול ביצוע וחשבונות. CSV כולל את התנועות בלבד, לשימוש בתוכנות אחרות.")
            }
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                Task { await export() }
            } label: {
                HStack {
                    Label("ייצוא", systemImage: "square.and.arrow.up")
                    Spacer()
                    if isExporting { ProgressView() }
                }
            }
            .disabled(isExporting)
        } footer: {
            Text(countText)
        }
    }

    /// "312 תנועות" — what the file will hold.
    private var countText: String {
        let count = ExportService.transactionCount(in: filters.interval(), context: modelContext)
        return count == 1 ? "תנועה אחת" : "\(count.formatted()) תנועות"
    }

    private func select(_ preset: DateRangeFilter) {
        if preset == .custom {
            filters.beginCustomRange()
        } else {
            filters.range = preset
        }
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let url = try await ExportService.export(format, interval: filters.interval(), context: modelContext)
            exportedFile = ExportedFile(url: url)
        } catch {
            failed = true
        }
    }
}

/// The written file, as a sheet item.
private struct ExportedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The system share sheet. `ShareLink` can't be opened from code, and the
/// file only exists once the export has finished, so this wraps
/// `UIActivityViewController` instead.
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        ExportView()
    }
    .modelContainer(for: OshRatSchema.models, inMemory: true)
    .environment(\.layoutDirection, .rightToLeft)
}
