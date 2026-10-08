import 'package:flutter_test/flutter_test.dart';
import 'package:hue_lock/core/angles.dart';
import 'package:hue_lock/game/game_engine.dart';
import 'package:hue_lock/game/hit_judge.dart';
import 'package:hue_lock/services/ads_service.dart';
import 'package:hue_lock/services/profile_store.dart';

import 'test_helpers.dart';

void main() {
  final config = loadTestConfig();

  GameEngine newEngine(List<GameEvent> events) =>
      GameEngine(config)..onEvent = events.add;

  test('a perfect player builds a combo multiplier and keeps going', () {
    final events = <GameEvent>[];
    final e = newEngine(events)..startRun(best: 0, seed: 1);
    for (var i = 0; i < 150; i++) {
      tapTargetCenter(e);
      expect(e.phase, GamePhase.playing, reason: 'round $i');
    }
    expect(e.level, 150);
    expect(e.multiplier, config.scoring.maxMultiplier);
    final hits = events.whereType<HitEvent>().toList();
    expect(hits, hasLength(150));
    expect(hits.every((h) => h.judgement.kind == HitKind.perfect), isTrue);
    // x1, x1, x2 ... capped at max.
    expect(hits[0].points, config.scoring.perfectPoints);
    expect(hits[2].multiplier, 2);
  });

  test('a Good hit resets the combo', () {
    final e = newEngine([])..startRun(best: 0, seed: 2);
    for (var i = 0; i < 6; i++) {
      tapTargetCenter(e);
    }
    expect(e.multiplier, 3);
    // Tap near the far edge of the target: Good.
    final t = e.round!.spec.target;
    final edge = wrapAngle(
      t.center + e.round!.spec.pointerDir * t.halfWidth * 0.9,
    );
    e.tap(e.time + timeUntil(e, edge));
    expect(e.multiplier, 1);
    expect(e.perfectStreak, 0);
    expect(e.score, 3 + 3 + 6 + 6 + 6 + 9 + 1);
  });

  test('a miss freezes, then shows game over; restart is instant', () {
    final events = <GameEvent>[];
    final e = newEngine(events)..startRun(best: 10, seed: 3);
    tapTargetCenter(e);
    // Tap opposite the target: neutral ring.
    final t = e.round!.spec.target;
    e.tap(e.time + timeUntil(e, wrapAngle(t.center + tau / 2)));
    expect(e.phase, GamePhase.dying);
    final miss = events.whereType<MissEvent>().single;
    expect(miss.summary.score, 3);

    advance(e, config.timing.deathFreeze + 0.01);
    expect(e.phase, GamePhase.gameOver);
    expect(events.last, isA<GameOverShown>());

    // Taps during the short lockout are ignored, then restart immediately.
    e.tap(e.time);
    expect(e.phase, GamePhase.gameOver);
    advance(e, config.timing.restartLockout);
    e.tap(e.time);
    expect(e.phase, GamePhase.playing);
    expect(e.score, 0);
  });

  test('continue works once per run and keeps the score', () {
    final events = <GameEvent>[];
    final e = newEngine(events)..startRun(best: 0, seed: 4);
    for (var i = 0; i < 5; i++) {
      tapTargetCenter(e);
    }
    final score = e.score;
    void die() {
      final t = e.round!.spec.target;
      e.tap(e.time + timeUntil(e, wrapAngle(t.center + tau / 2)));
      advance(e, config.timing.deathFreeze + 0.01);
    }

    die();
    expect(e.canContinue, isTrue);
    expect(e.continueRun(), isTrue);
    expect(e.phase, GamePhase.countdown);
    final pointer = e.pointerAngle();
    advance(e, config.timing.continueCountdown * 0.5);
    expect(e.pointerAngle(), closeTo(pointer, 1e-9), reason: 'frozen');
    advance(e, config.timing.continueCountdown * 0.6);
    expect(e.phase, GamePhase.playing);
    expect(e.score, score);

    tapTargetCenter(e);
    expect(e.score, greaterThan(score));
    die();
    expect(e.canContinue, isFalse);
    expect(e.continueRun(), isFalse);

    // Coins are banked per death, never twice.
    final misses = events.whereType<MissEvent>().toList();
    final banked = misses.fold<int>(0, (s, m) => s + m.summary.newCoins);
    expect(banked, misses.last.summary.coinsEarned);
  });

  test('new best is announced once, only when beating a previous best', () {
    final events = <GameEvent>[];
    final e = newEngine(events)..startRun(best: 5, seed: 5);
    for (var i = 0; i < 6; i++) {
      tapTargetCenter(e);
    }
    expect(events.whereType<NewBestEvent>(), hasLength(1));
  });

  test('pausing mid-run freezes the pointer behind a countdown', () {
    final e = newEngine([])..startRun(best: 0, seed: 6);
    advance(e, 0.1);
    e.pause();
    expect(e.phase, GamePhase.countdown);
    final a = e.pointerAngle();
    advance(e, 0.5);
    expect(e.pointerAngle(), closeTo(a, 1e-9));
  });

  test('judging uses the tap timestamp, not the frame time', () {
    final e = newEngine([])..startRun(best: 0, seed: 7);
    final target = e.round!.spec.target;
    final wait = timeUntil(e, target.center);
    // Render a frame well past the target, but the tap happened on center.
    advance(e, wait + 0.03);
    final j = e.tap(e.time - 0.03)!;
    expect(j.kind, HitKind.perfect);
  });

  group('AdPolicy', () {
    final policy = AdPolicy(config.ads);
    PlayerProfile profile(int runs, int since, {bool removed = false}) =>
        PlayerProfile()
          ..totalRuns = runs
          ..runsSinceInterstitial = since
          ..adsRemoved = removed;

    test('no interstitials during the first runs', () {
      expect(policy.shouldShowInterstitial(profile(2, 2)), isFalse);
    });
    test('interstitial every N runs', () {
      expect(policy.shouldShowInterstitial(profile(10, 3)), isFalse);
      expect(policy.shouldShowInterstitial(profile(10, 4)), isTrue);
    });
    test('remove ads disables interstitials', () {
      expect(
        policy.shouldShowInterstitial(profile(10, 9, removed: true)),
        isFalse,
      );
    });
  });
}
