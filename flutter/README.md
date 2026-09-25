# asalyze (Flutter)

Apple Search Ads ROAS tracking for **iOS** Flutter apps. A self-contained plugin: the native `Asalyze`
Swift SDK (AdServices attribution, StoreKit 2 purchases, ad revenue) is vendored into the plugin's iOS
pod and compiled in — **no external pods, no CocoaPods trunk dependency**. Dart just calls in.

> iOS only. Apple Search Ads attribution is an iOS capability, so there is **no Android implementation**
> (every call is a no-op off iOS). Requires **iOS 15+**.

## Install

From [pub.dev](https://pub.dev/packages/asalyze):

```yaml
dependencies:
  asalyze: ^3.1.9
```

Or `flutter pub add asalyze`. Then `flutter pub get` and, from `ios/`, `pod install`. Ensure the app's iOS
deployment target is **15.0+**.

## Use

```dart
import 'package:asalyze/asalyze.dart';

// Call once, as early as possible (e.g. top of main(), before runApp).
await Asalyze.configure(
  apiKey: 'sk_…',            // Asalyze dashboard → My Apps → app → SDK API key
  appId: 'com.your.app',     // your bundle id
  // endpoint: 'http://your-mac.local:3100',  // ← only for local/staging; omit for production
);

// StoreKit 2 purchases/renewals/refunds are captured NATIVELY — there is nothing to call.
// Apple's own transaction id, price, currency, offer type and product type are used.

// Ad revenue (e.g. from AdMob's paid-event callback):
await Asalyze.trackAdRevenue(valueUsd: 0.012, format: AdFormat.banner);

// Custom Goal events + optional user id:
await Asalyze.trackEvent('completed_onboarding');
await Asalyze.setUserId('user_123');
```

## Local backend testing (dev)

To point at a backend running on your Mac instead of production:

1. Pass `endpoint:` to `configure` — use the Mac's **`.local` hostname** (survives IP changes), e.g.
   `http://your-mac.local:3100`. On a real device `localhost` will NOT work (that's the phone).
2. iOS blocks plain HTTP — add to the **app's** `ios/Runner/Info.plist` (debug only, never ship):
   ```xml
   <key>NSAppTransportSecurity</key>
   <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
   <key>NSLocalNetworkUsageDescription</key>
   <string>Connects to the local Asalyze dev server for testing.</string>
   ```
   Accept the iOS "Local Network" permission prompt on first launch.
3. Phone and Mac on the **same Wi-Fi**. A dev build reports as `sandbox` → data lands in the dashboard's
   **Test Devices → Live sandbox feed**, not production Reports.

## Known limitations

- **No offline queue / retry** yet — ingest is fire-and-forget (events lost on a network failure).
- Default endpoint is `https://asalyze.com` (live) — pass `endpoint:` only for local/staging testing.

### Subscription transitions

**Cancelled, expired, resubscribed and offer-redeemed** reach Asalyze through **App Store Server
Notifications** and the App Store Server API. Renewal *status* is not a StoreKit transaction, so these
never appear in the transaction stream and there is nothing to report from the app.

Connect App Store Server Notifications and this is handled — including for users who never reopen the
app, which no on-device code can cover.

---

Built and maintained by [Codematics Services Private Limited](https://asalyze.com). Malik Ahsan Ali — Founder & Managing Director.
