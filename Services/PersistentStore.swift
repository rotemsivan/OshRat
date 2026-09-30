import Foundation
import SwiftData
import CoreData

/// Every model the app stores — the one list the container and every preview
/// are built from.
///
/// **Changes must be additive** (a new model, a new optional or defaulted
/// attribute, a new relationship): the store syncs through CloudKit, and a
/// CloudKit-mirrored store only supports lightweight migration, which
/// SwiftData performs by itself — it compares the model cached inside the
/// store with this one. So there is no versioned schema or migration plan: a
/// custom migration step couldn't sync anyway. (A staged plan existed briefly
/// — V1, then V2 adding `BudgetMonthCommitment` — and was dropped when the
/// inverse `Category.budgetItems` would have needed frozen copies of every
/// model; stores written under it open unchanged.) Never rename or remove a
/// stored property, never make an optional one required: CloudKit's schema,
/// once deployed to production, can only grow.
enum OshRatSchema {
    static var models: [any PersistentModel.Type] {
        [
            UserProfile.self, Account.self, Holding.self, Category.self,
            Transaction.self, TransactionAttachment.self, BudgetItem.self,
            Goal.self, FXRateSnapshot.self, UserProgress.self,
            DepositTranche.self, MascotConfig.self, BudgetMonthCommitment.self,
        ]
    }

    static var schema: Schema { Schema(models) }
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

    /// Synced to the user's **private** iCloud database, in this app variant's
    /// own container (`CLOUDKIT_CONTAINER`: `iCloud.com.oshrat.app` for the App
    /// Store app, `…app.dev` for the dev build, so the two never share data).
    /// Named explicitly rather than `.automatic`, which would pick whichever
    /// container the entitlements happen to list first.
    ///
    /// Signed out of iCloud, or offline, the store works exactly as before —
    /// local — and catches up when iCloud is back; nothing in the app waits
    /// for it. The name is the default one, so this is the same
    /// `default.store` file the app has always used, now mirrored.
    static let configuration = ModelConfiguration(
        schema: OshRatSchema.schema,
        cloudKitDatabase: cloudKitContainerID.map { .private($0) } ?? .none
    )

    /// This variant's CloudKit container, from Info.plist (`OshRatCloudKitContainer`
    /// ← the `CLOUDKIT_CONTAINER` build setting). `nil` only if the key is
    /// missing — then the store stays local rather than guessing.
    static var cloudKitContainerID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "OshRatCloudKitContainer") as? String,
              id.hasPrefix("iCloud.")
        else { return nil }
        return id
    }

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

    /// Creates this variant's CloudKit schema (record types and fields) in the
    /// container's **Development** environment, from the model.
    ///
    /// TestFlight and App Store builds talk to **Production**, which only has
    /// the schema someone deployed there from Development in the CloudKit
    /// Console — without that, sync silently does nothing. SwiftData creates
    /// schema lazily as records are first saved, which would miss any model
    /// the developer happened not to use; this creates all of it at once.
    ///
    /// Apple's documented pattern for SwiftData: a throwaway
    /// `NSPersistentCloudKitContainer` over the same model, on a separate
    /// scratch store so the real data is never touched. Run it by launching
    /// with `-initCloudKitSchema` from Xcode (a launch argument can't reach an
    /// installed App Store build), with the build configuration whose
    /// container should get the schema — Release for `iCloud.com.oshrat.app`
    /// — on a device signed into iCloud. The console says how it went.
    private static func initializeCloudKitSchema() {
        guard let containerID = cloudKitContainerID,
              let model = NSManagedObjectModel.makeManagedObjectModel(for: OshRatSchema.models)
        else {
            print("CloudKit schema: no container configured, or the model couldn't be built.")
            return
        }
        let scratch = URL.temporaryDirectory.appending(path: "cloudkit-schema.store")
        let description = NSPersistentStoreDescription(url: scratch)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerID)
        description.shouldAddStoreAsynchronously = false
        let container = NSPersistentCloudKitContainer(name: "OshRatSchema", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        do {
            if let loadError { throw loadError }
            try container.initializeCloudKitSchema()
            print("CloudKit schema: initialized in \(containerID) (Development). Deploy it to Production in the CloudKit Console.")
        } catch {
            print("CloudKit schema: failed — \(error)")
        }
        for store in container.persistentStoreCoordinator.persistentStores {
            try? container.persistentStoreCoordinator.remove(store)
        }
    }

    /// Moves the unreadable store into `Application Support/Recovered Stores/<date>`
    /// — moved, never deleted, so a later build can still read it — then
    /// opens a fresh one — empty, or refilled by iCloud sync from whatever the
    /// user's other devices (or this one, before) uploaded.
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
        if CommandLine.arguments.contains("-initCloudKitSchema") {
            initializeCloudKitSchema()
        }
        do {
            let container = try ModelContainer(for: OshRatSchema.schema, configurations: configuration)
            // Merge duplicate category rows and top up the defaults, then
            // fold together the one-per-user rows two synced devices may have
            // each created. Idempotent, so it runs every launch.
            SyncDeduplicator.run(in: container.mainContext)
            return .ready(container)
        } catch {
            return .failed(String(describing: error))
        }
    }
}
