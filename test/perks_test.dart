import 'package:flutter_test/flutter_test.dart';
import 'package:hue_lock/core/angles.dart';
import 'package:hue_lock/game/game_engine.dart';
import 'package:hue_lock/game/hit_judge.dart';
import 'package:hue_lock/game/perks.dart';
import 'package:hue_lock/game/round.dart';

import 'test_helpers.dart';

void main() {
  final config = loadTestConfig();

  GameEngine newEngine(List<GameEvent> events) => GameEngine(config)
    ..onEvent = events.add
    ..seen.addAll(intros.keys);

  /// Plays perfectly up to the end of the first boss round (not past the
  /// perk choice).
  void beatFirstBoss(GameEngine e) {
    clearRounds(e, config.boss.every);
    expect(e.round!.spec.kind, RoundKind.boss);
    while (e.phase != GamePhase.perk) {
      tapTargetCenter(e);
    }
  }

  group('perks', () {
    test('beating a boss offers three different perks and waits', () {
      final events = <GameEvent>[];
      final e = newEngine(events)..startRun(best: 0, seed: 11);
      beatFirstBoss(e);
      final offer = e.perkOffer!;
      expect(offer, hasLength(3));
      expect(offer.toSet(), hasLength(3));
      expect(events.whereType<PerkOfferEvent>().single.offer, offer);

      // Frozen while choosing: taps do nothing, the pointer stands still.
      final pointer = e.pointerAngle();
      final level = e.level;
      advance(e, 2);
      expect(e.tap(e.time), isNull);
      expect(e.phase, GamePhase.perk);
      expect(e.pointerAngle(), closeTo(pointer, 1e-9));

      // A perk that wasn't offered is ignored.
      final other = Perk.values.firstWhere((p) => !offer.contains(p));
      e.choosePerk(other);
      expect(e.phase, GamePhase.perk);

      e.choosePerk(offer.first);
      expect(e.perks[offer.first], 1);
      expect(e.perkOffer, isNull);
      expect(e.phase, GamePhase.countdown);
      expect(e.showCountdownNumber, isTrue);
      expect(events.whereType<PerkChosenEvent>().single.perk, offer.first);
      waitUntilPlaying(e);
      expect(e.phase, GamePhase.playing);
      expect(e.level, level);
      expect(e.round!.spec.kind, isNot(RoundKind.boss));
    });

    test('offers are the same for the same seed (Daily, duels)', () {
      final a = newEngine([])..startRun(best: 0, seed: 99, mode: RunMode.daily);
      final b = newEngine([])..startRun(best: 0, seed: 99, mode: RunMode.duel);
      beatFirstBoss(a);
      beatFirstBoss(b);
      expect(a.perkOffer, b.perkOffer);
    });

    test('no perks in Levels or Zen', () {
      final e = newEngine([])
        ..startRun(
          best: 0,
          seed: 3,
          mode: RunMode.level,
          config: loadTestConfig({
            'boss': {'every': 2},
          }),
          targetRounds: 6,
        );
      expect(e.perksEnabled, isFalse);
      clearRounds(e, 4);
      expect(e.bossesCleared, greaterThan(0));
      expect(e.perkOffer, isNull);
      e.startRun(best: 0, mode: RunMode.zen);
      expect(e.perksEnabled, isFalse);
    });

    test('maxed-out perks and a held shield are not offered', () {
      final set = PerkSet();
      for (final p in Perk.values) {
        for (var i = 0; i < p.maxStacks && p != Perk.shield; i++) {
          set.add(p);
        }
      }
      expect(set.offer(1, 1, hasShield: false), [Perk.shield]);
      expect(set.offer(1, 1, hasShield: true), isEmpty);
    });

    test('perks change the run, survive a continue, reset on restart', () {
      final e = newEngine([])..startRun(best: 0, seed: 21);
      e.perks
        ..add(Perk.chill)
        ..add(Perk.wide)
        ..add(Perk.hot)
        ..add(Perk.magnet);
      expect(e.feverGoal, config.fever.perfectStreak - 1);
      clearRounds(e, 3);
      final coins = e.coinsEarned;
      expect(
        coins,
        ((e.score ~/ config.coins.scorePerCoin + e.zoneCoins) * 1.5).round(),
      );

      // Slower pointer, wider zones than the same run without perks.
      final plain = newEngine([])..startRun(best: 0, seed: 21);
      clearRounds(plain, 3);
      expect(
        e.round!.spec.pointerSpeed,
        lessThan(plain.round!.spec.pointerSpeed),
      );
      expect(
        e.round!.spec.target.width,
        greaterThan(plain.round!.spec.target.width),
      );

      // Die, continue: perks stay. Restart: gone.
      waitUntilPlaying(e);
      final target = e.round!.currentPrimary.center;
      e.tap(e.time + timeUntil(e, wrapAngle(target + tau / 2)));
      advance(e, 3);
      expect(e.continueRun(), isTrue);
      expect(e.perks[Perk.chill], 1);
      e.restart(best: 0);
      expect(e.perks.isEmpty, isTrue);
    });

    test('Greed scores more; Steady Hand widens the Perfect window', () {
      final e = newEngine([])..startRun(best: 0, seed: 4);
      e.perks.add(Perk.greed);
      tapTargetCenter(e);
      expect(e.score, (config.scoring.perfectPoints * 1.5).round());

      final z = e.round!.currentPrimary;
      final speed = e.round!.spec.relativeSpeed.abs();
      final normal = perfectHalfWidth(z, config.timing, speed);
      final steady = perfectHalfWidth(z, config.timing, speed, 1.35);
      expect(steady, greaterThan(normal));
      expect(steady, lessThanOrEqualTo(z.halfWidth));
    });
  });

  group('combo', () {
    /// A Good: inside the target but well off its center.
    void tapGood(GameEngine e) {
      waitUntilPlaying(e);
      final z = e.round!.currentPrimary;
      final edge = z.center - e.round!.spec.pointerDir * z.halfWidth * 0.85;
      e.tap(e.time + timeUntil(e, edge));
    }

    test('losing a combo of x3 or more is announced', () {
      final events = <GameEvent>[];
      final e = newEngine(events)..startRun(best: 0, seed: 8);
      for (var i = 0; i < 6; i++) {
        tapTargetCenter(e);
      }
      expect(e.multiplier, 3);
      tapGood(e);
      expect(e.multiplier, 1);
      expect(events.whereType<ComboLostEvent>().single.multiplier, 3);
      expect(e.effects.texts.map((t) => t.text), contains('COMBO LOST'));
    });

    test('Combo Saver: a Good costs one step, and the combo climbs on', () {
      final events = <GameEvent>[];
      final e = newEngine(events)..startRun(best: 0, seed: 8);
      e.perks.add(Perk.keeper);
      for (var i = 0; i < 6; i++) {
        tapTargetCenter(e);
      }
      expect(e.multiplier, 3);
      tapGood(e);
      expect(e.multiplier, 2);
      expect(e.perfectStreak, 0, reason: 'the streak itself still breaks');
      expect(events.whereType<ComboLostEvent>(), isEmpty);
      for (var i = 0; i < 3; i++) {
        tapTargetCenter(e);
      }
      expect(e.multiplier, 3);
    });
  });
}
