import 'package:flutter_test/flutter_test.dart';
import 'package:hue_lock/core/angles.dart';
import 'package:hue_lock/game/game_engine.dart';
import 'package:hue_lock/game/hit_judge.dart';
import 'package:hue_lock/game/round.dart';
import 'package:hue_lock/services/ads_service.dart';
import 'package:hue_lock/services/profile_store.dart';

import 'test_helpers.dart';

void main() {
  final config = loadTestConfig();

  GameEngine newEngine(List<GameEvent> events) =>
      GameEngine(config)..onEvent = events.add;

  /// Taps opposite the current target: a guaranteed miss.
  void missNow(GameEngine e) {
    waitUntilPlaying(e);
    final t = e.round!.currentPrimary;
    e.tap(e.time + timeUntil(e, wrapAngle(t.center + tau / 2)));
  }

  test('a perfect player clears 150 rounds, bosses and all', () {
    final events = <GameEvent>[];
    final e = newEngine(events)..startRun(best: 0, seed: 1);
    clearRounds(e, 150);
    expect(e.level, 150);
    expect(e.phase, isNot(GamePhase.dying));
    expect(e.fever, isTrue);
    expect(e.multiplier, config.scoring.maxMultiplier);
    expect(events.whereType<MissEvent>(), isEmpty);
    final hits = events.whereType<HitEvent>().toList();
    expect(hits.every((h) => h.judgement.kind == HitKind.perfect), isTrue);
    expect(hits[0].points, config.scoring.perfectPoints);
    expect(hits[2].multiplier, 2);
    // Boss rounds at 25, 50, ... were shown and cleared.
    expect(
      events.whereType<BossEvent>().where((b) => b.cleared),
      // The boss at level 150 has not been played yet.
      hasLength((150 - 1) ~/ config.boss.every),
    );
    expect(events.whereType<SetClearedEvent>(), isNotEmpty);
    expect(e.world, 150 ~/ config.worlds.every);
    expect(events.whereType<WorldEvent>(), hasLength(e.world));
  });

  test('Fever starts after the Perfect streak and ends on a Good', () {
    final events = <GameEvent>[];
    final e = newEngine(events)..startRun(best: 0, seed: 2);
    for (var i = 0; i < config.fever.perfectStreak; i++) {
      tapTargetCenter(e);
    }
    expect(e.fever, isTrue);
    expect(events.whereType<FeverEvent>().single.active, isTrue);

    // Fever doubles the points of the next Perfect.
    final before = e.score;
    tapTargetCenter(e);
    final last = events.whereType<HitEvent>().last;
    expect(
      last.points,
      config.scoring.perfectPoints *
          e.multiplier *
          config.fever.pointsMultiplier,
    );
    expect(e.score - before, greaterThanOrEqualTo(last.points));

    // A Good (near the far edge) ends Fever and the combo.
    waitUntilPlaying(e);
    final t = e.round!.currentPrimary;
    final edge = wrapAngle(
      t.center + e.round!.spec.pointerDir * t.halfWidth * 0.9,
    );
    e.tap(e.time + timeUntil(e, edge));
    expect(e.fever, isFalse);
    expect(e.multiplier, 1);
    expect(e.perfectStreak, 0);
    // That Good was still scored under Fever.
    expect(
      events.whereType<HitEvent>().last.points,
      config.scoring.goodPoints * config.fever.pointsMultiplier,
    );
  });

  test('the fuse burns out if the pointer passes the target', () {
    final events = <GameEvent>[];
    final e = newEngine(events)..startRun(best: 0, seed: 3);
    tapTargetCenter(e);
    // Do nothing for a full lap.
    advance(e, tau / e.round!.spec.minRelativeSpeed + 0.5);
    expect(e.phase, isNot(GamePhase.playing));
    final miss = events.whereType<MissEvent>().single;
    expect(miss.judgement.timeout, isTrue);
  });

  test('a miss freezes, then shows game over; restart is instant', () {
    final events = <GameEvent>[];
    final e = newEngine(events)..startRun(best: 10, seed: 3);
    tapTargetCenter(e);
    missNow(e);
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
    clearRounds(e, 5);
    final score = e.score;
    void die() {
      missNow(e);
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

  test('a shield absorbs one miss', () {
    final events = <GameEvent>[];
    final e = newEngine(events)..startRun(best: 0, seed: 5);
    tapTargetCenter(e);
    e.shield = true;
    missNow(e);
    expect(e.phase, GamePhase.playing);
    expect(e.shield, isFalse);
    expect(events.whereType<ShieldSavedEvent>(), hasLength(1));
    missNow(e);
    expect(e.phase, GamePhase.dying);
  });

  test('slow-mo and wide shape the next rounds', () {
    final e = newEngine([])..startRun(best: 0, seed: 6);
    clearRounds(e, 10);
    final normal = e.round!.spec;
    e.slowRounds = 3;
    e.wideRounds = 3;
    clearRounds(e, 1);
    final boosted = e.round!.spec;
    expect(boosted.pointerSpeed, lessThan(normal.pointerSpeed));
    expect(boosted.target.width, greaterThan(normal.target.width * 1.1));
    expect(e.slowRounds, 2);
  });

  test('boss rounds preview the sequence with the round frozen', () {
    final events = <GameEvent>[];
    final e = newEngine(events)..startRun(best: 0, seed: 7);
    clearRounds(e, config.boss.every);
    expect(e.round!.spec.kind, RoundKind.boss);
    expect(e.bossPreview, isTrue);
    expect(e.bossPreviewIndex, 0);
    final pointer = e.pointerAngle();
    advance(e, config.boss.previewPerColor * 1.5);
    expect(e.bossPreviewIndex, 1);
    expect(e.pointerAngle(), closeTo(pointer, 1e-9));
    // Hitting the right colors in order clears it.
    final steps = e.round!.spec.steps.length;
    for (var i = 0; i < steps; i++) {
      tapTargetCenter(e);
    }
    expect(events.whereType<BossEvent>().where((b) => b.cleared), hasLength(1));
    expect(e.level, config.boss.every + 1);
  });

  test('a boss round punishes the wrong order', () {
    final e = newEngine([])..startRun(best: 0, seed: 8);
    clearRounds(e, config.boss.every);
    waitUntilPlaying(e);
    e.shield = false; // in case one was collected on the way
    final spec = e.round!.spec;
    final wrong = spec.zones[spec.steps[1].primary];
    e.tap(e.time + timeUntil(e, wrong.center));
    expect(e.phase, GamePhase.dying);
  });

  test('new best is announced once, only when beating a previous best', () {
    final events = <GameEvent>[];
    final e = newEngine(events)..startRun(best: 5, seed: 5);
    clearRounds(e, 6);
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
    // Render a frame past the target, but the tap happened on center.
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
