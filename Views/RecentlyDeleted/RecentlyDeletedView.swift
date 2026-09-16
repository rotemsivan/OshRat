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
///
/// **Rows hold value snapshots, never the model objects** — see `DeletedItem`
/// for why that matters on this screen specifically.
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

    /// The item awaiting a "delete permanently" confirmation, held as an
    /// **identifier** rather than the model object — see `PendingPurge`.
    @State private var pendingPurge: PendingPurge?

    var body: some View {
        NavigationStack {
            Group {
                if accountItems.isEmpty && transactionItems.isEmpty {
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
            if !accountItems.isEmpty {
                Section {
                    ForEach(accountItems) { item in
                        DeletedItemRow(item: item)
                            .listRowBackground(Theme.Colors.surface)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                swipeButtons(for: item, kind: .account)
                            }
                    }
                } header: {
                    Text("חשבונות")
                }
            }

            if !transactionItems.isEmpty {
                Section {
                    ForEach(transactionItems) { item in
                        DeletedItemRow(item: item)
                            .listRowBackground(Theme.Colors.surface)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                swipeButtons(for: item, kind: .transaction)
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

    /// Icon-only buttons, destructive first, accent tint on the safe one —
    /// the same swipe vocabulary as the transactions list, so a swipe means
    /// the same thing everywhere in the app.
    ///
    /// The one thing deliberately *not* copied from that list is
    /// `allowsFullSwipe`. There, a full swipe soft-deletes and the row is
    /// recoverable from this very screen; here the destructive action is the
    /// irreversible one, so it stays a deliberate tap rather than a gesture
    /// that can be completed by accident.
    @ViewBuilder
    private func swipeButtons(for item: DeletedItem, kind: PendingPurge.Kind) -> some View {
        Button(role: .destructive) {
            pendingPurge = PendingPurge(id: item.id, kind: kind)
        } label: {
            Image(systemName: "trash")
        } .tint(.red)
        .accessibilityLabel(Text("מחיקה לצמיתות"))
        
        Button {
            restore(id: item.id, kind: kind)
        } label: {
            Image(systemName: "arrow.uturn.backward")
        }
        .tint(Theme.Colors.accent)
        .accessibilityLabel(Text("שחזור"))
    }

    // MARK: - Snapshots

    /// Value snapshots of the soft-deleted accounts, rebuilt whenever the
    /// query changes.
    private var accountItems: [DeletedItem] {
        deletedAccounts.map { account in
            DeletedItem(
                id: account.persistentModelID,
                title: account.name.isEmpty ? "ללא שם" : account.name,
                caption: deletedCaption(account.deletedAt),
                amount: account.balance.formatted(.currency(code: account.currencyCode)),
                amountColor: Theme.Colors.textSecondary
            )
        }
    }

    private var transactionItems: [DeletedItem] {
        deletedTransactions.map(DeletedItem.init(transaction:))
    }

    // MARK: - Actions

    private func restore(id: PersistentIdentifier, kind: PendingPurge.Kind) {
        withAnimation {
            switch kind {
            case .account:
                guard let account = modelContext.model(for: id) as? Account else { return }
                TrashService.restore(account)
            case .transaction:
                guard let transaction = modelContext.model(for: id) as? Transaction else { return }
                TrashService.restore(transaction, fx: fxSnapshots.first)
            }
            try? modelContext.save()
        }
    }

    /// Resolve the pending identifier to a live model and hard-delete it.
    ///
    /// Resolving *here* rather than holding the object in `@State` is the
    /// point: once this runs, the model is invalid, and nothing in the view
    /// tree is left holding a reference to it.
    private func confirmPurge() {
        guard let pendingPurge else { return }
        // Clear the state first. The alert's `presenting:` value is re-read as
        // the view updates, and it must not still be pointing at something
        // that is about to stop existing.
        self.pendingPurge = nil

        withAnimation {
            switch pendingPurge.kind {
            case .account:
                guard let account = modelContext.model(for: pendingPurge.id) as? Account else { return }
                modelContext.delete(account)
            case .transaction:
                guard let transaction = modelContext.model(for: pendingPurge.id) as? Transaction else { return }
                modelContext.delete(transaction)
            }
            try? modelContext.save()
        }
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

/// What the confirmation alert is about to destroy.
///
/// Holds a `PersistentIdentifier`, **not** the model. `@State` outlives the
/// delete it triggers — SwiftUI re-reads the alert's `presenting:` value as
/// the view updates — and a hard-deleted SwiftData object traps the moment
/// anything touches it. An identifier is just a value, and
/// `ModelContext.model(for:)` turns it back into an object at the one moment
/// we actually need one.
private struct PendingPurge: Identifiable {
    enum Kind {
        case account
        case transaction
    }

    let id: PersistentIdentifier
    let kind: Kind
}

// MARK: - Row snapshot

/// Everything a deleted-item row draws, as plain values.
///
/// This screen is the only place in the app that **hard**-deletes, and that
/// makes it the only place where holding a `@Model` in a row is dangerous:
/// `modelContext.delete` invalidates the object immediately, while SwiftUI
/// keeps the outgoing row alive to animate it away. A row that read
/// `transaction.title` (or worse, walked `transaction.category?.name`) during
/// that animation would be reading an invalidated model, which traps with
/// "This model instance was invalidated because its backing data could no
/// longer be found in the store".
///
/// Everywhere else in the app deletion is a *soft* delete — it only sets
/// `deletedAt`, leaving the object perfectly valid — which is why rows there
/// can hold their models safely.
private struct DeletedItem: Identifiable {
    let id: PersistentIdentifier
    let title: String
    let caption: String
    let amount: String
    let amountColor: Color
}

extension DeletedItem {
    init(transaction: Transaction) {
        self.id = transaction.persistentModelID
        self.title = Self.title(for: transaction)
        self.caption = deletedCaption(transaction.deletedAt)
        self.amount = Self.formattedAmount(for: transaction)
        self.amountColor = Self.amountColor(for: transaction)
    }

    private static func title(for transaction: Transaction) -> String {
        let trimmed = transaction.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if transaction.isTransfer { return "העברה" }
        return transaction.category?.name ?? "ללא שם"
    }

    /// Signed amount wrapped in an LTR isolate so the bidi-neutral sign
    /// stays on the visual left — same treatment as the transactions list.
    private static func formattedAmount(for transaction: Transaction) -> String {
        let base = transaction.amount.formatted(.currency(code: transaction.currencyCode))
        if transaction.isTransfer { return "\u{2066}\(base)\u{2069}" }
        let sign = transaction.kind == .income ? "+" : "-"
        return "\u{2066}\(sign)\(base)\u{2069}"
    }

    private static func amountColor(for transaction: Transaction) -> Color {
        if transaction.isTransfer { return Theme.Colors.accent }
        switch transaction.kind {
        case .income:  return Theme.Colors.income
        case .expense: return Theme.Colors.expense
        }
    }
}

// MARK: - Row

/// One deleted item: name on the leading edge with a "deleted N ago" caption,
/// amount trailing. Shared by both sections — an account and a transaction
/// differ only in the values the snapshot carries.
private struct DeletedItemRow: View {
    let item: DeletedItem

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(item.caption)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.sm)
            Text(item.amount)
                .font(Theme.Typography.amount)
                .foregroundStyle(item.amountColor)
                .monospacedDigit()
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
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
                Transaction.self, TransactionAttachment.self, BudgetItem.self,
                Goal.self, FXRateSnapshot.self, UserProgress.self
            ],
            inMemory: true
        )
}
