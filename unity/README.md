# Asalyze — Unity SDK (iOS)

Apple Search Ads attribution and revenue tracking for Unity iOS games. Installs are matched to the
campaign, ad group and keyword that produced them; purchases (including Unity IAP), subscriptions and ad
revenue are tracked against them. No IDFA and no ATT prompt.

> iOS only — every call is a no-op in the Editor and on other platforms.

## Requirements

- Unity 2020.3+, iOS 15+ target
- **External Dependency Manager for Unity (EDM4U)**, which pulls the native pod. Install
  `com.google.external-dependency-manager` (bundled with Firebase, AdMob and LevelPlay, or via OpenUPM).
- An Asalyze account with an app API key from the dashboard.

## Install

Unity ▸ Window ▸ Package Manager ▸ **+ ▸ Add package from git URL…**

```
https://github.com/CodematicsInc-MD/Asalyze-iOS-SDK.git?path=/unity#v3.2.0
```

On your next iOS build, EDM4U adds `pod 'Asalyze', '~> 3.2.0'` and runs `pod install` automatically.

The native bridge imports `<Asalyze/Asalyze-Swift.h>`, so the pod must be integrated **as a framework**:
in **Assets ▸ External Dependency Manager ▸ iOS Resolver ▸ Settings**, enable *Add use_frameworks to
Podfile*. Linked statically, the Swift header won't be found at compile time.

## Use

```csharp
public class AsalyzeBootstrap : MonoBehaviour
{
    void Awake()
    {
        Asalyze.Configure(
            apiKey: "sk_…",          // My Apps → your app → SDK API key
            appId:  "com.your.game"
        );
    }
}
```

That is the whole setup. Attribution, purchases and subscriptions are tracked from then on — nothing to
call per purchase.

**If your game shows ads**, report each impression's revenue from your mediation's callback:

```csharp
Asalyze.TrackAdRevenue(valueUsd: 0.012, format: AsalyzeAdFormat.Rewarded, currency: "USD");
```

Optional:

```csharp
Asalyze.TrackEvent("level_5_reached");   // your own events → Goals
Asalyze.SetUserId("player_123");         // your id for a signed-in player
```

## API

| Call | Purpose |
|---|---|
| `Asalyze.Configure(apiKey, appId, endpoint=null)` | Initialize, once at startup |
| `Asalyze.InstallId()` | Stable first-party id, for reconciling with your own analytics |
| `Asalyze.SetUserId(id)` | Your own id for a signed-in player |
| `Asalyze.TrackAdRevenue(valueUsd, format, currency="USD")` | Impression-level ad revenue |
| `Asalyze.TrackEvent(name, valueUsd=null)` | Custom event for Goals |

Subscription lifecycle — renewals, cancellations, expiries and refunds — needs App Store Server
Notifications connected in the dashboard.

---

Built and maintained by [Codematics Services Private Limited](https://asalyze.com). Malik Ahsan Ali — Founder & Managing Director.
