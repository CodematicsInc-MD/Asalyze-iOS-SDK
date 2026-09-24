# Asalyze — Unity SDK (iOS)

Apple Search Ads ROAS attribution + StoreKit 2 subscription and ad-revenue tracking for Unity iOS games.
Configure once; AdServices attribution and purchases (including Unity IAP) are observed automatically.

> **iOS only.** Apple Search Ads is iOS-only, so every call is a safe no-op in the Editor and on Android.

## Requirements
- Unity 2020.3+
- iOS 15+ target
- **External Dependency Manager for Unity (EDM4U)** in your project — used to pull the native pod.
  Install `com.google.external-dependency-manager` (bundled with Firebase/AdMob/LevelPlay, or via OpenUPM).

## Install
Unity ▸ Window ▸ Package Manager ▸ **+ ▸ Add package from git URL…**

```
https://github.com/CodematicsInc-MD/Asalyze-iOS-SDK.git?path=/unity#v3.1.8
```

On your next iOS build, EDM4U adds `pod 'Asalyze', '~> 3.1.8'` and runs `pod install` automatically.

### Framework linkage (important)
The native bridge imports `<Asalyze/Asalyze-Swift.h>`, so the Asalyze pod must be integrated **as a
framework**. In **Assets ▸ External Dependency Manager ▸ iOS Resolver ▸ Settings**, enable
**“Add use_frameworks to Podfile”** (or add `use_frameworks!` to the Podfile yourself). If you link pods
statically, the Swift header won't be found at compile time.

## Usage

```csharp
using UnityEngine;

public class AsalyzeBootstrap : MonoBehaviour
{
    void Awake()
    {
        // Call once, as early as possible. From here, AdServices attribution +
        // StoreKit 2 purchases are tracked automatically — no per-purchase code.
        Asalyze.Configure(
            apiKey: "sk_…",          // My Apps → your app → SDK API key
            appId:  "com.your.game"  // your bundle id
        );
    }
}
```

### Ad revenue (route mediation revenue into ROAS)
```csharp
// e.g. from AdMob / LevelPlay impression-level revenue callback:
Asalyze.TrackAdRevenue(valueUsd: 0.012, format: AsalyzeAdFormat.Rewarded);
```

### Custom goal events + your own user id
```csharp
Asalyze.TrackEvent("level_5_reached");
Asalyze.SetUserId("player_123");
```

### Purchases need no calls at all
StoreKit 2 purchases, renewals and refunds — including Unity IAP — are observed automatically, with
Apple's own price, currency, transaction id and product type. There is nothing to call, and nothing to
keep in step with your store logic.

There is deliberately no manual purchase call: one would take the app's word for the price and, used
alongside the observer, count the same money twice.

## API
| Call | Purpose |
|---|---|
| `Asalyze.Configure(apiKey, appId, endpoint=null)` | Initialize (once). |
| `Asalyze.InstallId()` | Stable first-party id (UUID). Optional — for reconciling with your own analytics. |
| `Asalyze.SetUserId(id)` | Your own user id for cross-device reconciliation. |
| `Asalyze.TrackAdRevenue(valueUsd, format, currency="USD")` | Impression-level ad revenue. |
| `Asalyze.TrackEvent(name, valueUsd=null)` | Custom Goals event. |

Docs: https://asalyze.com/docs

### Subscription transitions

**Cancelled, expired, resubscribed and offer-redeemed** reach Asalyze through **App Store Server
Notifications** and the App Store Server API. Renewal *status* is not a StoreKit transaction, so these
never appear in the transaction stream and there is nothing to report from the app.

Connect App Store Server Notifications and this is handled — including for users who never reopen the
app, which no on-device code can cover.

---

Built and maintained by [Codematics Services Private Limited](https://asalyze.com). Malik Ahsan Ali — Founder & Managing Director.
