import SwiftUI
import SwiftData

/// "Recently Deleted" — the recycle bin for soft-deleted accounts and
/// transactions. Reached from the assets card (accounts) and the
/// transactions toolbar (transactions); both open this same combined
/// screen.
///
/// Each row can be **restored** (un-hides it and, for a transaction,
/// re-applies its balance effect — see `TrashService.restore`) or
/// **permanently deleted** (a hard delete, gated behind a confirmation
/// since it's irreversible). Anything left here is purged automatically
/// after `TrashService.retention`; the dashboard runs that sweep on
/// appearance.
///
/// The view owns its own `@Query`s (filtering `deletedAt != nil`) rather
/// than taking the rows as parameters, so restoring/purging from here
/// updates the list live without the presenting screen having to refeed it.
struct RecentlyDeletedView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Account> { $0.deletedAt != nil }, sort: \Account.deletedAt, order: .reverse)
    private var deletedAccounts: [Account]
    @Query(filter: #Predicate<Transaction> { $0.deletedAt != nil }, sort: \Transaction.deletedAt, order: .reverse)
    private var deletedTransactions: [Transaction]
    /// Freshest FX snapshot first — restoring a cross-currency transaction
    /// re-applies its balance effect, which may need a rate to bridge the
    /// entry's currency and its account's.
    @Query(sort: \FXRateSnapshot.fetchedAt, order: .reverse) private var fxSnapshots: [FXRateSnapshot]

    /// The item awaiting a "delete permanently" confirmation. An enum
    /// because the two row types share one alert.
    @State private var pendingPurge: PendingPurge?

    var body: some View {
        NavigationStack {
            Group {
                if deletedAccounts.isEmpty && deletedTransactions.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Theme.Colors.background)
            .navigationTitle(Text("נמחקו לאחרונה"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סיום") { dismiss() }
                }
            }
        }
        .tint(Theme.Colors.accent)
        .alert(
            Text("מחיקה לצמיתות"),
            isPresented: purgeAlertBinding,
            presenting: pendingPurge
        ) { _ in
            Button("מחיקה לצמיתות", role: .destructive) { confirmPurge() }
            Button("ביטול", role: .cancel) {}
        } message: { _ in
            Text("הפעולה אינה הפיכה — הפריט יימחק לצמיתות ולא ניתן יהיה לשחזר אותו.")
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            if !deletedAccounts.isEmpty {
                Section {
                    ForEach(deletedAccounts) { account in
                        DeletedAccountRow(account: account)
                            .listRowBackground(Theme.Colors.surface)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                permanentDeleteButton(.account(account))
                                restoreButton { restore(account) }
                            }
                    }
                } header: {
                    Text("חשבונות")
                }
            }

            if !deletedTransactions.isEmpty {
                Section {
                    ForEach(deletedTransactions) { tx in
                        DeletedTransactionRow(transaction: tx)
                            .listRowBackground(Theme.Colors.surface)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                permanentDeleteButton(.transaction(tx))
                                restoreButton { restore(tx) }
                            }
                    }
                } header: {
                    Text("תנועות")
                }
            }

            Section {
                EmptyView()
            } footer: {
                Text("פריטים שנמחקו נמחקים אוטומטית לצמיתות אחרי 30 יום.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .font(Theme.Typography.body)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "אין פריטים שנמחקו לאחרונה",
            systemImage: "trash",
            description: Text("חשבונות ותנועות שתמחקו יופיעו כאן, וניתן יהיה לשחזר אותם תוך 30 יום.")
        )
    }

    // MARK: - Swipe buttons

    /// Restore is the safe action, so it gets the leading slot (closest to
    /// the swipe edge) and the accent tint. Non-destructive, no confirm.
    private func restoreButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("שחזור", systemImage: "arrow.uturn.backward")
        }
        .tint(Theme.Colors.accent)
    }

    /// Permanent delete is destructive and irreversible, so it routes
    /// through the confirmation alert rather than firing on the swipe.
    private func permanentDeleteButton(_ item: PendingPurge) -> some View {
        Button(role: .destructive) {
            pendingPurge = item
        } label: {
            Label("מחיקה לצמיתות", systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func restore(_ account: Account) {
        withAnimation {
            TrashService.restore(account)
            try? modelContext.save()
        }
    }

    private func restore(_ transaction: Transaction) {
        withAnimation {
            TrashService.restore(transaction, fx: fxSnapshots.first)
            try? modelContext.save()
        }
    }

    private func confirmPurge() {
        guard let pendingPurge else { return }
        withAnimation {
            switch pendingPurge {
            case .account(let account):         modelContext.delete(account)
            case .transaction(let transaction): modelContext.delete(transaction)
            }
            try? modelContext.save()
        }
        self.pendingPurge = nil
    }

    /// `.alert(presenting:)` wants a `Binding<Bool>`; bridge it through the
    /// optional pending item so dismissing clears it in one place.
    private var purgeAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingPurge != nil },
            set: { if !$0 { pendingPurge = nil } }
        )
    }
}

