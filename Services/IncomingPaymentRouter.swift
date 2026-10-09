import Foundation
import Observation

/// Carries a card payment from `LogPaymentIntent` to the screen that shows it.
///
/// The intent runs in the background at the till — often with the phone
/// locked and the app not running, in which case it runs in the App Intents
/// extension rather than the app — so it can't present anything itself. It
/// parks the payment in `PaymentInbox` (the App Group) and posts a
/// notification (`PaymentNotification`); when the user opens the app,
/// `HomeView` picks the payment up as soon as it's on screen and walks the
/// line in `PaymentQueueSheet`.
///
/// Two kinds of waiting payment share the queue:
/// - **up next** — not yet seen; these come up by themselves (`pending`,
///   `take`, `takeAll`);
/// - **skipped** ("דילוג") — parked until the user asks for them again from
///   the transactions list (`requestReview`), which puts them back in line.
///
/// This object is the app's **observable view** of `PaymentInbox`: `queue`
/// mirrors the stored queue, every change goes through `PaymentInbox.update`
/// (which re-reads the disk first, since the extension may have appended
/// since), and a Darwin notification from either process reloads it. Either
/// kind of payment is deleted unlogged once it's older than
/// `PaymentPrefill.freshness` (a week).
@MainActor
@Observable
final class IncomingPaymentRouter {
    static let shared = IncomingPaymentRouter()

    /// Waiting payments, oldest first — a mirror of the stored queue. A
    /// queue, not one slot: a second payment while the first still waits (a
    /// split bill, a second purchase) used to overwrite it, and that purchase
    /// went unlogged without a word.
    private var queue: [PaymentPrefill]

    /// Bumped whenever there's a new reason to bring the line up — a payment
    /// arrived, or the user asked to review the skipped ones — so `HomeView`
    /// can end a snooze on it (a put-back payment alone doesn't). This launch
    /// only.
    private(set) var presentationRequests = 0

    /// The newest payment the automation delivered, kept after it's logged
    /// or dropped — what the setup screen's live check reads
    /// (`PaymentSetupCheckCard`).
    private(set) var lastReceived: PaymentPrefill?

    /// Every payment id this launch has mirrored. An id outside it is an
    /// arrival; a payment taken and put back is not, whichever path —
    /// `apply` or `reload` — happens to mirror it first.
    @ObservationIgnored private var seenIDs: Set<UUID> = []

    /// The payment `HomeView` will show next, if any: the oldest one not
    /// skipped.
    var pending: PaymentPrefill? { queue.first { !$0.isSkipped } }

    /// How many payments are up next behind the one on screen.
    var waitingCount: Int { queue.count(where: { !$0.isSkipped }) }

    /// Every payment still waiting to be logged, skipped ones included — the
    /// transactions list's "N תשלומים ממתינים".
    var totalWaitingCount: Int { queue.count }

    private init() {
        PaymentInbox.migrateFromAppDefaultsIfNeeded()
        queue = PaymentInbox.load().filter { $0.isFresh() }
        seenIDs = Set(queue.map(\.id))
        lastReceived = PaymentInbox.lastReceived()
        observeOtherProcess()
    }

    /// A payment delivered inside the app's own process — the demo hooks and
    /// tests. (The intent writes to `PaymentInbox` directly, since it may be
    /// running in the extension, where this object doesn't exist; the
    /// Darwin notification brings that payment here.)
    func receive(_ payment: PaymentPrefill) {
        PaymentInbox.append(payment)
        reload()
    }

    /// Hands over the oldest payment that's up next and removes it, dropping
    /// any expired ones on the way.
    func take(now: Date = .now) -> PaymentPrefill? {
        removeExpired(now: now)
        var taken: PaymentPrefill?
        apply { queue in
            guard let index = queue.firstIndex(where: { !$0.isSkipped }) else { return }
            taken = queue.remove(at: index)
        }
        return taken
    }

    /// Hands over every payment that's up next, oldest first, and removes
    /// them — for logging them all at once. Skipped ones stay parked. The
    /// ones that can't be logged that way go back with `putBack`.
    func takeAll(now: Date = .now) -> [PaymentPrefill] {
        removeExpired(now: now)
        var upNext: [PaymentPrefill] = []
        apply { queue in
            upNext = queue.filter { !$0.isSkipped }
            queue.removeAll { !$0.isSkipped }
        }
        return upNext
    }

    /// Returns payments to the front of the queue, in their order, so the
    /// next sheet is the oldest of them.
    func putBack(_ payments: [PaymentPrefill]) {
        guard !payments.isEmpty else { return }
        apply { $0.insert(contentsOf: payments, at: 0) }
    }

    /// Parks a payment for later ("דילוג"): it keeps waiting, but doesn't come
    /// up by itself again.
    func skip(_ payment: PaymentPrefill, now: Date = .now) {
        var parked = payment
        parked.skippedAt = now
        apply { $0.append(parked) }
    }

    /// The transactions list's "N ממתינים" row: every skipped payment back in
    /// line, and the line brought up.
    func requestReview() {
        removeExpired()
        apply { queue in
            for index in queue.indices { queue[index].skippedAt = nil }
        }
        presentationRequests += 1
    }

    /// Deletes payments that waited past `PaymentPrefill.freshness` and
    /// returns them, so their notifications can be taken down too.
    @discardableResult
    func removeExpired(now: Date = .now) -> [PaymentPrefill] {
        var expired: [PaymentPrefill] = []
        apply { queue in
            expired = queue.filter { !$0.isFresh(at: now) }
            if !expired.isEmpty { queue.removeAll { !$0.isFresh(at: now) } }
        }
        return expired
    }

    /// Picks up what the other process wrote — the extension saving a
    /// payment while the app is open, or in the background. A payment that
    /// wasn't here before counts as an arrival and ends a snooze.
    func reload() {
        mirror(PaymentInbox.load())
        let last = PaymentInbox.lastReceived()
        if last != lastReceived { lastReceived = last }
    }

    // MARK: - Private

    /// Every change: re-read, change, write back — then mirror what was
    /// written. Never a write of the copy in memory, which could erase a
    /// payment the extension appended since it was read.
    private func apply(_ change: (inout [PaymentPrefill]) -> Void) {
        mirror(PaymentInbox.update(change))
    }

    /// Shows the stored queue, ending a snooze if it holds a payment this
    /// launch hasn't seen.
    private func mirror(_ stored: [PaymentPrefill]) {
        let ids = stored.map(\.id)
        if ids.contains(where: { !seenIDs.contains($0) }) {
            seenIDs.formUnion(ids)
            presentationRequests += 1
        }
        if stored != queue { queue = stored }
    }

    /// Reloads whenever either process changes the stored queue. The C
    /// callback can't capture anything, so it reaches the shared router.
    private func observeOtherProcess() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),  // never removed: the router lives as long as the app
            { _, _, _, _, _ in
                Task { @MainActor in IncomingPaymentRouter.shared.reload() }
            },
            PaymentInbox.changed as CFString,
            nil,
            .deliverImmediately
        )
    }
}
