import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Internal orchestrator wired up by `Asalyze.configure`. Owns the install identity, the API client,
/// attribution capture and the StoreKit observer. Kept `internal` so the public surface stays small.

/// The SDK's own version, reported with every install.
let asalyzeSDKVersion = "3.1.9"

final class Runtime {
    let config: Config
    let installId: String
    let isReinstall: Bool

    /// The app's own id for the signed-in user, from `Asalyze.setUserId`. Locked because the host sets it
    /// from whatever thread sign-in completes on. Setting it reports immediately; `nil` means sign-out
    /// and is reported as an empty string.
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
        // Register the install with its attribution token and environment, and hand the resolved
        // environment to the observer so its events agree with the install.
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
        // Observe StoreKit for the app's lifetime. A transaction is marked sent only after the report
        // lands, so a failed POST is retried from `Transaction.all` on the next launch.
        storeKit.onTransaction = { [weak self] tx in
            guard let self else { return }
            Task {
                if await self.api.recordSubscription(tx, installId: self.installId) {
                    Storage.markTransactionSent(tx.transactionId)
                } else {
                    // Hand the id back so a foreground rescan can retry it in this session.
                    self.storeKit.release(tx.transactionId)
                }
            }
        }
        storeKit.start()
        startHeartbeat()
    }

    /// How long a device may stay quiet before the next foreground counts as a fresh sighting.
    private static let heartbeatInterval: TimeInterval = 24 * 60 * 60

    /// Tell the backend the app is still in use, at most once a day, so last-seen means last USE rather
    /// than last cold launch. This is not uninstall detection: no code runs after an app is deleted, so
    /// the absence of a ping only means "not opened".
    private func startHeartbeat() {
        #if canImport(UIKit)
        // Fire for this foreground too — waiting for the next one would miss single-session users.
        beat()
        // The first notification belongs to the launch that just ran the backfill sweep, so it gets no
        // rescan. Every later foreground is a genuine return and does. Main thread only.
        var isLaunchForeground = true
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.beat()
            if isLaunchForeground { isLaunchForeground = false; return }
            // A purchase made in this session never reaches `Transaction.updates`, and the payment sheet
            // restores the app as it closes — so this is where such a sale is caught.
            self?.storeKit.rescan()
        }
        #endif
    }

    private func beat() {
        if let last = Storage.lastPingAt(), Date().timeIntervalSince(last) < Self.heartbeatInterval { return }
        // Marked before the request, so a device opened while offline doesn't retry all day.
        Storage.markPinged()
        let id = installId
        let user = userId
        Task { await api.ping(installId: id, userId: user) }
    }

    func trackAdRevenue(value: Double, currency: String, format: AdFormat) {
        // AdMob can report a non-finite value for an unpriced impression, and a NaN reaching
        // JSONSerialization raises an ObjC exception that would terminate the host app.
        guard value.isFinite else {
            NSLog("[Asalyze] ignoring ad revenue with a non-finite value")
            return
        }
        // Region is read at the impression, not at install: eCPM follows where the ad was served.
        Task {
            let region = SDKEnvironment.currentRegion()
            await api.recordEvent(.ad(installId: installId, value: value, currency: currency,
                                      format: format, region: region))
        }
    }

    func trackCustomEvent(name: String, value: Double?) {
        let value = (value?.isFinite ?? false) ? value : nil
        Task { await api.recordCustomEvent(installId: installId, name: name, value: value) }
    }

}
