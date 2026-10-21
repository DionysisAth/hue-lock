import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'config/game_config.dart';
import 'l10n/l10n.dart';
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

  /// Signs in to Play Games / Game Center, merges the cloud save into this
  /// device's progress (neither side loses anything) and saves the result
  /// back, so every device converges.
  Future<void> syncCloud() async {
    if (!gameServices.enabled) return;
    if (!gameServices.signedIn) await gameServices.signIn();
    if (!gameServices.signedIn) return;
    final remote = await gameServices.loadProfile();
    if (remote != null) profile.update((p) => p.mergeFrom(remote));
    await gameServices.saveProfile(profile.profile);
    await gameServices.refreshRank();
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
      syncCloud(),
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

class HueLockApp extends StatefulWidget {
  const HueLockApp({super.key, required this.services});

  final AppServices services;

  @override
  State<HueLockApp> createState() => _HueLockAppState();
}

class _HueLockAppState extends State<HueLockApp> with WidgetsBindingObserver {
  AppServices get services => widget.services;

  @override
  void initState() {
    super.initState();
    _applyLanguage(rebuild: false);
    services.profile.addListener(_applyLanguage);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    services.profile.removeListener(_applyLanguage);
    super.dispose();
  }

  /// The phone's language changed while the app was open.
  @override
  void didChangeLocales(List<Locale>? locales) => _applyLanguage();

  /// Uses the language picked in Settings, else the phone's own language
  /// (the first one the app supports).
  void _applyLanguage({bool rebuild = true}) {
    final chosen = services.profile.profile.language;
    final code = L10n.languages.containsKey(chosen)
        ? chosen
        : L10n.pick(WidgetsBinding.instance.platformDispatcher.locales);
    if (code == L10n.lang) return;
    L10n.use(code);
    if (!rebuild || !mounted) return;
    setState(() {});
    // Text is looked up while building, so every widget rebuilds once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void mark(Element e) {
        e.markNeedsBuild();
        e.visitChildren(mark);
      }

      (context as Element).visitChildren(mark);
    });
    // The daily reminder's text is fixed when it is scheduled.
    if (services.profile.profile.dailyReminder) {
      services.reminders.setDailyReminder(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Services(
      services: services,
      child: MaterialApp(
        title: 'Hue Lock',
        debugShowCheckedModeBanner: false,
        locale: Locale(L10n.lang),
        supportedLocales: L10n.locales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
