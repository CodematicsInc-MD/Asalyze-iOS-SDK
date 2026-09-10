import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

/// Observes StoreKit 2 transactions. On launch it first sweeps `Transaction.all` to BACKFILL the
/// user's past purchases (each stamped with its real Apple dates) — so a user who subscribed before
/// the SDK shipped still shows a complete timeline, exactly like RevenueCat/Adapty. It then watches
/// `Transaction.updates` for the app's lifetime. Every transaction carries Apple's `transactionId`, so
/// the backend can dedupe it against the App Store Server API pull. Local dedup avoids re-sending
/// history every launch.
final class StoreKitObserver {
    /// Guards every mutable field on this object.
    ///
    /// The sweeps below run on detached tasks while the Runtime is still WRITING to this object from
    /// another thread, so none of these fields could be plain `var`s. `environment` is the one that bit:
    /// Runtime sets it once `await AppTransaction.shared` returns — a storekitd round trip that can take
    /// seconds on a cold launch — while a sweep is already reading it for every transaction it emits.
    ///
    /// A `String` is not a word: reading one loads a buffer pointer AND retains that buffer, writing one
    /// stores a pointer AND releases the old buffer. With two sweeps reading (see `rescan`) and the
    /// Runtime writing, the same buffer can be released by parties that no longer agree on who owns it —
    /// an over-release, which frees memory that is still referenced. What crashes afterwards is whatever
    /// the allocator hands that memory to next, which is why the failure surfaced as a Swift Task
    /// resuming into a null function pointer rather than as anything to do with an environment string.
    ///
    /// Never call out (to `onTransaction`) while holding this: NSLock is not recursive.
    private let lock = NSLock()

