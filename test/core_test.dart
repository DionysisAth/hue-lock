import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_lock/core/angles.dart';
import 'package:hue_lock/core/seeded_random.dart';

import 'test_helpers.dart';

void main() {
  group('SeededRandom', () {
    test('matches the reference mulberry32 sequence', () {
      final r = SeededRandom(42);
      expect(
        [r.nextUint32(), r.nextUint32(), r.nextUint32()],
        [2581720956, 1925393290, 3661312704],
      );
      final q = SeededRandom(0xDEADBEEF);
      expect([q.nextUint32(), q.nextUint32()], [4043151706, 1147597007]);
    });

    test('doubles stay in [0, 1)', () {
      final r = SeededRandom(7);
      for (var i = 0; i < 10000; i++) {
        final d = r.nextDouble();
        expect(d, greaterThanOrEqualTo(0));
        expect(d, lessThan(1));
      }
    });
  });

  group('angles', () {
    test('wrapAngle', () {
      expect(wrapAngle(-0.5), closeTo(tau - 0.5, 1e-12));
      expect(wrapAngle(tau + 1), closeTo(1, 1e-12));
    });

    test('angleDiff is the shortest signed difference', () {
      expect(angleDiff(0.1, tau - 0.1), closeTo(0.2, 1e-12));
      expect(angleDiff(tau - 0.1, 0.1), closeTo(-0.2, 1e-12));
    });

    test('travelDistance respects direction', () {
      expect(travelDistance(0, 1, 1), closeTo(1, 1e-12));
      expect(travelDistance(0, 1, -1), closeTo(tau - 1, 1e-12));
      expect(travelDistance(1, 0, -1), closeTo(1, 1e-12));
    });
  });

  group('GameConfig', () {
    test('loads the bundled tuning file with sane values', () {
      final c = loadTestConfig();
      expect(c.timing.grace, closeTo(0.022, 1e-9));
      expect(c.pointer.maxSpeed, greaterThan(c.pointer.baseSpeed));
      expect(c.zone.minSize, lessThan(c.zone.startSize));
      expect(c.ringRotation.maxFraction, lessThan(0.5));
      expect(c.stages.first.fromLevel, 0);
      expect(c.stageFor(0).name, 'warmup');
      expect(c.stageFor(8).minColors, 2);
      expect(c.stageFor(14).reverseChance, 1);
      expect(c.stageFor(30).rotateChance, greaterThan(0));
      expect(c.stageFor(500).name, 'chaos');
      expect(c.boss.isBossLevel(15), isTrue);
      expect(c.boss.isBossLevel(25), isFalse);
      expect(c.boss.isBossLevel(0), isFalse);
    });

    test('overrides deep-merge (remote config)', () {
      final c = loadTestConfig({
        'pointer': {'baseSpeedDegPerSec': 200},
      });
      expect(c.pointer.baseSpeed, closeTo(200 * math.pi / 180, 1e-9));
      expect(c.pointer.maxSpeed, closeTo(330 * math.pi / 180, 1e-9));
    });
  });
}
