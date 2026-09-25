# Asalyze — iOS SDK

Apple Search Ads attribution and revenue tracking for iOS apps. Installs are matched to the campaign, ad
group and keyword that produced them; purchases, subscriptions and ad revenue are tracked against them.
No IDFA and no ATT prompt. iOS 15+.

## Install

**Swift Package Manager**
```swift
.package(url: "https://github.com/CodematicsInc-MD/Asalyze-iOS-SDK", from: "3.1.9")
```

**CocoaPods**
```ruby
pod 'Asalyze', '~> 3.1.9'
```

**Flutter** — [pub.dev/packages/asalyze](https://pub.dev/packages/asalyze)
```yaml
dependencies:
  asalyze: ^3.1.9
```

**Unity** — Package Manager ▸ Add package from git URL
```
https://github.com/CodematicsInc-MD/Asalyze-iOS-SDK.git?path=/unity#v3.1.9
```

## Use

```swift
import Asalyze

Asalyze.configure(apiKey: "sk_…", appId: "com.your.app")   // once, at startup
```

That is the whole setup. Attribution and purchases are tracked from then on, with nothing to call per
purchase — prices, currencies, offer types and transaction ids come from Apple rather than from your code.

Optional:

```swift
Asalyze.trackAdRevenue(valueUsd:format:currency:)   // from AdMob's paid event
Asalyze.trackEvent("completed_onboarding")          // your own events → Goals
Asalyze.setUserId("user_123")                       // your id for the signed-in user
```

## What it tracks

| | |
|---|---|
| **Attribution** | Apple Search Ads campaign, ad group and keyword per install; organic installs recorded too |
| **Purchases** | One-off purchases and subscriptions, with Apple's own price, currency and offer type |
| **Subscription lifecycle** | Renewals, cancellations, expiries and refunds — including for people who never reopen the app, once App Store Server Notifications are connected |
| **Ad revenue** | Per impression, via the AdMob helper |
| **Custom events** | Any event you send, for funnels and goals |

## Requirements

iOS 15+, and an Asalyze account with an app API key from the dashboard.

---

Built and maintained by [Codematics Services Private Limited](https://asalyze.com). Malik Ahsan Ali — Founder & Managing Director.
