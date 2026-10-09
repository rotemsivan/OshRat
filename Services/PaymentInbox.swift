import Foundation

/// Where waiting Apple Pay payments live on disk — in the **App Group**, the
/// one place both processes that handle them can reach.
///
/// `LogPaymentIntent` is compiled into the app *and* the App Intents
/// extension (`OshRatIntents`). The system runs it in the app when the app
/// is already running, and in the small extension process when it isn't —
/// the usual case at the till, and the one that used to fail when it meant
/// cold-launching the whole app. Whichever process runs it writes here, and
/// the app reads here (`IncomingPaymentRouter`).
///
/// **Two processes, one queue**, so every change re-reads the stored queue,
/// applies itself, and writes it back (`update`). Writing a copy held in
/// memory would erase a payment the other process appended meanwhile. And
/// each write rings a Darwin notification (`changed`), which the app
/// listens for, so a payment the extension saves while the app is open
/// shows up at once.
///
/// The group is per app variant, like everything else per-app
/// (`APP_GROUP` → `OshRatAppGroup`: `group.com.oshrat.app` /
/// `group.com.oshrat.app.dev`).
enum PaymentInbox {
    private static let queueKey = "pendingPayments"
    private static let lastReceivedKey = "lastReceivedPayment"

    /// This variant's App Group, from Info.plist. `nil` only if the key is
    /// missing.
    static let groupID: String? = {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "OshRatAppGroup") as? String,
              id.hasPrefix("group.")
        else { return nil }
        return id
    }()

    /// Whether this process can really reach the shared container. Without
    /// the entitlement `UserDefaults(suiteName:)` still hands back defaults
    /// — private to the process, which the other one never sees — so it's
    /// checked through the container instead.
    static var isShared: Bool {
        guard let groupID else { return false }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }

    /// The shared defaults, or this process's own when there's no group
    /// (the app then works exactly as it did before the extension).
    private static var defaults: UserDefaults {
        guard isShared, let groupID, let shared = UserDefaults(suiteName: groupID) else { return .standard }
        return shared
    }

    /// The Darwin notification every write posts. Darwin names are global
    /// across apps, so it carries the group: the dev and release apps
    /// installed side by side mustn't ping each other.
    static var changed: String { "\(groupID ?? "oshrat").payments-changed" }

    // MARK: Reading

    /// Waiting payments, oldest first.
    static func load() -> [PaymentPrefill] {
        guard let data = defaults.data(forKey: queueKey),
              let payments = try? JSONDecoder().decode([PaymentPrefill].self, from: data)
        else { return [] }
        return payments
    }

    /// The newest payment delivered, kept after it leaves the queue — the
    /// setup screen's live check.
    static func lastReceived() -> PaymentPrefill? {
        guard let data = defaults.data(forKey: lastReceivedKey) else { return nil }
        return try? JSONDecoder().decode(PaymentPrefill.self, from: data)
    }

    // MARK: Writing

    /// A payment the automation just delivered: queued at the back, and
    /// remembered as the last one received.
    static func append(_ payment: PaymentPrefill) {
        defaults.set(try? JSONEncoder().encode(payment), forKey: lastReceivedKey)
        update { $0.append(payment) }
    }

    /// Re-reads the queue, changes it, writes it back, and returns what it
    /// wrote — the one way to change it, see the type's note.
    @discardableResult
    static func update(_ change: (inout [PaymentPrefill]) -> Void) -> [PaymentPrefill] {
        var queue = load()
        change(&queue)
        if let data = try? JSONEncoder().encode(queue) {
            defaults.set(data, forKey: queueKey)
        }
        notifyChanged()
        return queue
    }

    private static func notifyChanged() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(changed as CFString), nil, nil, true
        )
    }

    // MARK: Moving in

    /// Brings payments saved before the App Group existed — in the app's own
    /// defaults — into the shared ones, once. Merged by id, so a payment the
    /// extension already wrote isn't lost or doubled.
    static func migrateFromAppDefaultsIfNeeded() {
        guard isShared else { return }
        let old = UserDefaults.standard
        if let data = old.data(forKey: queueKey),
           let stranded = try? JSONDecoder().decode([PaymentPrefill].self, from: data) {
            update { queue in
                let known = Set(queue.map(\.id))
                queue = (stranded.filter { !known.contains($0.id) } + queue)
                    .sorted { $0.receivedAt < $1.receivedAt }
            }
            old.removeObject(forKey: queueKey)
        }
        if let data = old.data(forKey: lastReceivedKey) {
            if defaults.data(forKey: lastReceivedKey) == nil {
                defaults.set(data, forKey: lastReceivedKey)
            }
            old.removeObject(forKey: lastReceivedKey)
        }
    }
}
