import 'dart:io' show Platform;
import 'package:flutter/services.dart';

/// Ad formats — mirrors the backend `ad_format` enum.
enum AdFormat { banner, interstitial, rewarded, rewardedInterstitial, native, appOpen }

extension on AdFormat {
  String get raw => const {
        AdFormat.banner: 'banner',
        AdFormat.interstitial: 'interstitial',
        AdFormat.rewarded: 'rewarded',
        AdFormat.rewardedInterstitial: 'rewarded_interstitial',
        AdFormat.native: 'native',
        AdFormat.appOpen: 'app_open',
      }[this]!;
}

/// Flutter entry point for Asalyze (Apple Search Ads ROAS tracking). Delegates to the native iOS SDK
/// over a MethodChannel. On non-iOS platforms every call is a no-op (Apple Search Ads is iOS-only).
class Asalyze {
  static const MethodChannel _channel = MethodChannel('asalyze');

  static bool get _supported => Platform.isIOS;

  /// Configure the SDK once at app startup (as early as possible).
  ///
  /// [apiKey] — the per-app key from the Asalyze dashboard (My Apps → app → SDK API key).
  /// [appId]  — your bundle identifier.
  /// [endpoint] — base URL. Omit for production; pass one only for local or staging testing.
  static Future<void> configure({
    required String apiKey,
    required String appId,
    String? endpoint,
  }) async {
    if (!_supported) return;
    await _channel.invokeMethod('configure', {
      'apiKey': apiKey,
      'appId': appId,
      if (endpoint != null) 'endpoint': endpoint,
    });
  }

  /// The stable first-party install id (no IDFA), or null before configure / on non-iOS.
  ///
  /// Useful for reconciling Asalyze against your own analytics — store it alongside your events and
  /// the two can be joined later. Nothing needs to be done with it for attribution: purchases and
  /// renewals are linked automatically.
  static Future<String?> installId() async {
    if (!_supported) return null;
    return _channel.invokeMethod<String>('installId');
  }

  /// Tag events with your own user id (enables cross-device reconciliation). Pass null to clear.
  static Future<void> setUserId(String? userId) async {
    if (!_supported) return;
    await _channel.invokeMethod('setUserId', {'userId': userId});
  }


  /// Report impression-level ad revenue (e.g. from AdMob's paid-event handler).
  static Future<void> trackAdRevenue({
    required double valueUsd,
    required AdFormat format,
    String currency = 'USD',
  }) async {
    if (!_supported) return;
    await _channel.invokeMethod('trackAdRevenue', {
      'valueUsd': valueUsd,
      'format': format.raw,
      'currency': currency,
    });
  }

  /// Report a named custom event for Goals (e.g. "tutorial_complete", "reached_level_5").
  static Future<void> trackEvent(String name, {double? valueUsd}) async {
    if (!_supported) return;
    await _channel.invokeMethod('trackEvent', {
      'name': name,
      if (valueUsd != null) 'valueUsd': valueUsd,
    });
  }

}
