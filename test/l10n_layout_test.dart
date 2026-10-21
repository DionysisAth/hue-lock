// Every screen in every language on a small phone: no layout overflows.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_lock/app.dart';
import 'package:hue_lock/game/game_engine.dart';
import 'package:hue_lock/l10n/l10n.dart';
import 'package:hue_lock/meta/levels.dart';
import 'package:hue_lock/services/ads_service.dart';
import 'package:hue_lock/services/analytics.dart';
import 'package:hue_lock/services/feedback.dart';
import 'package:hue_lock/services/profile_store.dart';
import 'package:hue_lock/services/purchase_service.dart';
import 'package:hue_lock/ui/game_screen.dart';

import 'test_helpers.dart';

/// Real Roboto metrics (the default test font draws every glyph as a
/// square, far wider than real text).
Future<void> _loadRoboto() async {
  final sdk = File(Platform.resolvedExecutable).parent.parent.parent.parent;
  final dir = '${sdk.path}/artifacts/material_fonts';
  if (!File('$dir/Roboto-Regular.ttf').existsSync()) return;
  final loader = FontLoader('Roboto');
  for (final f in [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
    'Roboto-Black.ttf',
  ]) {
    loader.addFont(
      Future.value(ByteData.sublistView(File('$dir/$f').readAsBytesSync())),
    );
  }
  await loader.load();
}

AppServices _services(String lang) => AppServices(
  config: loadTestConfig(),
  profile: ProfileStore.memory(
    PlayerProfile()
      ..language = lang
      ..bestScore = 1234
      ..coins = 12345
      ..tokens = 3
      ..xp = 4000
      ..seenIntros.addAll(intros.keys),
  ),
  audio: AudioService(enabled: false),
  music: MusicService(enabled: false),
  haptics: HapticsService()..enabled = false,
  ads: NoAdsService(),
  purchases: NoPurchaseService(),
  analytics: NoAnalytics(),
  levels: parseLevels(File('assets/config/levels.json').readAsStringSync()),
  warmUpEffects: false,
);

Future<void> _wait(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(_loadRoboto);
  tearDown(L10n.reset);

  for (final lang in L10n.languages.keys) {
    testWidgets('$lang: every screen fits a small phone', (tester) async {
      tester.view.physicalSize = const Size(360, 720) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final s = _services(lang);
      await tester.pumpWidget(HueLockApp(services: s));
      await _wait(tester, 4);
      expect(L10n.lang, lang);
      final problems = <String>[];
      void check(String where) {
        Object? e;
        while ((e = tester.takeException()) != null) {
          problems.add('$where: $e');
        }
      }

      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      Future<void> visit(String where, IconData icon) async {
        await tester.tap(find.byIcon(icon).first);
        await _wait(tester);
        check(where);
        if (where == 'shop') {
          for (final i in [1, 2]) {
            await tester.tap(find.byType(Tab).at(i));
            await _wait(tester);
            check('shop tab $i');
          }
        }
        nav.pop();
        await _wait(tester);
      }

      check('home');
      await visit('settings', Icons.tune_rounded);
      await visit('shop', Icons.palette_rounded);
      await visit('progress', Icons.emoji_events_rounded);
      await visit('how to play', Icons.help_outline_rounded);
      await visit('levels', Icons.school_rounded);

      // A run: pause menu, then game over.
      final e =
          (tester.state(find.byType(GameScreen)) as dynamic).engine
              as GameEngine;
      e.startRun(best: 1234, seed: 3);
      await _wait(tester, 4);
      check('run');
      e.pauseByPlayer();
      await _wait(tester, 4);
      check('pause');
      e.resume();
      for (var i = 0; i < 200 && e.phase != GamePhase.playing; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      e.tap(e.time); // far from the target: a miss
      for (var i = 0; i < 200 && e.phase != GamePhase.gameOver; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(e.phase, GamePhase.gameOver);
      await _wait(tester, 20);
      check('game over');
      // Let the reward toasts time out.
      await _wait(tester, 160);
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }
}
