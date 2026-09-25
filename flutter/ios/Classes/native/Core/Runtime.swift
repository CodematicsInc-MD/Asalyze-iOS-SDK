import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Internal orchestrator wired up by `Asalyze.configure`. Owns the install identity, the API client,
/// the attribution capture, and the StoreKit observer. Kept `internal` so the public surface stays tiny.
/// The SDK's own version, reported with every install.
///
/// The SDK's own version, sent with every install. Reading it directly beats inferring it from which
/// fields a payload happens to carry: that only works while every release adds one, and cannot tell
/// two releases apart once both send the same set.
let asalyzeSDKVersion = "3.1.9"

final class Runtime {
    let config: Config
    let installId: String
    let isReinstall: Bool

    /// The app's OWN id for the signed-in user, from `Asalyze.setUserId`.
    ///
    /// Behind the same lock as everything else shared here: the host calls `setUserId` from whatever
    /// thread its sign-in completes on, while `beat()` may be reading it on another.
    ///
    /// Setting it REPORTS it immediately rather than waiting for the next heartbeat. Sign-in is exactly
    /// when someone opens the dashboard to look for that user, and the heartbeat is throttled to a day —
    /// so waiting could mean the id shows up tomorrow. `nil` is a sign-out and is reported too, as an
    /// empty string, because "this device is no longer that person" is information we would otherwise
    /// keep serving as fact.
    private let userIdLock = NSLock()
    private var _userId: String?
    var userId: String? {
        get { userIdLock.lock(); defer { userIdLock.unlock() }; return _userId }
        set {
            userIdLock.lock()
            let changed = _userId != newValue
            _userId = newValue
            userIdLock.unlock()
            guard changed else { return }
            let id = installId
            Task { await api.ping(installId: id, userId: newValue ?? "") }
        }
    }

    private let api: APIClient
    private let storeKit: StoreKitObserver

    init(config: Config) {
        self.config = config
        let identity = Storage.loadIdentity()
        self.installId = identity.installId
        self.isReinstall = identity.isReinstall
        self.api = APIClient(config: config)
        self.storeKit = StoreKitObserver()
    }

    #if canImport(UIKit)
    private var foregroundObserver: NSObjectProtocol?
    #endif

    deinit {
        #if canImport(UIKit)
        if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
        #endif
    }

    func start() {
        // 1. Register the install with its AdServices attribution token (resolved server-side) and its
        //    environment (authoritative via StoreKit AppTransaction) — so TestFlight / debug installs land
        //    in Test Devices, not production reports. Also hand the resolved env to the observer so its
        //    events agree with the install (belt-and-suspenders with per-transaction .environment).
        Task {
            let ctx = await SDKEnvironment.appContext()
            self.storeKit.environment = ctx.environment.rawValue
            let attribution = AttributionManager.attributionToken()
            await api.registerInstall(installId: installId, attributionToken: attribution.token, environment: ctx.environment.rawValue,
                                      isReinstall: isReinstall, appVersion: ctx.version, appBuild: ctx.build, installedAt: ctx.installedAt,
                                      deviceRegion: ctx.region, osVersion: ctx.osVersion, legacyReceipt: ctx.legacyReceipt,
                                      appTransactionJws: ctx.appTransactionJws, sdkVersion: asalyzeSDKVersion,
                                      tokenError: attribution.error, userId: userId, deviceModel: ctx.deviceModel)
        }
        // 2. Observe StoreKit 2 transactions for the app's lifetime. Mark a transaction as sent only
        //    after the report lands — so a failed POST is retried from `Transaction.all` next launch
        //    (StoreKit is the durable queue; backend dedups on transactionId). This is what stops a
        //    transient network failure from permanently orphaning a purchase.
        storeKit.onTransaction = { [weak self] tx in
            guard let self else { return }
            Task {
                if await self.api.recordSubscription(tx, installId: self.installId) {
                    Storage.markTransactionSent(tx.transactionId)
                } else {
                    // Hand the id back so a foreground rescan can try again in THIS session. Without
                    // this the observer's claim would hold until the app is relaunched, turning one
                    // dropped connection into a purchase that goes unreported for the rest of the run.
                    self.storeKit.release(tx.transactionId)
                }
            }
        }
        storeKit.start()
        startHeartbeat()
    }

