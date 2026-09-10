import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

/// Public facade for the ASA ROAS Tracker SDK.
///
/// One call — `configure` — wires up first-party AdServices attribution and StoreKit 2 purchase
/// observation. Purchases, renewals and refunds need no code: StoreKit is the source of the price,
/// currency, offer type and transaction id. Ad revenue is the one thing Apple cannot see, so
/// `trackAdRevenue` reports it.
///
/// ```swift
/// Asalyze.configure(apiKey: "sk_…", appId: "com.your.app")
/// ```
public enum Asalyze {
    /// The runtime is read from whatever thread the host happens to call us on — AdMob's
    /// `paidEventHandler` fires on its own — while `configure` writes it from another. An unsynchronized
    /// class reference read against a concurrent write is the same defect that took the StoreKit observer
    /// down (see StoreKitObserver's `lock`), so the one mutable field in the public surface is guarded.
    private static let runtimeLock = NSLock()
    private static var _runtime: Runtime?
    private static var runtime: Runtime? {
        get { runtimeLock.lock(); defer { runtimeLock.unlock() }; return _runtime }
        set { runtimeLock.lock(); defer { runtimeLock.unlock() }; _runtime = newValue }
    }

    /// Configure the SDK. Call once, as early as possible (App init / didFinishLaunching).
    /// - Parameters:
    ///   - apiKey: the per-app key from the dashboard (Test Devices / My Apps).
    ///   - appId: your bundle identifier.
    ///   - endpoint: backend base URL. Defaults to production.
    public static func configure(apiKey: String, appId: String, endpoint: URL = Config.defaultEndpoint) {
        let config = Config(apiKey: apiKey, appId: appId, endpoint: endpoint)
        let runtime = Runtime(config: config)
        self.runtime = runtime
        runtime.start()
    }

    /// Expose the stable first-party install id (no IDFA) — useful to reconcile with your own analytics.
    public static var installId: String? { runtime?.installId }



    /// Tag this device with YOUR OWN id for the signed-in user — whatever your app already calls them
    /// (your backend's user id, a Firebase uid, an account number). Asalyze never generates or discovers
    /// it; you pass it, typically right after your sign-in completes.
    ///
    /// It is opaque to us and is used for exactly one thing: finding this install in User Journey by
    /// searching for your id, so our numbers can be reconciled against your own system. It never
    /// attributes, joins revenue or dedupes, and two devices sharing one account is expected.
    ///
    /// Reported immediately, not on the next heartbeat. Pass `nil` on sign-out to clear it.
    ///
    /// ```swift
    /// Asalyze.setUserId(session.user.id)   // after sign-in
    /// Asalyze.setUserId(nil)               // on sign-out
    /// ```
    public static func setUserId(_ userId: String?) {
        runtime?.userId = userId
    }


    /// Report impression-level ad revenue (e.g. from AdMob's `paidEventHandler`).
    public static func trackAdRevenue(valueUsd: Double, format: AdFormat, currency: String = "USD") {
        runtime?.trackAdRevenue(value: valueUsd, currency: currency, format: format)
    }

    /// Report a named custom event for Goals (e.g. "completed_onboarding", "reached_level_5").
    public static func trackEvent(_ name: String, valueUsd: Double? = nil) {
        runtime?.trackCustomEvent(name: name, value: valueUsd)
    }

}
