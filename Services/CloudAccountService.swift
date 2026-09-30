import Foundation
import CloudKit

/// What the app asks iCloud directly, outside SwiftData's own sync: whether
/// the device is signed in (the Settings status row), and whether the user's
/// iCloud already holds data from another device (the welcome screen, so a
/// second device waits for it rather than being set up from scratch).
///
/// Every answer is best-effort. A failure — offline, signed out, a container
/// that isn't set up yet — reads as "no", and nothing ever waits on it for
/// long: the app works fully without iCloud.
@MainActor
enum CloudAccountService {

    enum Status {
        /// Signed in; the store syncs.
        case available
        /// No iCloud account on the device, or iCloud Drive/CloudKit off for
        /// the app: everything stays on the device.
        case unavailable
        /// Couldn't tell (e.g. offline right now).
        case unknown
    }

    static func status() async -> Status {
        guard let container else { return .unavailable }
        do {
            switch try await container.accountStatus() {
            case .available: return .available
            case .noAccount, .restricted: return .unavailable
            default: return .unknown
            }
        } catch {
            return .unknown
        }
    }

    /// Whether this iCloud account already holds a profile synced from
    /// another device.
    ///
    /// SwiftData mirrors the store into one zone of the private database
    /// (`com.apple.coredata.cloudkit.zone`), one record type per model
    /// (`CD_<Model>`). Reading that zone's change feed from the start needs
    /// no query index — a `CKQuery` would need one, which the mirrored schema
    /// doesn't declare. Any profile record means there's data to wait for; a
    /// long feed with none in its first page counts too, since the account is
    /// clearly in use.
    static func hasExistingData() async -> Bool {
        guard let container, await status() == .available else { return false }
        let zone = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
        do {
            let changes = try await container.privateCloudDatabase.recordZoneChanges(
                inZoneWith: zone,
                since: nil,
                desiredKeys: [],
                resultsLimit: 200
            )
            let hasProfile = changes.modificationResultsByID.values.contains { result in
                (try? result.get().record.recordType) == "CD_UserProfile"
            }
            return hasProfile || (changes.moreComing && !changes.modificationResultsByID.isEmpty)
        } catch {
            return false
        }
    }

    private static var container: CKContainer? {
        PersistentStore.cloudKitContainerID.map(CKContainer.init(identifier:))
    }
}
