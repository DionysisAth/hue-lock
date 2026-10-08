import 'package:flutter_test/flutter_test.dart';
import 'package:hue_lock/core/angles.dart';
import 'package:hue_lock/core/seeded_random.dart';
import 'package:hue_lock/game/round.dart';
import 'package:hue_lock/game/round_generator.dart';

import 'test_helpers.dart';

void main() {
  final config = loadTestConfig();

  test('every generated round is fair, across levels 0-250', () {
    final pos = SeededRandom(99);
    for (var seed = 1; seed <= 40; seed++) {
      final gen = RoundGenerator(config, seed);
      var dir = 1;
      int? prev;
      for (var level = 0; level <= 250; level++) {
        final pointer = pos.range(0, tau);
        final first = level == 0;
        final spec = gen.next(
          level: level,
          pointerLocal: pointer,
          currentDir: dir,
          previousColor: prev,
          isFirst: first,
        );
        final problems = RoundGenerator.validate(
          config,
          spec,
          pointer,
          isFirst: first,
        );
        expect(problems, isEmpty, reason: 'seed $seed level $level');
        dir = spec.pointerDir;
        prev = spec.targetColor;
      }
    }
  });

  test('same seed produces the same sequence (daily challenge / duels)', () {
    List<RoundSpec> run(int seed) {
      final gen = RoundGenerator(config, seed);
      final out = <RoundSpec>[];
      var dir = 1;
      for (var level = 0; level < 120; level++) {
        final s = gen.next(
          level: level,
          pointerLocal: level * 0.37 % tau,
          currentDir: dir,
          isFirst: level == 0,
        );
        dir = s.pointerDir;
        out.add(s);
      }
      return out;
    }

    final a = run(1234), b = run(1234), c = run(4321);
    String key(RoundSpec s) =>
        '${s.targetColor}|${s.pointerDir}|${s.ringSpeed}|'
        '${s.zones.map((z) => '${z.color}@${z.center}').join(',')}';
    expect(a.map(key), b.map(key));
    expect(a.map(key), isNot(c.map(key)));
  });

  test('mechanics are introduced in the order of the design ramp', () {
    final gen = RoundGenerator(config, 77);
    Map<String, Object> sample(int level) {
      var colors = 0, reversals = 0, rotating = 0;
      for (var i = 0; i < 200; i++) {
        final s = gen.next(level: level, pointerLocal: 0, currentDir: 1);
        colors = colors > s.zones.length ? colors : s.zones.length;
        if (s.pointerDir == -1) reversals++;
        if (s.ringSpeed != 0) rotating++;
      }
      return {'colors': colors, 'reversals': reversals, 'rotating': rotating};
    }

    expect(sample(5), {'colors': 1, 'reversals': 0, 'rotating': 0});
    expect(sample(30), {'colors': 2, 'reversals': 0, 'rotating': 0});
    expect(sample(50)['reversals'], 200);
    expect(sample(50)['rotating'], 0);
    expect(sample(70)['colors'], greaterThanOrEqualTo(3));
    expect(sample(90)['rotating'], 200);
  });

  test('pointer speeds up and zones shrink, with breather rounds', () {
    final d0 = Difficulty.forLevel(config, 0);
    final d50 = Difficulty.forLevel(config, 50);
    final d200 = Difficulty.forLevel(config, 200);
    expect(d50.pointerSpeed, greaterThan(d0.pointerSpeed));
    expect(d50.zoneSize, lessThan(d0.zoneSize));
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
}
