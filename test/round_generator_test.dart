import 'package:flutter_test/flutter_test.dart';
import 'package:hue_lock/core/angles.dart';
import 'package:hue_lock/core/seeded_random.dart';
import 'package:hue_lock/game/round.dart';
import 'package:hue_lock/game/round_generator.dart';

import 'test_helpers.dart';

void main() {
  final config = loadTestConfig();

  test('every generated round is fair, across levels 0-250 and power-ups', () {
    final pos = SeededRandom(99);
    // Normal, Fever, Slow-mo, Wide and Fever + Wide.
    const factors = [
      (1.0, 1.0),
      (1.12, 1.0),
      (0.75, 1.0),
      (1.0, 1.5),
      (1.12, 1.5),
    ];
    final kinds = <RoundKind>{};
    for (var seed = 1; seed <= 40; seed++) {
      final gen = RoundGenerator(config, seed);
      var dir = 1;
      int? prev;
      for (var level = 0; level <= 250; level++) {
        final (speed, size) = factors[(seed + level) % factors.length];
        final pointer = pos.range(0, tau);
        final first = level == 0;
        final spec = gen.next(
          level: level,
          pointerLocal: pointer,
          currentDir: dir,
          previousColor: prev,
          isFirst: first,
          speedFactor: speed,
          sizeFactor: size,
        );
        kinds.add(spec.kind);
        final problems = RoundGenerator.validate(
          config,
          spec,
          pointer,
          isFirst: first,
        );
        expect(
          problems,
          isEmpty,
          reason: 'seed $seed level $level ${spec.kind}',
        );
        dir = spec.pointerDir;
        prev = spec.targetColor;
      }
    }
    expect(kinds, RoundKind.values.toSet(), reason: 'every round kind appears');
  });

  test('same seed produces the same sequence (daily challenge / duels)', () {
    List<String> run(int seed) {
      final gen = RoundGenerator(config, seed);
      final out = <String>[];
      var dir = 1;
      for (var level = 0; level < 120; level++) {
        final s = gen.next(
          level: level,
          pointerLocal: level * 0.37 % tau,
          currentDir: dir,
          isFirst: level == 0,
        );
        dir = s.pointerDir;
        out.add(
          '${s.kind}|${s.ballColors}|${s.pointerDir}|${s.ringSpeed}|'
          '${s.pulseAmplitude}|${s.ghost}|'
          '${s.zones.map((z) => '${z.color}@${z.center}${z.powerUp}').join(',')}',
        );
      }
      return out;
    }

    expect(run(1234), run(1234));
    expect(run(1234), isNot(run(4321)));
  });

  test('mechanics are introduced in the order of the ramp', () {
    final gen = RoundGenerator(config, 77);
    Map<String, int> sample(int level) {
      var colors = 0;
      final counts = <String, int>{};
      void bump(String k) => counts[k] = (counts[k] ?? 0) + 1;
      for (var i = 0; i < 300; i++) {
        final s = gen.next(level: level, pointerLocal: 0, currentDir: 1);
        final distinct = s.zones.where((z) => !z.isBonus).length;
        if (distinct > colors) colors = distinct;
        if (s.pointerDir == -1) bump('reverse');
        if (s.ringSpeed != 0) bump('rotate');
        if (s.zones.any((z) => z.isBonus)) bump('bonus');
        if (s.ghost) bump('ghost');
        if (s.pulseAmplitude > 0) bump('surge');
        bump(s.kind.name);
      }
      return {...counts, 'colors': colors};
    }

    final warmup = sample(3);
    expect(warmup['colors'], 1);
    expect(warmup['normal'], 300);
    expect(warmup.keys, isNot(contains('bonus')));

    final two = sample(8);
    expect(two['colors'], 2);
    expect(two['bonus'], greaterThan(0));
    expect(two['reverse'], isNull);

    expect(sample(14)['reverse'], 300);

    final not = sample(20);
    expect(not['colors'], greaterThanOrEqualTo(3));
    expect(not['inverted'], greaterThan(0));
    expect(not['rotate'], isNull);

    final spin = sample(28);
    expect(spin['rotate'], greaterThan(0));
    expect(spin['ghost'], greaterThan(0));
    expect(spin['split'], isNull);

    expect(sample(36)['split'], greaterThan(0));
    expect(sample(44)['surge'], greaterThan(0));
    expect(sample(25)['boss'], 300, reason: 'boss every 25 levels');
    expect(sample(50)['boss'], 300);
  });

  test('pointer speeds up and zones shrink, with breather rounds', () {
    final d0 = Difficulty.forLevel(config, 0);
    final d30 = Difficulty.forLevel(config, 30);
    final d200 = Difficulty.forLevel(config, 200);
    expect(d30.pointerSpeed, greaterThan(d0.pointerSpeed));
    expect(d30.zoneSize, lessThan(d0.zoneSize));
    expect(d200.pointerSpeed, closeTo(config.pointer.maxSpeed, 1e-9));
    expect(d200.zoneSize, closeTo(config.zone.minSize, 1e-9));

    final period = config.wave.period;
    final breather = period * 3 - 1;
    expect(Difficulty.forLevel(config, breather).isBreather, isTrue);
    expect(
      Difficulty.forLevel(config, breather).pointerSpeed,
      lessThan(Difficulty.forLevel(config, breather - 1).pointerSpeed),
    );
  });

  test('power-ups ride on zones once unlocked', () {
    final gen = RoundGenerator(config, 5);
    var early = 0, later = 0;
    for (var i = 0; i < 400; i++) {
      if (gen.next(level: 2, pointerLocal: 0, currentDir: 1).target.powerUp !=
          null) {
        early++;
      }
      if (gen
          .next(level: 10, pointerLocal: 0, currentDir: 1)
          .zones
          .any((z) => z.powerUp != null)) {
        later++;
      }
    }
    expect(early, 0);
    expect(later, greaterThan(0));
  });
}
