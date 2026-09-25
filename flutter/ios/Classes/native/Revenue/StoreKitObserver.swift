import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

/// Observes StoreKit 2 transactions: on launch it backfills the device's past purchases from
/// `Transaction.all`, then watches `Transaction.updates` for the app's lifetime. Every transaction
/// carries Apple's own id, price, currency and product type.
final class StoreKitObserver {
    /// Guards every mutable field. Sweeps run on detached tasks while the Runtime writes here.
    /// Never call out (to `onTransaction`) while holding it: NSLock is not recursive.
    private let lock = NSLock()

    /// Called once per not-yet-sent verified transaction (past + live: initial buys, renewals, refunds).
    var onTransaction: ((ObservedTransaction) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onTransaction }
        set { lock.lock(); defer { lock.unlock() }; _onTransaction = newValue }
    }
    private var _onTransaction: ((ObservedTransaction) -> Void)?

    /// Resolved app environment, used on OS versions where a transaction doesn't expose its own.
    var environment: String {
        get { lock.lock(); defer { lock.unlock() }; return _environment }
        set { lock.lock(); defer { lock.unlock() }; _environment = newValue }
    }
    private var _environment: String = SDKEnvironment.current.rawValue

    /// Ids already emitted during THIS launch, so two overlapping sweeps can't report one purchase
    /// twice. In memory only: a failed report must still replay from `Transaction.all` next launch.
    private var claimed: Set<String> = []

    /// Sweeps never overlap. One arriving while another runs is queued, not dropped — a purchase
    /// completing mid-sweep may sit where the running pass has already been.
    private var sweeping = false
    private var pendingSweep = false

    /// Floor between two foreground-triggered sweeps. A request inside the window is delayed, never
    /// dropped.
    private static let minSweepInterval: TimeInterval = 60
    private var lastSweepEndedAt: Date?

    private var task: Task<Void, Never>?


    /// Re-read every transaction the device knows about. Needed because a purchase the app makes itself
    /// is returned in its own `PurchaseResult` and never appears in `Transaction.updates`.
    func rescan() {
        #if canImport(StoreKit)
        if #available(iOS 15.0, macOS 12.0, *) {
            Task.detached { [weak self] in await self?.sweepAll(rateLimited: true) }
        }
        #endif
    }

    /// The right to run a sweep, or a note that one is already running and another is now owed.
    private enum SweepClaim {
        case owned(lastEndedAt: Date?)
        case alreadyRunning
    }

    /// Take the sweep, or record that one more is owed.
    private func claimSweep() -> SweepClaim {
        lock.lock(); defer { lock.unlock() }
        if sweeping { pendingSweep = true; return .alreadyRunning }
        sweeping = true
        return .owned(lastEndedAt: lastSweepEndedAt)
    }

    /// End one pass. True when a sweep was requested while this one ran, and should run now.
    private func finishSweepPass() -> Bool {
        lock.lock(); defer { lock.unlock() }
        lastSweepEndedAt = Date()
        let again = pendingSweep
        pendingSweep = false
        if !again { sweeping = false }
        return again
    }

    #if canImport(StoreKit)
    /// One pass over `Transaction.all`, serialized against every other pass.
    ///
    /// The locking lives in `claimSweep`/`finishSweepPass` because a lock must never be held across an
    /// `await` — note the `await` below sits between the two calls, never inside either.
    @available(iOS 15.0, macOS 12.0, *)
    private func sweepAll(rateLimited: Bool = false) async {
        guard case .owned(let lastEndedAt) = claimSweep() else { return }

        // Waiting while holding the claim collapses foregrounds arriving during the wait into this pass.
        if rateLimited, let lastEndedAt {
            let remaining = Self.minSweepInterval - Date().timeIntervalSince(lastEndedAt)
            if remaining > 0 { try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
        }

        repeat {
            for await result in Transaction.all {
                guard case .verified(let tx) = result else { continue }
                emitIfNew(tx)
            }
        } while finishSweepPass()
    }
    #endif

    /// True only the first time an id is claimed this launch.
    private func claim(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return claimed.insert(id).inserted
    }

    /// Hand an id back after a report failed, so a later sweep this session can retry it.
    func release(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        claimed.remove(id)
    }

    func start() {
        #if canImport(StoreKit)
        if #available(iOS 15.0, macOS 12.0, *) {
            task = Task.detached { [weak self] in
                // Backfill first, then live transactions for the app's lifetime.
                await self?.sweepAll()
                for await update in Transaction.updates {
                    guard case .verified(let tx) = update else { continue }
                    self?.emitIfNew(tx)
                }
            }
        }
        #endif
    }

    #if canImport(StoreKit)
    @available(iOS 15.0, macOS 12.0, *)
    private func emitIfNew(_ tx: Transaction) {
        let txId = String(tx.id)
        guard !Storage.hasSentTransaction(txId) else { return }
        guard claim(txId) else { return }
        // Read shared fields once, through the lock, into locals.
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
        // Product kind straight from StoreKit. Non-renewable maps to subscription because it is one:
        // a fixed-term subscription that does not auto-renew.
        let purchaseType: String
        switch tx.productType {
        case .consumable:    purchaseType = "consumable"
        case .nonConsumable: purchaseType = "non_consumable"
        default:             purchaseType = "subscription" // .autoRenewable, .nonRenewable
        }
        // Prefer the transaction's own environment where the OS exposes it.
        var txEnv = resolvedEnvironment
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
            txEnv = tx.environment == .production ? "production" : "sandbox"
        }
        // NEVER read `tx.currencyCode` above iOS 15 — on those versions it can dereference null.
        // `tx.currency` is iOS 16+ and back-deployed; iOS 15 keeps the old call.
        let currency: String?
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
            currency = tx.currency?.identifier
        } else {
            currency = tx.currencyCode
        }
        // Not marked sent here: the Runtime marks it only after the POST succeeds, so a failed report
        // replays from `Transaction.all` on the next launch.
        emit(ObservedTransaction(
            transactionId: txId,
            originalTxnId: String(tx.originalID),
            productId: tx.productID,
            type: type,
            priceUsd: (tx.price as NSDecimalNumber?)?.doubleValue,
            currency: currency,
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
    /// consumable / non_consumable / subscription, straight from StoreKit rather than assumed.
    let purchaseType: String
}
