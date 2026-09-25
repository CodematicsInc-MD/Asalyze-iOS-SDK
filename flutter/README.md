# asalyze (Flutter)

Apple Search Ads attribution and revenue tracking for iOS Flutter apps. Installs are matched to the
campaign, ad group and keyword that produced them; purchases, subscriptions and ad revenue are tracked
against them. No IDFA and no ATT prompt.

> iOS only — every call is a no-op on other platforms. Requires iOS 15+.

## Install

```yaml
dependencies:
  asalyze: ^3.2.0
```

Or `flutter pub add asalyze`, then `flutter pub get` and `pod install` from `ios/`.

## Use

```dart
import 'package:asalyze/asalyze.dart';

// Once, as early as possible — top of main(), before runApp.
await Asalyze.configure(
  apiKey: 'sk_…',          // My Apps → your app → SDK API key
  appId: 'com.your.app',
);
```

That is the whole setup. Attribution, purchases and subscriptions are tracked from then on — nothing to
call per purchase.

**If your app shows ads**, report each impression's revenue from your mediation's paid-event callback:

```dart
await Asalyze.trackAdRevenue(valueUsd: 0.012, currency: 'USD', format: AdFormat.banner);
```

Optional:

```dart
await Asalyze.trackEvent('completed_onboarding');   // your own events → Goals
await Asalyze.setUserId('user_123');                // your id for a signed-in user
```

## What it tracks

| | |
|---|---|
| **Attribution** | Apple Search Ads campaign, ad group and keyword per install; organic installs recorded too |
| **Purchases** | One-off purchases and subscriptions, with Apple's own price, currency and offer type |
| **Subscription lifecycle** | Renewals, cancellations, expiries and refunds (connect App Store Server Notifications in the dashboard) |
| **Ad revenue** | Per impression, from your mediation's paid-event callback |
| **Custom events** | Any event you send, for funnels and goals |

## Requirements

iOS 15+, and an Asalyze account with an app API key from the dashboard.

---

Built and maintained by [Codematics Services Private Limited](https://asalyze.com). Malik Ahsan Ali — Founder & Managing Director.
