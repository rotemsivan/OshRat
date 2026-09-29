import Foundation
import SwiftData

/// The store's schema as it stands today, as the first versioned snapshot.
///
/// Until now the container was built from a bare list of models, which gives
/// SwiftData nothing to migrate *from*: a model change it can't handle on its
/// own (CLAUDE.md records a Codable enum attribute trapping this way) would
/// simply fail to open the store. With a versioned baseline, the next such
/// change becomes a `SchemaV2` plus a `MigrationStage` in
/// `OshRatMigrationPlan`.
///
/// When that day comes: V1 must keep describing the models *as they are now*,
/// so copy today's `@Model` classes into this enum (as nested types) before
/// changing the live ones, and point `models` at the copies.
enum OshRatSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            UserProfile.self, Account.self, Holding.self, Category.self,
            Transaction.self, TransactionAttachment.self, BudgetItem.self,
            Goal.self, FXRateSnapshot.self, UserProgress.self,
            DepositTranche.self, MascotConfig.self,
        ]
    }
}

/// Every schema version, oldest first, and the steps between them. Empty
/// while there is only one version.
enum OshRatMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [OshRatSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// Opens the on-device database, and keeps the app alive when it can't.
///
/// A failed open used to be a `fatalError`, which on a phone means the app
/// crashes on every launch with the user's hand-entered data locked inside
/// and no way to reach it until a fixed build ships. Now the failure is a
/// state: `OshRatApp` shows `StoreRecoveryView`, which can retry, hand the
/// user a copy of the files, or set them aside and start fresh. Nothing on
/// this path ever deletes the store.
@MainActor
@Observable
final class PersistentStore {
    enum State {
        case ready(ModelContainer)
        /// The error's description, shown under "פרטים טכניים".
        case failed(String)
    }

    private(set) var state: State

    init() {
        state = Self.open()
    }

    /// Explicitly local. The default configuration's `cloudKitDatabase` is
    /// `.automatic`, so adding any iCloud entitlement later would silently
    /// start mirroring the whole store; sync should be switched on here, on
    /// purpose (see *Planned* in CLAUDE.md). The name is the default one, so
    /// this is the same `default.store` file the app has always used.
    static let configuration = ModelConfiguration(
        schema: Schema(versionedSchema: OshRatSchemaV1.self),
        cloudKitDatabase: .none
    )

    func retry() {
        state = Self.open()
    }

    /// The files that make up the store (the database and its journal), for
    /// the "save a copy" share sheet. External blobs (attachments) live in a
    /// hidden folder beside them and are left out: a share sheet can't carry
    /// a folder, and the database is what matters for a rescue.
    var storeFiles: [URL] {
        let url = Self.configuration.url
        return [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Moves the unreadable store into `Application Support/Recovered Stores/<date>`
    /// — moved, never deleted, so a later build can still read it — then
    /// opens a fresh, empty one.
    func startFresh() throws {
        let fm = FileManager.default
        let storeURL = Self.configuration.url
        let directory = storeURL.deletingLastPathComponent()
        let base = storeURL.deletingPathExtension().lastPathComponent  // "default"

        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let backup = directory
            .appendingPathComponent("Recovered Stores", isDirectory: true)
            .appendingPathComponent(stamp, isDirectory: true)
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)

        // default.store, default.store-wal, default.store-shm and the
        // attachments folder .default_SUPPORT.
        for name in try fm.contentsOfDirectory(atPath: directory.path)
        where name.hasPrefix(storeURL.lastPathComponent) || name == ".\(base)_SUPPORT" {
            try fm.moveItem(at: directory.appendingPathComponent(name),
                            to: backup.appendingPathComponent(name))
        }
        retry()
    }

    private static func open() -> State {
        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: OshRatSchemaV1.self),
                migrationPlan: OshRatMigrationPlan.self,
                configurations: configuration
            )
            // Clean up any duplicate category rows left over from earlier
            // dev resets BEFORE topping up the default set — otherwise
            // the idempotent seed would see "name already present" and
            // skip while a duplicate still lurked in the database.
            SeedData.dedupeCategoriesIfNeeded(in: container.mainContext)
            // Now safe to top up. Idempotent — renames legacy defaults in
            // place and adds only the defaults the store doesn't have, so it
            // runs every launch without growing the table.
            SeedData.seedDefaultCategoriesIfNeeded(in: container.mainContext)
            return .ready(container)
        } catch {
            return .failed(String(describing: error))
        }
    }
}
