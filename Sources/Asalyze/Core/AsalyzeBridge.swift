import Foundation

/// Objective-C–visible façade over ``Asalyze`` for **non-Swift hosts** (Unity, Cordova, native ObjC).
///
/// Swift and Flutter apps use ``Asalyze`` directly; this class exists so a C-callable layer (e.g. the
/// Unity plugin's `.mm` shim) can drive the SDK without touching Swift types. Enum arguments are passed
/// as their **backend string values** (the same taxonomy as the REST API and the Flutter bridge), so
/// callers never need the Swift `Offer` / `AdFormat` enums.
///
/// The heavy lifting — AdServices attribution and StoreKit 2 purchase observation — still happens
/// automatically after ``configure(apiKey:appId:endpoint:)``; these methods only cover the manual
/// reporting paths (ad revenue, custom events) and identity.
@objc(AsalyzeBridge)
public final class AsalyzeBridge: NSObject {
    /// Configure once at launch. `endpoint` is optional — pass `nil`/empty for production.
    @objc public static func configure(apiKey: String, appId: String, endpoint: String?) {
        if let endpoint, !endpoint.isEmpty, let url = URL(string: endpoint) {
            Asalyze.configure(apiKey: apiKey, appId: appId, endpoint: url)
        } else {
            Asalyze.configure(apiKey: apiKey, appId: appId)
        }
    }

    /// The stable first-party install id (no IDFA), or `nil` before `configure`.
    @objc public static var installId: String? { Asalyze.installId }

    /// Tag events with your own user id (pass `nil` to clear).
    @objc public static func setUserId(_ userId: String?) { Asalyze.setUserId(userId) }


    /// Report impression-level ad revenue. `format` is a backend ad-format string (e.g. `"rewarded"`).
    @objc public static func trackAdRevenue(valueUsd: Double, format: String, currency: String) {
        Asalyze.trackAdRevenue(valueUsd: valueUsd, format: AdFormat(rawValue: format) ?? .banner,
                               currency: currency)
    }

    /// Report a named custom event for Goals. Pass `nil` for `valueUsd` to omit a value.
    @objc public static func trackEvent(_ name: String, valueUsd: NSNumber?) {
        Asalyze.trackEvent(name, valueUsd: valueUsd?.doubleValue)
    }

}