    /// Called once per not-yet-sent verified transaction (past + live: initial buys, renewals, refunds).
    var onTransaction: ((ObservedTransaction) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onTransaction }
        set { lock.lock(); defer { lock.unlock() }; _onTransaction = newValue }
    }
    private var _onTransaction: ((ObservedTransaction) -> Void)?

    /// Resolved app environment (set by Runtime once AppTransaction resolves) — used for OS versions
    /// where a transaction doesn't expose its own `.environment`.
    var environment: String {
        get { lock.lock(); defer { lock.unlock() }; return _environment }
        set { lock.lock(); defer { lock.unlock() }; _environment = newValue }
    }
    private var _environment: String = SDKEnvironment.current.rawValue

    /// Ids already handed to `onTransaction` during THIS launch.
    ///
    /// `Storage.hasSentTransaction` cannot do this job alone: it is written only after the POST lands, a
    /// network round trip later, so two sweeps starting milliseconds apart both read "not sent" and both
    /// report the same purchase. This claims the id the moment it is emitted, so a transaction is emitted
    /// once no matter how many sweeps are walking `Transaction.all`.
    ///
    /// In memory, never persisted — a failed report must still replay from `Transaction.all` next launch.
    private var claimed: Set<String> = []

    /// Sweeps never overlap. `Transaction.all` walks the device's whole purchase history, so running two
    /// at once is the same work twice — and it was two concurrent readers that turned the unsynchronized
    /// `environment` above into a crash. A rescan arriving while one is running sets `pendingSweep`
    /// instead, and exactly one more runs when the current finishes, however many arrive meanwhile.
    ///
    /// Queued rather than dropped: a purchase completing mid-sweep may sit at a position the running
    /// sweep has already passed, so skipping could lose the very sale `rescan` exists to catch.
    private var sweeping = false
    private var pendingSweep = false

    /// Floor between two sweeps triggered by a foreground.
    ///
    /// `didBecomeActive` is not a purchase signal — it fires on every return to the app: after a phone
    /// call, the notification shade, Control Centre, an app switch. Walking the device's entire purchase
    /// history each time is work nobody asked for, on someone else's battery.
    ///
    /// A request inside the window is DELAYED, never dropped: dropping it would lose the sale that
    /// `rescan` exists to catch, since a purchase is exactly a foreground that follows a system sheet.
    /// Worst case a purchase is reported a minute later than it could have been — and Apple's server
    /// notification usually beats us to it anyway.
    private static let minSweepInterval: TimeInterval = 60
    private var lastSweepEndedAt: Date?

    private var task: Task<Void, Never>?


    /// Re-read every transaction the device knows about.
    ///
    /// `Transaction.updates` carries only what happens OUTSIDE a purchase() call — renewals, another
    /// device, Ask to Buy. A purchase the app makes itself is returned in its PurchaseResult and never
    /// appears in that stream, so the SDK cannot see it. Sweeping again catches it without the app
    /// having to report anything: the StoreKit sheet restores the app when it closes, so this runs a
    /// second after the sale. `emitIfNew` dedupes on the transaction id, so nothing is sent twice.
    func rescan() {
        #if canImport(StoreKit)
        if #available(iOS 15.0, macOS 12.0, *) {
            Task.detached { [weak self] in await self?.sweepAll(rateLimited: true) }
        }
        #endif
    }

    #if canImport(StoreKit)
    /// One pass over `Transaction.all`, serialized against every other pass. Returns immediately if a
    /// sweep is already running, having marked that one more is owed.
    @available(iOS 15.0, macOS 12.0, *)
    private func sweepAll(rateLimited: Bool = false) async {
        lock.lock()
        if sweeping { pendingSweep = true; lock.unlock(); return }
        sweeping = true
        let last = lastSweepEndedAt
        lock.unlock()

        // Waiting INSIDE the sweep, holding `sweeping`, is deliberate: foregrounds arriving during the
        // wait collapse into the one pass that is already owed rather than queueing up behind it.
        if rateLimited, let last {
            let remaining = Self.minSweepInterval - Date().timeIntervalSince(last)
            if remaining > 0 { try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
        }

        repeat {
            for await result in Transaction.all {
                guard case .verified(let tx) = result else { continue }
                emitIfNew(tx)
            }
            lock.lock()
            lastSweepEndedAt = Date()
            let again = pendingSweep
            pendingSweep = false
            if !again { sweeping = false }
            lock.unlock()
            if !again { return }
        } while true
    }
    #endif

    /// True only the first time an id is claimed this launch.
    private func claim(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return claimed.insert(id).inserted
    }

    /// Hand an id back after a report FAILED, so a later sweep in this same session can retry it —
    /// otherwise a transient network error would wait for the next cold launch to be replayed.
    func release(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        claimed.remove(id)
    }

    func start() {
        #if canImport(StoreKit)
        if #available(iOS 15.0, macOS 12.0, *) {
            task = Task.detached { [weak self] in
                // 1. Backfill: every transaction the device knows about, with its real dates.
                await self?.sweepAll()
                // 2. Live: new transactions (renewals/refunds) for the app's lifetime.
                for await update in Transaction.updates {
                    guard case .verified(let tx) = update else { continue }
                    self?.emitIfNew(tx)
                    await tx.finish()
                }
            }
        }
        #endif
    }

    #if canImport(StoreKit)
    @available(iOS 15.0, macOS 12.0, *)
    private func emitIfNew(_ tx: Transaction) {
        let txId = String(tx.id)
        guard !Storage.hasSentTransaction(txId) else { return } // already reported (belt-and-suspenders with backend dedup)
        guard claim(txId) else { return }                       // a concurrent sweep already has this one
        // Read the shared fields ONCE, through the lock, into locals — every use below is of the local.
        guard let emit = onTransaction else { release(txId); return }
        let resolvedEnvironment = environment

        let type: SubscriptionEventType
        if tx.revocationDate != nil {
            type = .refund
        } else if tx.offerType == .introductory && tx.price == 0 {
            type = .trialStarted
        } else {
            type = tx.originalID == tx.id ? .purchase : .renewal
        }
        // Prefer the transaction's OWN environment (authoritative, per-transaction) when the OS exposes
        // it; otherwise fall back to the app-level environment resolved via AppTransaction.
        // StoreKit knows exactly which kind of product this is; we were throwing that away. nonRenewable
        // maps to subscription because it IS one — a fixed-term subscription that simply does not
        // auto-renew — and grouping it with one-off purchases would misreport it just as badly.
        let purchaseType: String
        switch tx.productType {
        case .consumable:    purchaseType = "consumable"
        case .nonConsumable: purchaseType = "non_consumable"
        default:             purchaseType = "subscription" // .autoRenewable, .nonRenewable
        }
        var txEnv = resolvedEnvironment
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
            txEnv = tx.environment == .production ? "production" : "sandbox"
        }
        // NB: do NOT mark sent here — the Runtime marks it only after the POST succeeds, so a failed
        // report is replayed from `Transaction.all` on the next launch instead of being lost.
        emit(ObservedTransaction(
            transactionId: txId,
            originalTxnId: String(tx.originalID),
            productId: tx.productID,
            type: type,
            priceUsd: (tx.price as NSDecimalNumber?)?.doubleValue,
            currency: tx.currencyCode,
            occurredAt: tx.revocationDate ?? tx.purchaseDate,
            environment: txEnv,
            purchaseType: purchaseType
        ))
    }
    #endif

    deinit { task?.cancel() }
}

/// A normalized transaction handed to the runtime (decoupled from StoreKit types for testability).
struct ObservedTransaction {
    let transactionId: String
    let originalTxnId: String
    let productId: String
    let type: SubscriptionEventType
    let priceUsd: Double?
    let currency: String?
    let occurredAt: Date?
    let environment: String
    /// What KIND of purchase this is, straight from StoreKit rather than assumed.
    ///
    /// The SDK reported every purchase as "subscription" — hard-coded — so a lifetime unlock or a coin
    /// pack arrived looking like a recurring subscription. That is wrong in the optimistic direction:
    /// a one-time payment counted as recurring inflates LTV projections and appears in churn and renewal
    /// metrics it has no business in.
    let purchaseType: String
}
