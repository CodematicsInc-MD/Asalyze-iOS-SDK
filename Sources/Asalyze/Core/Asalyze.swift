import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

/// Public facade for the Asalyze SDK.
///
/// One call — `configure` — sets up Apple Search Ads attribution and purchase tracking. Purchases,
/// renewals and refunds need no code of your own. Ad revenue is the one thing Apple cannot see, so
/// report it with `trackAdRevenue`.
///
/// ```swift
/// Asalyze.configure(apiKey: "sk_…", appId: "com.your.app")
/// ```
public enum Asalyze {
    /// Guarded: the host can call in from any thread (AdMob's `paidEventHandler` has its own) while
    /// `configure` writes this from another.
    private static let runtimeLock = NSLock()
    private static var _runtime: Runtime?
    private static var runtime: Runtime? {
        get { runtimeLock.lock(); defer { runtimeLock.unlock() }; return _runtime }
        set { runtimeLock.lock(); defer { runtimeLock.unlock() }; _runtime = newValue }
    }

    /// Configure the SDK. Call once, as early as possible (App init / didFinishLaunching).
    /// - Parameters:
    ///   - apiKey: the per-app key from the dashboard (My Apps → your app → SDK API key).
    ///   - appId: your bundle identifier.
    ///   - endpoint: base URL. Defaults to production; pass one only for local or staging testing.
    public static func configure(apiKey: String, appId: String, endpoint: URL = Config.defaultEndpoint) {
        let config = Config(apiKey: apiKey, appId: appId, endpoint: endpoint)
        let runtime = Runtime(config: config)
        self.runtime = runtime
        runtime.start()
    }

    /// Expose the stable first-party install id (no IDFA) — useful to reconcile with your own analytics.
    public static var installId: String? { runtime?.installId }



    /// Tag this device with your own id for the signed-in user, so you can find the install in User
    /// Journey by searching for it. Optional: nothing in attribution or revenue uses it. Reported
    /// immediately; pass `nil` on sign-out.
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
