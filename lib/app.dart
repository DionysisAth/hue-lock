import 'package:flutter/material.dart';

import 'config/game_config.dart';
import 'meta/levels.dart';
import 'services/ads_service.dart';
import 'services/analytics.dart';
import 'services/feedback.dart';
import 'services/game_services.dart';
import 'services/notifications.dart';
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
    GameServices? gameServices,
    ReminderService? reminders,
    this.levels = const [],
    this.warmUpEffects = true,
  }) : gameServices = gameServices ?? GameServices(enabled: false),
       reminders = reminders ?? ReminderService(enabled: false) {
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

  /// Play Games / Game Center (off until configured, see GameServiceIds).
  final GameServices gameServices;
  final ReminderService reminders;

  /// Levels mode content (assets/config/levels.json).
  final List<LevelDef> levels;

  /// Pre-render effects at startup to compile shaders (off in tests).
  final bool warmUpEffects;

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

  /// Signs in to Play Games / Game Center and merges the cloud save.
  Future<void> _syncCloud() async {
    if (!gameServices.enabled) return;
    await gameServices.signIn();
    final remote = await gameServices.loadProfile();
    if (remote != null) profile.update((p) => p.mergeFrom(remote));
  }

  /// Non-critical startup work, run after the first frame so the game is
  /// playable immediately.
  Future<void> startBackground() async {
    await Future.wait([
      audio.init(),
      music.init(),
      purchases.init(
        onEntitled: (id) {
          final p = profile.profile;
          switch (id) {
            case Products.removeAds:
              if (p.adsRemoved) return;
              profile.update((p) => p.adsRemoved = true);
            case Products.starterPack:
              // Restores must not grant the coins / tokens twice.
              if (p.starterPack) return;
              profile.update((p) {
                p.starterPack = true;
                p.adsRemoved = true;
                p.coins += 1000;
                p.tokens += 5;
                p.ownedBalls.add('crown');
              });
            case Products.tokens5:
              profile.update((p) => p.tokens += 5);
            default:
              return;
          }
          analytics.log('purchase', {'product': id});
        },
      ),
      reminders.init(),
      _syncCloud(),
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
