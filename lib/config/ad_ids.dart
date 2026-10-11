/// AdMob ad unit ids: the only place to put them (plus the AdMob *app* ids
/// in android/app/src/main/AndroidManifest.xml and ios/Runner/Info.plist).
///
/// Empty = not set up yet, so Google's test ads are used. Debug builds and
/// builds made with --dart-define=TEST_ADS=true (the downloadable test APK)
/// always use test ads, so tapping your own ads never counts as fraud.
abstract final class AdIds {
  static const androidInterstitial = 'ca-app-pub-1774874652706103/6291309626';
  static const androidRewarded = 'ca-app-pub-1774874652706103/5313269873';
  static const iosInterstitial = '';
  static const iosRewarded = '';
}
