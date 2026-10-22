// Screenshots of the home and Settings screens in a few languages, to eyeball
// translations. Not part of the normal test run:
//
//   flutter test tool/l10n_screens_test.dart   # -> build/l10n/screens/
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_lock/app.dart';
import 'package:hue_lock/game/game_engine.dart';
import 'package:hue_lock/l10n/l10n.dart';
import 'package:hue_lock/meta/levels.dart';
import 'package:hue_lock/render/text_sprites.dart';
import 'package:hue_lock/services/ads_service.dart';
import 'package:hue_lock/services/analytics.dart';
import 'package:hue_lock/services/feedback.dart';
import 'package:hue_lock/services/profile_store.dart';
import 'package:hue_lock/services/purchase_service.dart';

import '../test/test_helpers.dart';

const _langs = ['el', 'de', 'ja', 'ru', 'hi'];

Future<void> _loadFonts() async {
  final sdk = File(Platform.resolvedExecutable).parent.parent.parent.parent;
  final dir = '${sdk.path}/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
        Future.value(ByteData.sublistView(File('$dir/$f').readAsBytesSync())),
      );
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

void main() {
  setUpAll(_loadFonts);
  tearDown(() => L10n.use('en'));

  for (final lang in _langs) {
    testWidgets('$lang screens', (tester) async {
      tester.view.physicalSize = const Size(400, 800) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      final s = AppServices(
        config: loadTestConfig(),
        profile: ProfileStore.memory(
          PlayerProfile()
            ..language = lang
            ..bestScore = 248
            ..coins = 1340
            ..tokens = 3
            ..xp = 2600
            ..seenIntros.addAll(intros.keys),
        ),
        audio: AudioService(enabled: false),
        music: MusicService(enabled: false),
        haptics: HapticsService()..enabled = false,
        ads: NoAdsService(),
        purchases: NoPurchaseService(),
        analytics: NoAnalytics(),
        levels: parseLevels(
          File('assets/config/levels.json').readAsStringSync(),
        ),
        warmUpEffects: false,
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: HueLockApp(services: s),
        ),
      );
      Future<void> shot(String name) async {
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.runAsync(() async {
          final b =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await b.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('build/l10n/screens/${lang}_$name.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync(data!.buffer.asUint8List());
        });
      }

      await shot('home');
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await shot('settings');
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.byIcon(Icons.help_outline_rounded));
      await shot('help');
    });
  }
}
