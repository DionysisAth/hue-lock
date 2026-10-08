import 'dart:io';
import 'dart:math' as math;

import 'package:hue_lock/config/game_config.dart';
import 'package:hue_lock/core/angles.dart';
import 'package:hue_lock/game/game_engine.dart';

GameConfig loadTestConfig([Map<String, dynamic>? overrides]) {
  final base = GameConfig.fromJsonString(
    File('assets/config/game_config.json').readAsStringSync(),
  );
  return overrides == null
      ? base
      : GameConfig.fromJson(deepMerge(base.raw, overrides));
}

/// Seconds until the pointer is over [localTarget] in the current round.
double timeUntil(GameEngine engine, double localTarget) {
  final r = engine.round!;
  // A round may start slightly after the last frame (tap timestamps can be
  // newer than the frame clock); the pointer waits at its start until then.
  final now = math.max(engine.time, r.startTime);
  final local = r.localPointerAt(now);
  final rel = r.spec.relativeSpeed;
  return (now - engine.time) +
      travelDistance(local, localTarget, rel.sign.toInt()) / rel.abs();
}

/// Advances the engine in ~60 FPS steps.
void advance(GameEngine engine, double seconds) {
  var left = seconds;
  while (left > 1e-12) {
    final dt = left < 1 / 60 ? left : 1 / 60;
    engine.tick(dt);
    left -= dt;
  }
}

/// Plays one round like a perfect player: taps at the target center.
void tapTargetCenter(GameEngine engine) {
  final target = engine.round!.spec.target;
  final wait = timeUntil(engine, target.center);
  advance(engine, wait * 0.5);
  // Tap timestamped exactly at the center crossing, between frames.
  engine.tap(engine.time + wait * 0.5);
}
