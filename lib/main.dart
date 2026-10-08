import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'config/game_config.dart';
import 'services/ads_service.dart';
import 'services/analytics.dart';
import 'services/feedback.dart';
import 'services/profile_store.dart';
import 'services/purchase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final mobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  final (config, profile, analytics) = await (
    GameConfig.load(),
    ProfileStore.load(),
    LocalAnalytics.load(),
  ).wait;

  final services = AppServices(
    config: config,
    profile: profile,
    audio: AudioService(),
    haptics: HapticsService(),
    ads: mobile ? MobileAdsService() : NoAdsService(),
    purchases: mobile ? StorePurchaseService() : NoPurchaseService(),
    analytics: analytics,
  );
  analytics.log('app_open');

  runApp(HueLockApp(services: services));
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => services.startBackground(),
  );
}
