# Asalyze — iOS SDK

Apple Search Ads attribution and revenue tracking for iOS apps. On-device it captures the AdServices
attribution token once on launch, observes StoreKit 2 purchases, renewals and refunds, routes AdMob ad
revenue, and sends events to Asalyze. iOS 15+. No IDFA and no ATT prompt. AdServices and StoreKit are linked
as **system frameworks** (not bundled); AdMob is hooked, not bundled.

## Install

**Swift Package Manager**
```swift
.package(url: "https://github.com/CodematicsInc-MD/Asalyze-iOS-SDK", from: "3.1.8")
```

**CocoaPods**
```ruby
pod 'Asalyze', '~> 3.1.8'
```

**Flutter** — [pub.dev/packages/asalyze](https://pub.dev/packages/asalyze)
```yaml
dependencies:
  asalyze: ^3.1.8
```

**Unity** — Package Manager ▸ Add package from git URL
```
https://github.com/CodematicsInc-MD/Asalyze-iOS-SDK.git?path=/unity#v3.1.8
```
EDM4U then pulls `pod 'Asalyze', '~> 3.1.8'` on the next iOS build. See [`unity/`](unity/).

> Pin the **full version** (`3.1.8`) rather than `~> 3.1`, which also resolves to earlier 3.1.x releases.

## Public surface
```swift
Asalyze.configure(apiKey: "sk_…", appId: "com.your.app")        // AdServices + StoreKit 2 auto
Asalyze.trackAdRevenue(valueUsd:format:currency:)               // e.g. from AdMob paidEventHandler
Asalyze.trackEvent("completed_onboarding")                      // custom event → Goals
Asalyze.setUserId("…")                                          // optional, your own id
```

Purchases are **not** in that list, deliberately. StoreKit 2 is observed automatically, using Apple's
own transaction id, price, currency, offer type and product type — more accurate than anything an app
can pass, and the transaction id is what makes deduplication possible. There is no manual purchase
call: one would take the app's word for the price and, used alongside the observer, count the same
money twice.

## Layout (layered)
```
Sources/Asalyze/
├── Core/          configure(apiKey:appId:), Keychain install id, environment detection, models
├── Attribution/   AdServices token capture -> resolved server-side to campaign/adgroup/keyword
├── Revenue/       StoreKit 2 Transaction.updates observer; AdMob adapter
└── Networking/    ingest client -> POST /v1/install, /v1/event, /v1/subscription, /v1/custom-event
```

Attribution capture sits behind its own module, so a SKAdNetwork / AdAttributionKit conversion-value
manager can be added alongside it — never entangled with IAP or ad tracking.

## Subscription transitions

**Cancelled, expired, resubscribed and offer-redeemed** reach Asalyze through **App Store Server
Notifications** and the App Store Server API. Renewal *status* is not a StoreKit transaction, so these
never appear in the transaction stream and there is nothing to report from the app.

Connect App Store Server Notifications and this is handled — including for users who never reopen the
app, which no on-device code can cover.

---

Built and maintained by [Codematics Services Private Limited](https://asalyze.com). Malik Ahsan Ali — Founder & Managing Director.