// MARK: - Pending purge

/// One alert serves both row types, so the item it's confirming is an
/// enum over the two.
private enum PendingPurge: Identifiable {
    case account(Account)
    case transaction(Transaction)

    var id: PersistentIdentifier {
        switch self {
        case .account(let account):         return account.persistentModelID
        case .transaction(let transaction): return transaction.persistentModelID
        }
    }
}

// MARK: - Rows

/// A soft-deleted account: name + type on the leading edge, its balance
/// (in its own currency) trailing, with a "deleted N ago" caption.
private struct DeletedAccountRow: View {
    let account: Account

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name.isEmpty ? "ללא שם" : account.name)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(deletedCaption(account.deletedAt))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.sm)
            Text(account.balance.formatted(.currency(code: account.currencyCode)))
                .font(Theme.Typography.amount)
                .foregroundStyle(Theme.Colors.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A soft-deleted transaction: title + original date on the leading edge,
/// the amount (coloured by kind, accent for a transfer) trailing, with a
/// "deleted N ago" caption.
private struct DeletedTransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(deletedCaption(transaction.deletedAt))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.sm)
            Text(formattedAmount)
                .font(Theme.Typography.amount)
                .foregroundStyle(amountColor)
                .monospacedDigit()
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        let trimmed = transaction.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if transaction.isTransfer { return "העברה" }
        return transaction.category?.name ?? "ללא שם"
    }

    /// Signed amount wrapped in an LTR isolate so the bidi-neutral sign
    /// stays on the visual left — same treatment as the transactions list.
    private var formattedAmount: String {
        let base = transaction.amount.formatted(.currency(code: transaction.currencyCode))
        if transaction.isTransfer { return "\u{2066}\(base)\u{2069}" }
        let sign = transaction.kind == .income ? "+" : "-"
        return "\u{2066}\(sign)\(base)\u{2069}"
    }

    private var amountColor: Color {
        if transaction.isTransfer { return Theme.Colors.accent }
        switch transaction.kind {
        case .income:  return Theme.Colors.income
        case .expense: return Theme.Colors.expense
        }
    }
}

// MARK: - Shared formatting

/// Hebrew relative-time formatter shared by both row types.
private let deletedRelativeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: "he_IL")
    formatter.unitsStyle = .full
    return formatter
}()

/// "נמחק <relative>", e.g. "נמחק לפני 3 ימים". `deletedAt` is always set
/// for rows in this screen, but guarded for safety.
private func deletedCaption(_ deletedAt: Date?) -> String {
    guard let deletedAt else { return "נמחק" }
    return "נמחק \(deletedRelativeFormatter.localizedString(for: deletedAt, relativeTo: .now))"
}

#Preview {
    RecentlyDeletedView()
        .modelContainer(
            for: [
                UserProfile.self, Account.self, Holding.self, Category.self,
                Transaction.self, TransactionAttachment.self, BudgetItem.self, Goal.self, FXRateSnapshot.self
            ],
            inMemory: true
        )
}
