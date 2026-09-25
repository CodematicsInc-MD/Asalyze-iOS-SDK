import Foundation

/// Backend base URL + credentials. `defaultEndpoint` points at production (the API is path-routed
/// under this host at `/v1`, so no separate `api.` subdomain).
public struct Config {
    public let apiKey: String
    public let appId: String
    public let endpoint: URL

    public static let defaultEndpoint = URL(string: "https://asalyze.com")!

    public init(apiKey: String, appId: String, endpoint: URL = Config.defaultEndpoint) {
        self.apiKey = apiKey
        self.appId = appId
        self.endpoint = endpoint
    }
}

/// What kind of in-app purchase this is, from StoreKit's `productType`. A non-renewing subscription
/// counts as a subscription: it is one, just fixed-term.
public enum PurchaseType: String, Codable {
    case subscription
    case consumable
    case nonConsumable = "non_consumable"
}

/// Ad formats — mirrors the backend `ad_format` enum.
public enum AdFormat: String, Codable {
    case banner, interstitial, rewarded
    case rewardedInterstitial = "rewarded_interstitial"
    case native
    case appOpen = "app_open"
}

/// Subscription lifecycle transition the SDK can observe (server derives `trial_converted`).
public enum SubscriptionEventType: String, Codable {
    case trialStarted = "trial_started"
    case purchase, renewal
    case offerRedeemed = "offer_redeemed"
    case refund, expired, resubscribed
    case autoRenewOff = "auto_renew_off"
}

