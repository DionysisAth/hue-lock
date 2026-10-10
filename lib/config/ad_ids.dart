/// AdMob ad unit ids: the only place to put them (plus the AdMob *app* ids
/// in android/app/src/main/AndroidManifest.xml and ios/Runner/Info.plist).
///
/// Empty = not set up yet, so Google's test ads are used. Debug builds and
/// builds made with --dart-define=TEST_ADS=true (the downloadable test APK)
/// always use test ads, so tapping your own ads never counts as fraud.
abstract final class AdIds {
  static const androidInterstitial = '';
  static const androidRewarded = '';
  static const iosInterstitial = '';
  static const iosRewarded = '';
}
