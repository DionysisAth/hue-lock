import 'dart:io' show Platform;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'config/game_config.dart';
import 'meta/levels.dart';
import 'services/ads_service.dart';
import 'services/analytics.dart';
import 'services/feedback.dart';
import 'services/game_services.dart';
import 'services/notifications.dart';
import 'services/profile_store.dart';
import 'services/purchase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final mobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  final (config, profile, local, levels, firebase) = await (
    GameConfig.load(),
    ProfileStore.load(),
    LocalAnalytics.load(),
    loadLevels(),
    _initFirebase(),
  ).wait;
  final Analytics analytics = firebase == null
      ? local
      : FirebaseEventsAnalytics(local, firebase);

  final services = AppServices(
    config: config,
    profile: profile,
    audio: AudioService(),
    music: MusicService(),
    haptics: HapticsService(),
    ads: mobile ? MobileAdsService() : NoAdsService(),
    purchases: mobile ? StorePurchaseService() : NoPurchaseService(),
    analytics: analytics,
    gameServices: GameServices(),
    reminders: ReminderService(),
    levels: levels,
  );
  analytics.log('app_open');

  runApp(HueLockApp(services: services));
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => services.startBackground(),
  );
}

/// Firebase Analytics, Android only (its config is
/// android/app/google-services.json). Never blocks the game: null if it
/// can't start.
Future<FirebaseAnalytics?> _initFirebase() async {
  if (kIsWeb || !Platform.isAndroid) return null;
  try {
    await Firebase.initializeApp();
    final analytics = FirebaseAnalytics.instance;
    // Usage stats only: nothing from Firebase is used for ads.
    await analytics.setConsent(
      analyticsStorageConsentGranted: true,
      adStorageConsentGranted: false,
      adUserDataConsentGranted: false,
      adPersonalizationSignalsConsentGranted: false,
    );
    return analytics;
  } catch (e) {
    debugPrint('Firebase unavailable: $e');
    return null;
  }
}
