// Renders the store screenshots from the real app (real fonts, real game
// engine) at 1080x2160. Not part of the normal test run:
//
//   flutter test tool/store_screenshots_test.dart
//   python3 tool/frame_screenshots.py      # adds captions -> docs/store/
//
// Raw captures go to build/screenshots/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_lock/app.dart';
import 'package:hue_lock/game/game_engine.dart';
import 'package:hue_lock/game/round.dart';
import 'package:hue_lock/meta/levels.dart';
import 'package:hue_lock/meta/progression.dart';
import 'package:hue_lock/render/text_sprites.dart';
import 'package:hue_lock/services/ads_service.dart';
import 'package:hue_lock/services/analytics.dart';
import 'package:hue_lock/services/feedback.dart';
import 'package:hue_lock/services/profile_store.dart';
import 'package:hue_lock/services/purchase_service.dart';
import 'package:hue_lock/ui/game_screen.dart';

import '../test/test_helpers.dart';

const _logical = Size(400, 800);
const _ratio = 2.7; // 1080 x 2160
const _out = 'build/screenshots';

Future<void> _loadFonts() async {
  final sdk = File(Platform.resolvedExecutable).parent.parent.parent.parent;
  final fonts = '${sdk.path}/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('$fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  const roboto = [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ];
  await load('Roboto', roboto);
  TextSprites.fontFamily = 'Roboto';
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

PlayerProfile _profile() => PlayerProfile()
  ..bestScore = 248
  ..coins = 1340
  ..tokens = 3
  ..xp = 2600
  ..rewardedLevel = 99
  ..totalRuns = 40
  ..lastRewardDay = dayKey(DateTime.now())
  ..seenIntros.addAll(intros.keys)
  ..levelStars = {
    for (var i = 1; i <= 9; i++) 'L$i': i % 4 == 0 ? 2 : 3,
    'L10': 1,
  }
  ..chapterRewards = {'C1', 'C1*', 'C2', 'C3'}
  ..missions = [
    Mission(MissionType.perfects, 75, 80, progress: 58).toJson(),
    Mission(MissionType.bosses, 2, 80).toJson(),
    Mission(MissionType.runs, 9, 80, progress: 4).toJson(),
  ];

void main() {
  final shotKey = GlobalKey();
  late AppServices services;

  setUpAll(() async {
    await _loadFonts();
    Directory(_out).createSync(recursive: true);
  });

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = _logical * _ratio;
    tester.view.devicePixelRatio = _ratio;
    addTearDown(tester.view.reset);
    services = AppServices(
      config: loadTestConfig(),
      profile: ProfileStore.memory(_profile()),
      audio: AudioService(enabled: false),
      music: MusicService(enabled: false),
      haptics: HapticsService()..enabled = false,
      ads: NoAdsService(),
      purchases: NoPurchaseService(),
      analytics: NoAnalytics(),
      levels: parseLevels(File('assets/config/levels.json').readAsStringSync()),
      warmUpEffects: false,
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: shotKey,
        child: HueLockApp(services: services),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(() async {
      final boundary =
          shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: _ratio);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      image.dispose();
    });
  }

  GameEngine engine(WidgetTester tester) =>
      (tester.state(find.byType(GameScreen)) as dynamic).engine as GameEngine;

  /// Starts an endless run with a fixed seed.
  Future<GameEngine> run(WidgetTester tester, int seed) async {
    await tester.tapAt(const Offset(200, 330));
    await tester.pump(const Duration(milliseconds: 16));
    final e = engine(tester);
    e.startRun(best: 248, seed: seed);
    await tester.pump(const Duration(milliseconds: 16));
    return e;
  }

  /// One perfectly timed tap through real frames.
  Future<void> perfect(WidgetTester tester, GameEngine e) async {
    if (e.phase == GamePhase.perk) {
      await tester.pump(const Duration(milliseconds: 500));
      e.choosePerk(e.perkOffer!.first);
    }
    var guard = 0;
    while (e.phase == GamePhase.countdown && guard++ < 400) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final wait = timeUntil(e, e.round!.currentPrimary.center);
    var left = wait - 0.004;
    while (left > 0.017) {
      await tester.pump(const Duration(milliseconds: 16));
      left = timeUntil(e, e.round!.currentPrimary.center) - 0.004;
    }
    e.tap(e.time + timeUntil(e, e.round!.currentPrimary.center));
  }

  testWidgets('1 home', (tester) async {
    await start(tester);
    await tester.pump(const Duration(milliseconds: 900));
    await shoot(tester, '1_home');
  });

  testWidgets('2 perfect streak', (tester) async {
    await start(tester);
    final e = await run(tester, 31);
    for (var i = 0; i < 12; i++) {
      await perfect(tester, e);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 90));
    await shoot(tester, '2_perfect');
  });

  testWidgets('3 NOT round', (tester) async {
    await start(tester);
    final e = await run(tester, 11);
    var guard = 0;
    while (e.round!.spec.kind != RoundKind.inverted && guard++ < 80) {
      await perfect(tester, e);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 220));
    await shoot(tester, '3_not');
  });

  testWidgets('4 boss', (tester) async {
    await start(tester);
    final e = await run(tester, 5);
    var guard = 0;
    while (e.round!.spec.kind != RoundKind.boss && guard++ < 80) {
      await perfect(tester, e);
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Into the color preview.
    guard = 0;
    while (e.bossPreviewIndex < 0 && guard++ < 400) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await shoot(tester, '4_boss');
  });

  testWidgets('5 levels', (tester) async {
    await start(tester);
    await tester.tap(find.text('LEVELS'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await shoot(tester, '5_levels');
  });

  testWidgets('7 perks', (tester) async {
    await start(tester);
    final e = await run(tester, 5);
    var guard = 0;
    while (e.phase != GamePhase.perk && guard++ < 120) {
      await perfect(tester, e);
      await tester.pump(const Duration(milliseconds: 16));
    }
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await shoot(tester, '7_perks');
  });

  testWidgets('6 game over', (tester) async {
    await start(tester);
    final e = await run(tester, 77);
    for (var i = 0; i < 46; i++) {
      await perfect(tester, e);
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Miss by a hair: "SO CLOSE!" (no shield to save it).
    e.shield = false;
    var guard = 0;
    while (e.phase == GamePhase.countdown && guard++ < 400) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Late by ~70 ms past the far edge of the target.
    final t = e.round!.currentPrimary;
    final far = t.center + e.round!.spec.pointerDir * t.halfWidth;
    e.tap(e.time + timeUntil(e, far) + 0.07);
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await shoot(tester, '6_game_over');
  });
}
