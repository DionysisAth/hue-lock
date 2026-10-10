import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_lock/game/game_engine.dart';
import 'package:hue_lock/game/hit_judge.dart';
import 'package:hue_lock/render/ball_skins.dart';
import 'package:hue_lock/render/game_painter.dart';
import 'package:hue_lock/render/palette.dart';
import 'package:hue_lock/render/ring_themes.dart';
import 'package:hue_lock/render/text_sprites.dart';

import 'test_helpers.dart';

void main() {
  final config = loadTestConfig();

  /// An engine right after a Perfect, with every effect on screen.
  GameEngine afterPerfects(int count) {
    final e = GameEngine(config)..seen.addAll(intros.keys);
    e.startRun(best: 0, seed: 12);
    for (var i = 0; i < count; i++) {
      waitUntilPlaying(e);
      advance(e, timeUntil(e, e.round!.currentPrimary.center));
      expect(e.tap(e.time)!.kind, HitKind.perfect);
    }
    advance(e, 0.06);
    return e;
  }

  Future<ui.Image> render(GameEngine e, RingTheme theme) async {
    const size = Size(400, 860);
    final recorder = ui.PictureRecorder();
    GamePainter(
      engine: e,
      theme: theme,
      skin: ballSkins.first,
      palette: HuePalette.standard,
      colorblind: false,
      repaint: ChangeNotifier(),
      pixelRatio: 1,
    ).paint(Canvas(recorder), size);
    return recorder.endRecording().toImage(400, 860);
  }

  testWidgets('a Perfect frame paints in every theme', (tester) async {
    await tester.runAsync(() async {
      final e = afterPerfects(3); // with a streak word on screen
      expect(e.effects.texts, isNotEmpty);
      expect(e.effects.particles, isNotEmpty);
      for (final theme in ringThemes) {
        final image = await render(e, theme);
        final out = Platform.environment['HUE_LOCK_SHOTS'];
        if (out != null) {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$out/perfect_${theme.id}.png')
              .writeAsBytesSync(png!.buffer.asUint8List());
        }
        image.dispose();
      }
    });
  });

  testWidgets('effect text is rasterized once and reused', (tester) async {
    await tester.runAsync(() async {
      TextSprites.clear();
      final a = TextSprites.get(
        'PERFECT',
        color: Colors.red,
        fontSize: 30,
        glow: 12,
      );
      final b = TextSprites.get(
        'PERFECT',
        color: Colors.red,
        fontSize: 30,
        glow: 12,
      );
      expect(identical(a, b), isTrue);
      expect(a.textWidth, greaterThan(0));
      expect(a.image.width, greaterThan(a.textWidth));
      TextSprites.clear();
    });
  });
}
