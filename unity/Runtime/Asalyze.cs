using System.Runtime.InteropServices;
using System.Text;

/// <summary>Ad format for impression-level ad revenue.</summary>
public enum AsalyzeAdFormat { Banner, Interstitial, Rewarded, RewardedInterstitial, Native, AppOpen }

/// <summary>
/// Unity entry point for Asalyze. Call <see cref="Configure"/> once at startup; attribution and
/// purchases (including Unity IAP) are tracked from then on. iOS only — every call is a no-op
/// elsewhere. Report ad revenue with <see cref="TrackAdRevenue"/> from your mediation callback.
/// </summary>
public static class Asalyze
{
#if UNITY_IOS && !UNITY_EDITOR
    [DllImport("__Internal")] private static extern void AsalyzeConfigure(string apiKey, string appId, string endpoint);
    [DllImport("__Internal")] private static extern void AsalyzeInstallId(StringBuilder buffer, int size);
    [DllImport("__Internal")] private static extern void AsalyzeSetUserId(string userId);
    [DllImport("__Internal")] private static extern void AsalyzeTrackAdRevenue(double valueUsd, string format, string currency);
    [DllImport("__Internal")] private static extern void AsalyzeTrackEvent(string name, double valueUsd, bool hasValue);
#endif

    private static string Raw(AsalyzeAdFormat f)
    {
        switch (f)
        {
            case AsalyzeAdFormat.Interstitial: return "interstitial";
            case AsalyzeAdFormat.Rewarded: return "rewarded";
            case AsalyzeAdFormat.RewardedInterstitial: return "rewarded_interstitial";
            case AsalyzeAdFormat.Native: return "native";
            case AsalyzeAdFormat.AppOpen: return "app_open";
            default: return "banner";
        }
    }

    /// <summary>Configure the SDK once, as early as possible (e.g. a bootstrap MonoBehaviour Awake).</summary>
    /// <param name="apiKey">Per-app key from the Asalyze dashboard (My Apps → app → SDK API key).</param>
    /// <param name="appId">Your bundle identifier.</param>
    /// <param name="endpoint">Backend base URL. Leave null for production.</param>
    public static void Configure(string apiKey, string appId, string endpoint = null)
    {
#if UNITY_IOS && !UNITY_EDITOR
        AsalyzeConfigure(apiKey, appId, endpoint ?? "");
#endif
    }

    /// <summary>
    /// The stable first-party install id (no IDFA), or null before Configure / off-iOS.
    ///
    /// Optional — useful for reconciling Asalyze against your own analytics. Attribution needs nothing
    /// from you: purchases and renewals are linked automatically.
    /// </summary>
    public static string InstallId()
    {
#if UNITY_IOS && !UNITY_EDITOR
        var sb = new StringBuilder(64);
        AsalyzeInstallId(sb, sb.Capacity);
        var s = sb.ToString();
        return string.IsNullOrEmpty(s) ? null : s;
#else
        return null;
#endif
    }

    /// <summary>Tag events with your own user id (pass null to clear).</summary>
    public static void SetUserId(string userId)
    {
#if UNITY_IOS && !UNITY_EDITOR
        AsalyzeSetUserId(userId);
#endif
    }

    /// <summary>Report impression-level ad revenue (e.g. from AdMob / LevelPlay paid-event callbacks).</summary>
    public static void TrackAdRevenue(double valueUsd, AsalyzeAdFormat format, string currency = "USD")
    {
#if UNITY_IOS && !UNITY_EDITOR
        AsalyzeTrackAdRevenue(valueUsd, Raw(format), currency);
#endif
    }

    /// <summary>Report a named custom event for Goals (e.g. "tutorial_complete", "level_5_reached").</summary>
    public static void TrackEvent(string name, double? valueUsd = null)
    {
#if UNITY_IOS && !UNITY_EDITOR
        AsalyzeTrackEvent(name, valueUsd ?? 0.0, valueUsd.HasValue);
#endif
    }

}
