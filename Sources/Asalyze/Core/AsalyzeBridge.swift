import Foundation

/// Objective-C façade over ``Asalyze`` for non-Swift hosts (Unity, Cordova, native ObjC). Enum arguments
/// are passed as strings, so callers need no Swift types. Attribution and purchase tracking still happen
/// automatically after `configure`; these methods cover ad revenue, custom events and identity.
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
