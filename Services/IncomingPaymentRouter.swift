import Foundation
import Observation

/// Carries a card payment from `LogPaymentIntent` to the screen that shows it.
///
/// The intent runs in the background at the till — often with the phone
/// locked and the app not running — so it can't present anything itself. It
/// parks the payment here and posts a notification (`PaymentNotifier`); when
/// the user opens the app, `HomeView` picks the payment up as soon as it's on
/// screen and walks the line in `PaymentQueueSheet`.
///
/// Two kinds of waiting payment share the queue:
/// - **up next** — not yet seen; these come up by themselves (`pending`,
///   `take`, `takeAll`);
/// - **skipped** ("דילוג") — parked until the user asks for them again from
///   the transactions list (`requestReview`), which puts them back in line.
///
/// The queue is **kept on disk** (`UserDefaults`), because the process that
/// ran the intent may well be gone by the time the notification is tapped.
/// Either kind is deleted unlogged once it's older than
/// `PaymentPrefill.freshness` (a week).
@MainActor
@Observable
final class IncomingPaymentRouter {
    static let shared = IncomingPaymentRouter()

    private static let storageKey = "pendingPayments"
    private static let lastReceivedKey = "lastReceivedPayment"

    /// Waiting payments, oldest first. A queue, not one slot: a second
    /// payment while the first still waits (a split bill, a second purchase)
    /// used to overwrite it, and that purchase went unlogged without a word.
    private var queue: [PaymentPrefill] {
        didSet { save() }
    }

    /// Bumped whenever there's a new reason to bring the line up — a payment
    /// arrived, or the user asked to review the skipped ones — so `HomeView`
    /// can end a snooze on it (a put-back payment alone doesn't). This launch
    /// only.
    private(set) var presentationRequests = 0

    /// The newest payment the automation delivered, kept after it's logged
    /// or dropped — what the setup screen's live check reads
    /// (`PaymentSetupCheckCard`). On disk, like the queue, since the action
    /// usually runs in a launch of its own.
    private(set) var lastReceived: PaymentPrefill? {
        didSet {
            let data = lastReceived.flatMap { try? JSONEncoder().encode($0) }
            UserDefaults.standard.set(data, forKey: Self.lastReceivedKey)
        }
    }

    /// The payment `HomeView` will show next, if any: the oldest one not
    /// skipped.
    var pending: PaymentPrefill? { queue.first { !$0.isSkipped } }

    /// How many payments are up next behind the one on screen.
    var waitingCount: Int { queue.count(where: { !$0.isSkipped }) }

    /// Every payment still waiting to be logged, skipped ones included — the
    /// transactions list's "N תשלומים ממתינים".
    var totalWaitingCount: Int { queue.count }

    private init() {
        queue = Self.load().filter { $0.isFresh() }
        lastReceived = Self.loadLastReceived()
    }

    func receive(_ payment: PaymentPrefill) {
        queue.append(payment)
        lastReceived = payment
        presentationRequests += 1
    }

    /// Hands over the oldest payment that's up next and removes it, dropping
    /// any expired ones on the way.
    func take(now: Date = .now) -> PaymentPrefill? {
        removeExpired(now: now)
        guard let index = queue.firstIndex(where: { !$0.isSkipped }) else { return nil }
        return queue.remove(at: index)
    }

    /// Hands over every payment that's up next, oldest first, and removes
    /// them — for logging them all at once. Skipped ones stay parked. The
    /// ones that can't be logged that way go back with `putBack`.
    func takeAll(now: Date = .now) -> [PaymentPrefill] {
        removeExpired(now: now)
        let upNext = queue.filter { !$0.isSkipped }
        queue.removeAll { !$0.isSkipped }
        return upNext
    }

    /// Returns payments to the front of the queue, in their order, so the
    /// next sheet is the oldest of them.
    func putBack(_ payments: [PaymentPrefill]) {
        guard !payments.isEmpty else { return }
        queue.insert(contentsOf: payments, at: 0)
    }

    /// Parks a payment for later ("דילוג"): it keeps waiting, but doesn't come
    /// up by itself again.
    func skip(_ payment: PaymentPrefill, now: Date = .now) {
        var parked = payment
        parked.skippedAt = now
        queue.append(parked)
    }

    /// The transactions list's "N ממתינים" row: every skipped payment back in
    /// line, and the line brought up.
    func requestReview() {
        removeExpired()
        for index in queue.indices { queue[index].skippedAt = nil }
        presentationRequests += 1
    }

    /// Deletes payments that waited past `PaymentPrefill.freshness` and
    /// returns them, so their notifications can be taken down too.
    @discardableResult
    func removeExpired(now: Date = .now) -> [PaymentPrefill] {
        let expired = queue.filter { !$0.isFresh(at: now) }
        if !expired.isEmpty { queue.removeAll { !$0.isFresh(at: now) } }
        return expired
    }

    /// Picks up payments another process wrote since this one loaded — the
    /// intent can run in a background launch of the app while a foreground
    /// copy of this object already exists.
    func reload() {
        let stored = Self.load()
        if stored != queue { queue = stored }
        let last = Self.loadLastReceived()
        if last != lastReceived { lastReceived = last }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func loadLastReceived() -> PaymentPrefill? {
        guard let data = UserDefaults.standard.data(forKey: lastReceivedKey) else { return nil }
        return try? JSONDecoder().decode(PaymentPrefill.self, from: data)
    }

    private static func load() -> [PaymentPrefill] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let payments = try? JSONDecoder().decode([PaymentPrefill].self, from: data)
        else { return [] }
        return payments
    }
}
