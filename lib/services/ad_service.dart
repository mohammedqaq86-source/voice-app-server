import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Manages AdMob Banner and Interstitial ads.
///
/// All methods are safe to call on Flutter Web — they are no-ops on
/// unsupported platforms so the same code compiles for web dev builds.
///
/// PRODUCTION CHECKLIST:
///   1. Set [_isProduction] to true.
///   2. Replace [_prodBannerId] and [_prodInterstitialId] with your real
///      Ad Unit IDs from AdMob.
///   3. Remove or clear [testDeviceIds] in [updateTestDeviceIds].
class AdService {
  // ── Environment toggle ────────────────────────────────────────────────────

  /// Flip to `true` before publishing to the store.
  static const bool _isProduction = false;

  // ── Ad Unit IDs ───────────────────────────────────────────────────────────

  // Official Google test IDs — safe to use during development.
  static const String _testBannerId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _testInterstitialId =
      'ca-app-pub-3940256099942544/1033173712';

  // Replace these with real Ad Unit IDs from your AdMob account.
  static const String _prodBannerId = 'YOUR_BANNER_AD_UNIT_ID';
  static const String _prodInterstitialId = 'YOUR_INTERSTITIAL_AD_UNIT_ID';

  static String get bannerId =>
      _isProduction ? _prodBannerId : _testBannerId;

  static String get interstitialId =>
      _isProduction ? _prodInterstitialId : _testInterstitialId;

  // ── Interstitial state ────────────────────────────────────────────────────

  InterstitialAd? _interstitialAd;
  bool _isLoading = false;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Registers physical test devices so they receive test ads instead of
  /// real ones. Call before [loadInterstitial] during development.
  static void updateTestDeviceIds(List<String> deviceIds) {
    if (kIsWeb || _isProduction || deviceIds.isEmpty) return;
    MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(testDeviceIds: deviceIds),
    );
  }

  /// Preloads an interstitial ad in the background.
  void loadInterstitial() {
    if (kIsWeb || _isLoading || _interstitialAd != null) return;
    _isLoading = true;

    InterstitialAd.load(
      adUnitId: interstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isLoading = false;
        },
        onAdFailedToLoad: (_) {
          _isLoading = false;
        },
      ),
    );
  }

  /// Whether a preloaded interstitial is ready to show.
  bool get isInterstitialReady => !kIsWeb && _interstitialAd != null;

  /// Shows the interstitial ad (if preloaded) and calls [onComplete] after it
  /// closes or fails. Falls through immediately if no ad is ready.
  Future<void> showInterstitialAndThen(VoidCallback onComplete) async {
    if (!isInterstitialReady) {
      onComplete();
      return;
    }

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        onComplete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitialAd = null;
        onComplete();
      },
    );

    await _interstitialAd!.show();
  }

  /// Releases all ad resources. Call from the widget's [dispose].
  void dispose() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
  }
}
