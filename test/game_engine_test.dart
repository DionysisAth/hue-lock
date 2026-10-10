import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_lock/core/angles.dart';
import 'package:hue_lock/game/effects.dart';
import 'package:hue_lock/game/game_engine.dart';
import 'package:hue_lock/game/hit_judge.dart';
import 'package:hue_lock/game/round.dart';
import 'package:hue_lock/services/ads_service.dart';
import 'package:hue_lock/services/profile_store.dart';

import 'test_helpers.dart';

void main() {
  final config = loadTestConfig();

  /// A returning player (every mechanic already explained) unless [fresh].
  GameEngine newEngine(List<GameEvent> events, {bool fresh = false}) {
    final e = GameEngine(config)..onEvent = events.add;
    if (!fresh) e.seen.addAll(intros.keys);
    return e;
  }

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
    expect(e.multiplier, config.scoring.maxMultiplier);
    expect(e.bestMultiplier, config.scoring.maxMultiplier);
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

  test('the combo climbs every 3 Perfects, never speeds the pointer up, and '
      'a Good resets it', () {
    final events = <GameEvent>[];
    final e = newEngine(events)..startRun(best: 0, seed: 2);
    final plain = newEngine([])..startRun(best: 0, seed: 2);
    final step = config.scoring.perfectsPerMultiplierStep;
    for (var i = 0; i < step * 3; i++) {
      tapTargetCenter(e);
      tapTargetCenter(plain);
    }
    expect(e.multiplier, 4);
    // No Fever: a long Perfect streak plays at the normal speed.
    expect(e.round!.spec.pointerSpeed, plain.round!.spec.pointerSpeed);

    final before = e.score;
    tapTargetCenter(e);
    final last = events.whereType<HitEvent>().last;
    expect(last.points, config.scoring.perfectPoints * e.multiplier);
    expect(e.score - before, greaterThanOrEqualTo(last.points));

    // A Good (near the far edge) resets the combo.
    waitUntilPlaying(e);
    final t = e.round!.currentPrimary;
    final edge = wrapAngle(
      t.center + e.round!.spec.pointerDir * t.halfWidth * 0.9,
    );
    e.tap(e.time + timeUntil(e, edge));
    expect(e.multiplier, 1);
    expect(e.perfectStreak, 0);
    expect(e.bestMultiplier, 4);
    expect(events.whereType<HitEvent>().last.points, config.scoring.goodPoints);
  });

  test('Perfects hit harder: effects, combo and streak events', () {
    final events = <GameEvent>[];
    final e = newEngine(events)..startRun(best: 0, seed: 12);
    // Tap right now, on a frame where the pointer is on the center.
    advance(e, timeUntil(e, e.round!.currentPrimary.center));
    expect(e.tap(e.time)!.kind, HitKind.perfect);
    // Shards, shockwaves, camera punch.
    expect(e.effects.zoom, 1);
    expect(e.effects.waves, isNotEmpty);
    expect(
      e.effects.particles.where((p) => p.shape == ParticleShape.shard),
      isNotEmpty,
    );
    // No hit-stop: the pointer keeps moving on the very next frame.
    final a = e.pointerAngle();
    advance(e, 1 / 60);
    expect(e.phase, GamePhase.playing);
    expect(e.pointerAngle(), isNot(closeTo(a, 1e-6)));
    // Combo up at 3 Perfects, along with the first streak word.
    tapTargetCenter(e);
    tapTargetCenter(e);
    expect(events.whereType<ComboUpEvent>().single.multiplier, 2);
    expect(events.whereType<StreakEvent>().single.word, streakWords[3]);
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
    // Not dead: a short frozen pause, then play goes on.
    expect(e.phase, GamePhase.countdown);
    expect(e.showCountdownNumber, isFalse);
    final pointer = e.pointerAngle();
    advance(e, config.announce.shield * 0.8);
    expect(e.pointerAngle(), closeTo(pointer, 1e-9));
    waitUntilPlaying(e);
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

  test('boss rounds: intro, then one color at a time, then GO', () {
    final events = <GameEvent>[];
    final e = newEngine(events)..startRun(best: 0, seed: 7);
    clearRounds(e, config.boss.every);
    final b = config.boss;
    expect(e.round!.spec.kind, RoundKind.boss);
    expect(e.bossPreview, isTrue);
    expect(e.showCountdownNumber, isFalse);
    // Intro: banner only, no color yet.
    expect(e.bossPreviewIndex, -1);
    final pointer = e.pointerAngle();
    advance(e, b.intro + 0.1);
    expect(e.bossPreviewIndex, 0);
    // Gap between colors.
    advance(e, b.previewPerColor);
    expect(e.bossPreviewIndex, -1);
    advance(e, b.previewGap);
    expect(e.bossPreviewIndex, 1);
    expect(e.pointerAngle(), closeTo(pointer, 1e-9), reason: 'frozen');
    // After the last color: a "GO" pause before the pointer moves.
    final n = e.round!.spec.ballColors.length;
    advance(e, (n - 1) * (b.previewPerColor + b.previewGap));
    expect(e.bossPreview, isTrue);
    expect(e.bossPreviewIndex, -1);
    expect(e.effects.banner?.title, 'GO!');
    expect(e.pointerAngle(), closeTo(pointer, 1e-9));
    // Hitting the right colors in order clears it.
    for (var i = 0; i < n; i++) {
      tapTargetCenter(e);
    }
    expect(events.whereType<BossEvent>().where((b) => b.cleared), hasLength(1));
    expect(e.level, config.boss.every + 1);
  });

  test('the very first boss gets a longer intro', () {
    final e = newEngine([])..seen.remove('boss');
    e.startRun(best: 0, seed: 7);
    clearRounds(e, config.boss.every);
    advance(e, config.boss.intro + 0.1);
    expect(e.bossPreviewIndex, -1, reason: 'still reading the explanation');
    advance(e, 1.0);
    expect(e.bossPreviewIndex, 0);
    expect(e.seen, contains('boss'));
  });

  group('announcements', () {
    test('a first-ever run starts playing under an explanation banner', () {
      final events = <GameEvent>[];
      final e = newEngine(events, fresh: true)..startRun(best: 0, seed: 9);
      expect(e.phase, GamePhase.playing, reason: 'no first-time freeze');
      expect(e.effects.banner?.title, intros['intro']!.$1);
      expect(events.whereType<IntroSeenEvent>().map((x) => x.name), ['intro']);
      final pointer = e.pointerAngle();
      advance(e, 0.1);
      expect(e.pointerAngle(), isNot(closeTo(pointer, 1e-6)));
    });

    test('a returning player starts right away', () {
      final e = newEngine([])..startRun(best: 0, seed: 9);
      expect(e.phase, GamePhase.playing);
    });

    test('only boss rounds pause; NOT / split get a banner and extra lead', () {
      final events = <GameEvent>[];
      final e = newEngine(events, fresh: true)..startRun(best: 0, seed: 11);
      final rounds = <String, int>{};
      var pauses = 0;
      var bossPauses = 0;
      var fullLead = 0;
      var guard = 0;
      while (e.level < 80 && guard++ < 400) {
        waitUntilPlaying(e);
        tapTargetCenter(e);
        final r = e.round;
        if (r == null || e.phase == GamePhase.dying) break;
        final kind = r.spec.kind;
        if (r.step != 0) continue;
        if (kind == RoundKind.boss) {
          if (e.phase == GamePhase.countdown) bossPauses++;
          continue;
        }
        if (e.phase == GamePhase.countdown) pauses++;
        final key = kind == RoundKind.inverted
            ? 'not'
            : kind == RoundKind.split
            ? 'split'
            : null;
        if (key == null) continue;
        rounds[key] = (rounds[key] ?? 0) + 1;
        expect(e.effects.banner?.title, intros[key]!.$1);
        // The target starts far enough ahead to read the new rule: the
        // full rule-change lead when it fits in the lap at this speed,
        // never less than the normal reaction time.
        final z = r.currentPrimary;
        final nearEdge = wrapAngle(z.center - r.spec.pointerDir * z.halfWidth);
        final lead = r.timeWhenAt(r.startTime, nearEdge) - r.startTime;
        final maxRel = r.spec.maxRelativeSpeed;
        final room = (config.zone.maxLeadFraction * tau - z.width) / maxRel;
        final need = math.max(
          config.timing.minReaction,
          math.min(config.timing.ruleChangeLead, room),
        );
        expect(
          lead,
          greaterThanOrEqualTo(need - 1e-3),
          reason: '$key round at level ${e.level}',
        );
        if (lead >= config.timing.ruleChangeLead - 1e-3) fullLead++;
      }
      expect(events.whereType<MissEvent>(), isEmpty);
      expect(rounds['not'], greaterThan(1));
      expect(rounds['split'], greaterThan(1));
      expect(pauses, 0, reason: 'only boss rounds freeze the run');
      expect(bossPauses, greaterThan(0));
      expect(
        fullLead,
        greaterThan((rounds['not']! + rounds['split']!) ~/ 2),
        reason: 'most rule changes get the full extra lead',
      );
      final introduced = events.whereType<IntroSeenEvent>().map((x) => x.name);
      expect(
        introduced.toSet(),
        containsAll(['intro', 'not', 'reverse', 'boss', 'split']),
      );
      expect(introduced.length, introduced.toSet().length, reason: 'once');
    });
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
