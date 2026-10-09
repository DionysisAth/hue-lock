import 'package:flutter/material.dart';

import 'config/game_config.dart';
import 'services/ads_service.dart';
import 'services/analytics.dart';
import 'services/feedback.dart';
import 'services/profile_store.dart';
import 'services/purchase_service.dart';
import 'ui/game_screen.dart';

/// Long-lived app services, created once in `main`.
class AppServices {
  AppServices({
    required this.config,
    required this.profile,
    required this.audio,
    required this.music,
    required this.haptics,
    required this.ads,
    required this.purchases,
    required this.analytics,
  }) {
    profile.addListener(applySettings);
    applySettings();
  }

  final GameConfig config;
  final ProfileStore profile;
  final AudioService audio;
  final MusicService music;
  final HapticsService haptics;
  final AdsService ads;
  final PurchaseService purchases;
  final Analytics analytics;

  late final adPolicy = AdPolicy(config.ads);

  void applySettings() {
    final p = profile.profile;
    audio
      ..muted = !p.sound
      ..volume = p.volume;
    haptics.enabled = p.haptics;
    music
      ..muted = !p.music
      ..volume = p.musicVolume;
  }

  /// Non-critical startup work, run after the first frame so the game is
  /// playable immediately.
  Future<void> startBackground() async {
    await Future.wait([
      audio.init(),
      music.init(),
      purchases.init(
        onEntitled: (id) {
          if (id == Products.removeAds && !profile.profile.adsRemoved) {
            profile.update((p) => p.adsRemoved = true);
            analytics.log('purchase', {'product': id});
          }
        },
      ),
      ads.init(),
    ]);
  }
}

class Services extends InheritedWidget {
  const Services({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Services>()!.services;

  @override
  bool updateShouldNotify(Services old) => old.services != services;
}

class HueLockApp extends StatelessWidget {
  const HueLockApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return Services(
      services: services,
      child: MaterialApp(
        title: 'Hue Lock',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2F8BFF),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const GameScreen(),
      ),
    );
  }
}
