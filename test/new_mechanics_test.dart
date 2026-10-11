import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_lock/core/angles.dart';
import 'package:hue_lock/game/game_engine.dart';
import 'package:hue_lock/game/hit_judge.dart';
import 'package:hue_lock/meta/levels.dart';

import 'test_helpers.dart';

void main() {
  final config = loadTestConfig();
  final levels = parseLevels(
    File('assets/config/levels.json').readAsStringSync(),
  );

  GameEngine newEngine(List<GameEvent> events) => GameEngine(config)
    ..onEvent = events.add
    ..seen.addAll(intros.keys);

  group('Focus', () {
    test('Perfects fill the meter; Focus slows the game clock, then runs '
        'out', () {
      final events = <GameEvent>[];
      final e = newEngine(events)..startRun(best: 0, seed: 3);
      e.toggleFocus();
      expect(e.focusActive, isFalse, reason: 'empty meter');
      tapTargetCenter(e);
      tapTargetCenter(e);
      expect(e.focus, closeTo(2 * config.focus.perPerfect, 1e-9));
      waitUntilPlaying(e);
      // The round starts at the last tap's timestamp; let it begin.
      while (e.time <= e.round!.startTime + 0.01) {
        e.tick(1 / 60);
      }
      e.toggleFocus();
      expect(e.focusActive, isTrue);
      expect(e.focusUses, 1);
      expect(events.whereType<FocusEvent>().single.active, isTrue);

      // Real time moves the game clock by the time scale only.
      final before = e.time;
      final pointer = e.pointerAngle();
      e.tick(0.1);
      expect(e.time - before, closeTo(0.1 * config.focus.timeScale, 1e-9));
      expect(e.pointerAngle(), isNot(closeTo(pointer, 1e-9)));

      // The meter drains in real time and Focus stops by itself.
      advance(e, 5);
      expect(e.focusActive, isFalse);
      expect(e.focus, 0);
      expect(e.timeScale, 1);
    });

    test('tapping the button again stops it; Levels can switch it off', () {
      final e = newEngine([])..startRun(best: 0, seed: 3);
      for (var i = 0; i < 3; i++) {
        tapTargetCenter(e);
      }
      waitUntilPlaying(e);
      e.toggleFocus();
      final left = e.focus;
      e.toggleFocus();
      expect(e.focusActive, isFalse);
      expect(e.focus, left, reason: 'stopping early keeps the rest');

      final off = newEngine([])
        ..startRun(best: 0, seed: 3, mode: RunMode.level, focus: false);
      for (var i = 0; i < 3; i++) {
        tapTargetCenter(off);
      }
      off.toggleFocus();
      expect(off.focus, 0);
      expect(off.focusActive, isFalse);
    });
  });

  group('hold zones', () {
    final lesson = levels.firstWhere((l) => l.title == 'Hold On');

    GameEngine holdRun(List<GameEvent> events) {
      final e = newEngine(events)
        ..startRun(
          best: 0,
          seed: lesson.seed,
          mode: RunMode.level,
          config: lesson.configFrom(config),
          targetRounds: 50,
        );
      // The first round is never a hold round; the next ones are.
      tapTargetCenter(e);
      waitUntilPlaying(e);
      expect(e.round!.currentPrimary.hold, isTrue);
      return e;
    }

    void press(GameEngine e) {
      final r = e.round!;
      final z = r.currentPrimary;
      final at = wrapAngle(z.center - r.spec.pointerDir * z.halfWidth * 0.6);
      e.tap(e.time + timeUntil(e, at));
    }

    test('press, hold, let go on the end mark: Perfect', () {
      final events = <GameEvent>[];
      final e = holdRun(events);
      final hits = events.whereType<HitEvent>().length;
      press(e);
      expect(e.round!.holding, isTrue);
      expect(events.whereType<HoldStartEvent>(), hasLength(1));
      expect(events.whereType<HitEvent>(), hasLength(hits), reason: 'not yet');
      // A second finger does nothing while holding.
      expect(e.tap(e.time), isNull);
      final z = e.round!.currentPrimary;
      final end = wrapAngle(z.center + e.round!.spec.pointerDir * z.halfWidth);
      e.release(e.time + timeUntil(e, end));
      final hit = events.whereType<HitEvent>().last;
      expect(hit.judgement.kind, HitKind.perfect);
      expect(e.holdsCleared, 1);
    });

    test('letting go too soon is a miss', () {
      final events = <GameEvent>[];
      final e = holdRun(events);
      press(e);
      final r = e.round!;
      final z = r.currentPrimary;
      final early = wrapAngle(z.center - r.spec.pointerDir * z.halfWidth * 0.3);
      e.release(e.time + timeUntil(e, early));
      expect(e.phase, GamePhase.dying);
      expect(events.whereType<MissEvent>().single.judgement.letGo, isTrue);
    });

    test('holding past the end still counts, as a Good', () {
      final events = <GameEvent>[];
      final e = holdRun(events);
      press(e);
      final r = e.round!;
      var guard = 0;
      while (r.holding && guard++ < 1000) {
        e.tick(1 / 60);
      }
      final hit = events.whereType<HitEvent>().last;
      expect(hit.judgement.kind, HitKind.good);
      expect(e.phase, isNot(GamePhase.dying));
      expect(e.holdsCleared, 1);
    });

    test('Endless brings hold rounds in after the warm-up stages', () {
      var holds = 0;
      final e = newEngine([])..startRun(best: 0, seed: 9);
      for (var i = 0; i < 80; i++) {
        tapTargetCenter(e);
        if (e.round!.spec.target.hold) {
          holds++;
          expect(e.level, greaterThanOrEqualTo(16));
        }
      }
      expect(holds, greaterThan(0));
      expect(e.phase, isNot(GamePhase.dying));
    });
  });

  group('Rush', () {
    test('a minute on the clock, no bosses; a miss costs time, not the '
        'run', () {
      final events = <GameEvent>[];
      final e = newEngine(events)..startRun(best: 0, mode: RunMode.rush);
      expect(e.rushLeft, config.rush.seconds);
      expect(e.config.boss.every, 0);
      tapTargetCenter(e);
      final afterPerfect = e.rushLeft;
      // Miss on purpose.
      waitUntilPlaying(e);
      final t = e.round!.currentPrimary;
      e.tap(e.time + timeUntil(e, wrapAngle(t.center + tau / 2)));
      expect(events.whereType<RushMissEvent>(), hasLength(1));
      expect(events.whereType<MissEvent>(), isEmpty);
      expect(e.phase, isNot(GamePhase.dying));
      expect(
        e.rushLeft,
        lessThan(afterPerfect - config.rush.missPenalty + 0.5),
      );
    });

    test('when time runs out the run ends and is reported once', () {
      final events = <GameEvent>[];
      final e = newEngine(events)..startRun(best: 0, mode: RunMode.rush);
      var guard = 0;
      while (e.phase != GamePhase.gameOver && guard++ < 2000) {
        tapTargetCenter(e);
        if (e.phase == GamePhase.dying) advance(e, 1);
      }
      expect(e.phase, GamePhase.gameOver);
      final up = events.whereType<TimeUpEvent>().single.summary;
      expect(up.mode, RunMode.rush);
      expect(up.score, greaterThan(0));
      expect(e.canContinue, isFalse);
      e.restart(best: 0);
      expect(events.whereType<RunFinishedEvent>(), hasLength(1));
      expect(e.mode, RunMode.rush);
      expect(e.rushLeft, config.rush.seconds);
    });
  });
}
