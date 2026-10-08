import 'package:flutter_test/flutter_test.dart';
import 'package:hue_lock/core/angles.dart';
import 'package:hue_lock/game/hit_judge.dart';
import 'package:hue_lock/game/round.dart';

import 'test_helpers.dart';

void main() {
  final timing = loadTestConfig().timing;
  // 180 deg/s pointer, clockwise, still ring.
  final speed = deg(180);
  final target = Zone(
    center: deg(90),
    width: deg(40),
    color: 0,
    isTarget: true,
  );
  final decoy = Zone(center: deg(130), width: deg(30), color: 1, isDecoy: true);
  final spec = RoundSpec(
    level: 0,
    stageName: 'test',
    targetColor: 0,
    zones: [target, decoy],
    pointerSpeed: speed,
    pointerDir: 1,
    ringSpeed: 0,
    isBreather: false,
  );

  Judgement at(double degrees) => judgeTap(spec, deg(degrees), timing);

  test('center is Perfect, inside is Good', () {
    expect(at(90).kind, HitKind.perfect);
    expect(at(93).kind, HitKind.perfect);
    expect(at(105).kind, HitKind.good);
    expect(at(72).kind, HitKind.good);
  });

  test('grace margin counts taps just outside the edge', () {
    final graceDeg = timing.grace * 180; // pointer moves 180 deg/s
    expect(at(70 - graceDeg * 0.9).kind, HitKind.good);
    expect(at(70 - graceDeg * 1.1).kind, HitKind.miss);
  });

  test('a tap inside a wrong-colored zone is always a miss', () {
    final j = at(117); // decoy spans 115..145, grace would reach 114
    expect(j.kind, HitKind.miss);
    expect(j.wrongZone, decoy);
  });

  test('near misses are flagged with early/late', () {
    final early = at(64); // 6 deg before the zone = 33 ms
    expect(early.kind, HitKind.miss);
    expect(early.nearMiss, isTrue);
    expect(early.early, isTrue);
    expect(early.missBySeconds, closeTo(6 / 180, 1e-9));

    final late = at(160);
    expect(late.early, isFalse);
    expect(late.nearMiss, isFalse); // 50 deg late
  });

  test('neutral ring far away is a plain miss', () {
    final j = at(270);
    expect(j.kind, HitKind.miss);
    expect(j.nearMiss, isFalse);
    expect(j.wrongZone, isNull);
  });

  test('ActiveRound angles are analytic in time and freeze', () {
    final r = ActiveRound(
      spec: spec,
      startTime: 10,
      pointerStart: 0,
      ringStart: 0,
    );
    expect(r.pointerAngleAt(10.5), closeTo(deg(90), 1e-9));
    r.frozenAt = 10.25;
    expect(r.pointerAngleAt(11), closeTo(deg(45), 1e-9));
  });
}