    /// How long a device may stay quiet before the next foreground counts as a fresh sighting. A day is
    /// the resolution every report that reads last-seen actually uses, and anything tighter would post
    /// on every app switch for no gain in what we can say.
    private static let heartbeatInterval: TimeInterval = 24 * 60 * 60

    /// Tell the backend the app is still being used, at most once a day.
    ///
    /// registerInstall fires only at startup, so on iOS — where an app can stay resident for weeks — a
    /// daily user who never force-quits was last SEEN whenever they last cold-launched. Reports that
    /// ask "has this cohort gone quiet?" were reading that as churn.
    ///
    /// This is not uninstall tracking. No code runs after an app is deleted, so the SDK cannot report
    /// its own removal; the absence of a ping means "not opened", which is a weaker claim and the only
    /// honest one available here.
    private func startHeartbeat() {
        #if canImport(UIKit)
        // Fire once for THIS foreground too: the app has just become active, which is exactly the
        // event being recorded, and waiting for the next one would miss single-session users entirely.
        beat()
        // The FIRST notification after registering belongs to the launch that just called start(), whose
        // backfill sweep is already running — rescanning for it is the same walk of Transaction.all
        // twice, for nothing. Every LATER foreground is a genuine return to the app and does get one.
        // Only ever read and written on the main thread, where UIApplication posts its lifecycle
        // notifications.
        var isLaunchForeground = true
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.beat()
            if isLaunchForeground { isLaunchForeground = false; return }
            // A purchase made in this session never reaches Transaction.updates, and the payment sheet
            // restores the app as it closes — so this is where an unreported sale gets caught.
            self?.storeKit.rescan()
        }
        #endif
    }

    private func beat() {
        if let last = Storage.lastPingAt(), Date().timeIntervalSince(last) < Self.heartbeatInterval { return }
        // Marked before the request, not after: a device that is opened while offline should not retry
        // on every foreground for the rest of the day. A missed beat costs a day of resolution on a
        // signal measured in days; a retry loop costs the user's battery.
        Storage.markPinged()
        let id = installId
        let user = userId
        Task { await api.ping(installId: id, userId: user) }
    }

    func trackAdRevenue(value: Double, currency: String, format: AdFormat) {
        // A non-finite value would take the host app down, not just lose the impression.
        //
        // This number comes straight from AdMob's paidEventHandler, and `GADAdValue.value` is an
        // NSDecimalNumber that can be `.notANumber` — an unpriced or no-fill impression. `.doubleValue`
        // turns that into a Swift NaN, and NaN is not a JSON number: JSONSerialization does not THROW on
        // it, it raises an ObjC NSInvalidArgumentException, which `try?` cannot catch and which
        // terminates the process. An analytics SDK crashing its host over a value it could not express
        // is indefensible, so the impression is dropped and noted instead.
        guard value.isFinite else {
            NSLog("[Asalyze] ignoring ad revenue with a non-finite value")
            return
        }
        // Read at the impression, not at install: eCPM is set by where the ad was served, and a user
        // who has travelled since installing would otherwise have every impression priced against the
        // country they signed up in.
        Task {
            let region = SDKEnvironment.currentRegion()
            await api.recordEvent(.ad(installId: installId, value: value, currency: currency,
                                      format: format, region: region))
        }
    }

    func trackCustomEvent(name: String, value: Double?) {
        // Same reasoning as trackAdRevenue: a NaN reaching JSONSerialization is a crash, not an error.
        let value = (value?.isFinite ?? false) ? value : nil
        Task { await api.recordCustomEvent(installId: installId, name: name, value: value) }
    }

}
