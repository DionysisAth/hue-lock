// Records the gameplay for the promo video from the real app, frame by frame
// at 30 fps (540x1080), plus a log of game events for the sound effects.
// Not part of the normal test run:
//
//   flutter test tool/promo_video_test.dart
//   python3 tool/make_promo_video.py       # -> build/promo/hue-lock-promo.mp4
//
// Frames go to build/promo/frames/, the log to build/promo/events.json.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_lock/app.dart';
import 'package:hue_lock/core/angles.dart';
import 'package:hue_lock/game/game_engine.dart';
import 'package:hue_lock/game/hit_judge.dart';
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
const _ratio = 1.35; // 540 x 1080
const _out = 'build/promo';
const _frame = Duration(microseconds: 33333); // 30 fps

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

  await load('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]);
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
  ..achievements.addAll(achievementDefs.map((a) => a.id))
  ..levelStars = {
    for (var i = 1; i <= 9; i++) 'L$i': i % 4 == 0 ? 2 : 3,
    'L10': 1,
  };

void main() {
  final shotKey = GlobalKey();
  var frameNo = 0;
  final events = <Map<String, Object>>[];
  final scenes = <Map<String, Object>>[];
  var recording = false;

  setUpAll(() async {
    await _loadFonts();
    final dir = Directory('$_out/frames');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
  });

  tearDownAll(() {
    File('$_out/events.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert({
        'fps': 30,
        'frames': frameNo,
        'events': events,
        'scenes': scenes,
      }),
    );
  });

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = _logical * _ratio;
    tester.view.devicePixelRatio = _ratio;
    addTearDown(tester.view.reset);
    final services = AppServices(
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

  GameEngine engine(WidgetTester tester) =>
      (tester.state(find.byType(GameScreen)) as dynamic).engine as GameEngine;

  /// Logs the engine's events (with the frame they land on) for the sound.
  void listen(GameEngine e) {
    final screen = e.onEvent;
    e.onEvent = (ev) {
      screen?.call(ev);
      String? sfx;
      switch (ev) {
        case HitEvent(:final judgement, :final perfectStreak):
          sfx = judgement.kind == HitKind.perfect
              ? 'perfect_${(perfectStreak - 1).clamp(0, 7)}'
              : 'hit';
        case ComboUpEvent():
          sfx = 'combo_up';
        case StreakEvent():
          sfx = 'streak';
        case FeverEvent(:final active):
          if (active) sfx = 'fever';
        case FocusEvent(:final active):
          if (active) sfx = 'focus';
        case BossEvent(:final cleared):
          sfx = cleared ? 'stage' : 'boss';
        case MissEvent():
          sfx = 'fail';
        case NewBestEvent():
          sfx = 'new_best';
        case PowerUpEvent():
          sfx = 'power_up';
        default:
          break;
      }
      if (sfx != null && recording) {
        events.add({'frame': frameNo, 'sfx': sfx});
      }
    };
  }

  /// One video frame: advance the clock 1/30 s and save the picture.
  Future<void> frame(WidgetTester tester, {bool record = true}) async {
    recording = record;
    await tester.pump(_frame);
    if (!record) return;
    await tester.runAsync(() async {
      final boundary =
          shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: _ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final name = frameNo.toString().padLeft(5, '0');
      File('$_out/frames/$name.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
    });
    frameNo++;
  }

  Future<void> hold(
    WidgetTester tester,
    double seconds, {
    bool record = true,
  }) async {
    for (var i = 0; i < (seconds * 30).round(); i++) {
      await frame(tester, record: record);
    }
  }

  void scene(String id) => scenes.add({'id': id, 'frame': frameNo});

  /// Starts an endless run with a fixed seed from the home screen.
  Future<GameEngine> run(
    WidgetTester tester,
    int seed, {
    int best = 248,
  }) async {
    await tester.tapAt(const Offset(200, 330));
    await tester.pump(const Duration(milliseconds: 16));
    final e = engine(tester);
    listen(e);
    e.startRun(best: best, seed: seed);
    await tester.pump(const Duration(milliseconds: 16));
    return e;
  }

  /// Plays until the pointer is on the target's center, then taps.
  Future<void> perfect(
    WidgetTester tester,
    GameEngine e, {
    bool record = true,
  }) async {
    if (e.phase == GamePhase.perk) {
      await hold(tester, 0.6, record: record);
      e.choosePerk(e.perkOffer!.first);
    }
    var guard = 0;
    while (e.phase == GamePhase.countdown && guard++ < 600) {
      await frame(tester, record: record);
    }
    while (timeUntil(e, e.round!.currentPrimary.center) > 0.034) {
      await frame(tester, record: record);
    }
    e.tap(e.time + timeUntil(e, e.round!.currentPrimary.center));
    await frame(tester, record: record);
  }

  testWidgets('1 home and a perfect streak into Fever', (tester) async {
    await start(tester);
    scene('home');
    await hold(tester, 2.6);
    final e = await run(tester, 31);
    for (var i = 0; i < 3; i++) {
      await perfect(tester, e, record: false);
    }
    scene('streak');
    for (var i = 0; i < 8; i++) {
      await perfect(tester, e);
    }
    await hold(tester, 0.7);
  });

  testWidgets('2 boss round', (tester) async {
    await start(tester);
    final e = await run(tester, 5);
    var guard = 0;
    while (e.round!.spec.kind != RoundKind.boss && guard++ < 80) {
      await perfect(tester, e, record: false);
    }
    scene('boss');
    final boss = e.round;
    guard = 0;
    while (identical(e.round, boss) &&
        e.phase != GamePhase.perk &&
        guard++ < 12) {
      await perfect(tester, e);
    }
    scene('perks');
    await hold(tester, 1.8);
    e.choosePerk(e.perkOffer!.first);
    await hold(tester, 0.5);
  });

  testWidgets('3 hold zone and Focus', (tester) async {
    await start(tester);
    final e = await run(tester, 21);
    var guard = 0;
    while (!e.round!.currentPrimary.hold && guard++ < 80) {
      await perfect(tester, e, record: false);
    }
    scene('hold');
    while (e.phase == GamePhase.countdown) {
      await frame(tester);
    }
    await hold(tester, 0.3);
    final r = e.round!;
    final z = r.currentPrimary;
    final press = wrapAngle(z.center - r.spec.pointerDir * z.halfWidth * 0.85);
    while (timeUntil(e, press) > 0.034) {
      await frame(tester);
    }
    e.tap(e.time + timeUntil(e, press));
    e.focus = 0.9;
    e.toggleFocus();
    final end = wrapAngle(z.center + r.spec.pointerDir * z.halfWidth);
    while (timeUntil(e, end) > 0.034 && r.holding) {
      await frame(tester);
    }
    if (r.holding) e.release(e.time + timeUntil(e, end));
    await hold(tester, 1.0);
  });

  testWidgets('4 NOT round', (tester) async {
    await start(tester);
    final e = await run(tester, 11);
    var guard = 0;
    while (e.round!.spec.kind != RoundKind.inverted && guard++ < 80) {
      await perfect(tester, e, record: false);
    }
    scene('not');
    await perfect(tester, e);
    await hold(tester, 1.4);
  });

  testWidgets('5 levels map', (tester) async {
    await start(tester);
    scene('levels');
    await tester.tap(find.text('LEVELS'));
    await hold(tester, 2.6);
  });

  testWidgets('6 new best', (tester) async {
    await start(tester);
    final e = await run(tester, 77, best: 120);
    for (var i = 0; i < 40; i++) {
      await perfect(tester, e, record: false);
    }
    scene('best');
    for (var i = 0; i < 3; i++) {
      await perfect(tester, e);
    }
    e.shield = false;
    while (e.phase == GamePhase.countdown) {
      await frame(tester);
    }
    final t = e.round!.currentPrimary;
    final far = t.center + e.round!.spec.pointerDir * t.halfWidth;
    while (timeUntil(e, far) > 0.034) {
      await frame(tester);
    }
    e.tap(e.time + timeUntil(e, far) + 0.07);
    await hold(tester, 3.0);
  });
}
