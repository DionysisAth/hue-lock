import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/ad_ids.dart';
import '../config/game_config.dart';
import 'profile_store.dart';

/// The ad units to load: the real ones from [AdIds] in store builds, and
/// Google's public test units in debug / test builds or until set up.
class AdUnitIds {
  static const _forceTest = bool.fromEnvironment('TEST_ADS');

  static String _pick(String real, String test) =>
      kReleaseMode && !_forceTest && real.isNotEmpty ? real : test;

  static String get interstitial => Platform.isIOS
      ? _pick(AdIds.iosInterstitial, 'ca-app-pub-3940256099942544/4411468910')
      : _pick(
          AdIds.androidInterstitial,
          'ca-app-pub-3940256099942544/1033173712',
        );

  static String get rewarded => Platform.isIOS
      ? _pick(AdIds.iosRewarded, 'ca-app-pub-3940256099942544/1712485313')
      : _pick(AdIds.androidRewarded, 'ca-app-pub-3940256099942544/5224354917');
}

/// When interstitials may show (design doc 11.5). Pure so it can be tested.
class AdPolicy {
  const AdPolicy(this.config);

  final AdsConfig config;

  /// Interstitials are only ever offered on the way back to the home screen,
  /// never between a death and the restart tap.
  bool shouldShowInterstitial(PlayerProfile p) =>
      !p.adsRemoved &&
      p.totalRuns > config.noAdsFirstRuns &&
      p.runsSinceInterstitial >= config.interstitialEveryRuns;
}

abstract class AdsService {
  /// Notifies when ad readiness changes.
  ValueListenable<bool> get rewardedReady;

  Future<void> init();

  /// Shows a rewarded ad; completes with true if the reward was earned.
  Future<bool> showRewarded();

  /// Shows an interstitial if one is loaded; completes once it is closed.
  Future<bool> showInterstitial();

  /// Whether the GDPR/UMP privacy options entry point must be offered.
  bool get privacyOptionsRequired;
  Future<void> showPrivacyOptions();
}

/// Used in tests and on platforms without ads.
class NoAdsService implements AdsService {
  @override
  final ValueNotifier<bool> rewardedReady = ValueNotifier(false);

  @override
  Future<void> init() async {}

  @override
  Future<bool> showRewarded() async => false;

  @override
  Future<bool> showInterstitial() async => false;

  @override
  bool get privacyOptionsRequired => false;

  @override
  Future<void> showPrivacyOptions() async {}
}

/// Google Mobile Ads (AdMob) with UMP consent. Mediation adapters plug in at
/// the AdMob dashboard / native dependency level without code changes here.
class MobileAdsService implements AdsService {
  @override
  final ValueNotifier<bool> rewardedReady = ValueNotifier(false);

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  bool _started = false;
  bool _privacyRequired = false;
  int _interstitialRetry = 0;
  int _rewardedRetry = 0;

  @override
  bool get privacyOptionsRequired => _privacyRequired;

  @override
  Future<void> init() async {
    // GDPR / ATT consent first (UMP shows the ATT prompt when configured in
    // the AdMob "IDFA message"), then start the SDK.
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        await ConsentForm.loadAndShowConsentFormIfRequired((error) {
          if (error != null) debugPrint('Consent form: ${error.message}');
        });
        if (!done.isCompleted) done.complete();
      },
      (error) {
        debugPrint('Consent info update failed: ${error.message}');
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future;
    _privacyRequired =
        await ConsentInformation.instance
            .getPrivacyOptionsRequirementStatus() ==
        PrivacyOptionsRequirementStatus.required;
    if (await ConsentInformation.instance.canRequestAds()) {
      await _start();
    }
  }

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    await MobileAds.instance.initialize();
    _loadInterstitial();
    _loadRewarded();
  }

  void _loadInterstitial() {
    InterstitialAd.load(
      adUnitId: AdUnitIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialRetry = 0;
          _interstitial = ad;
        },
        onAdFailedToLoad: (error) {
          _interstitial = null;
          _retry(++_interstitialRetry, _loadInterstitial);
        },
      ),
    );
  }

  void _loadRewarded() {
    RewardedAd.load(
      adUnitId: AdUnitIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedRetry = 0;
          _rewarded = ad;
          rewardedReady.value = true;
        },
        onAdFailedToLoad: (error) {
          _rewarded = null;
          rewardedReady.value = false;
          _retry(++_rewardedRetry, _loadRewarded);
        },
      ),
    );
  }

  void _retry(int attempt, void Function() load) {
    final seconds = [5, 15, 30, 60, 120][(attempt - 1).clamp(0, 4)];
    Timer(Duration(seconds: seconds), load);
  }

  @override
  Future<bool> showInterstitial() async {
    final ad = _interstitial;
    if (ad == null) return false;
    _interstitial = null;
    final closed = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitial();
        closed.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _loadInterstitial();
        closed.complete(false);
      },
    );
    await ad.show();
    return closed.future;
  }

  @override
  Future<bool> showRewarded() async {
    final ad = _rewarded;
    if (ad == null) return false;
    _rewarded = null;
    rewardedReady.value = false;
    var earned = false;
    final closed = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewarded();
        closed.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _loadRewarded();
        closed.complete(false);
      },
    );
    await ad.show(onUserEarnedReward: (_, _) => earned = true);
    return closed.future;
  }

  @override
  Future<void> showPrivacyOptions() async {
    await ConsentForm.showPrivacyOptionsForm((error) {
      if (error != null) debugPrint('Privacy options: ${error.message}');
    });
    if (await ConsentInformation.instance.canRequestAds()) await _start();
  }
}
