import 'dart:io';

import 'package:hue_lock/config/game_config.dart';
import 'package:hue_lock/game/game_engine.dart';

GameConfig loadTestConfig([Map<String, dynamic>? overrides]) {
  final base = GameConfig.fromJsonString(
    File('assets/config/game_config.json').readAsStringSync(),
  );
  return overrides == null
      ? base
      : GameConfig.fromJson(deepMerge(base.raw, overrides));
}

/// Seconds until the pointer is over [localTarget] in the current round
/// (exact even for surge rounds, where the pointer speed varies).
double timeUntil(GameEngine engine, double localTarget) =>
    engine.round!.timeWhenAt(engine.time, localTarget) - engine.time;

/// Advances the engine in ~60 FPS steps.
void advance(GameEngine engine, double seconds) {
  if (!seconds.isFinite) throw StateError('cannot advance by $seconds');
  var left = seconds;
  while (left > 1e-12) {
    final dt = left < 1 / 60 ? left : 1 / 60;
    engine.tick(dt);
    left -= dt;
  }
}

/// Lets any countdown / boss preview run out.
void waitUntilPlaying(GameEngine engine) {
  var guard = 0;
  while (engine.phase == GamePhase.countdown && guard++ < 1000) {
    engine.tick(1 / 60);
  }
}

/// Plays one step like a perfect player: taps at the center of the current
/// step's target.
void tapTargetCenter(GameEngine engine) {
  waitUntilPlaying(engine);
  final target = engine.round!.currentPrimary;
  advance(engine, timeUntil(engine, target.center) * 0.5);
  // Re-aim after the frames went by (a Perfect's hit-stop shifts the round),
  // then tap timestamped exactly at the center crossing, between frames.
  engine.tap(engine.time + timeUntil(engine, target.center));
}

/// Plays perfect taps until [rounds] more rounds are cleared.
void clearRounds(GameEngine engine, int rounds) {
  final goal = engine.level + rounds;
  var guard = 0;
  while (engine.level < goal && guard++ < rounds * 6) {
    tapTargetCenter(engine);
  }
}
