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
    zones: [target, decoy],
    steps: const [
      RoundStep([0], 0),
    ],
    ballColors: const [0],
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

  test('NOT round: any zone except the forbidden color counts', () {
    final zones = [
      Zone(center: deg(90), width: deg(40), color: 1, isTarget: true),
      Zone(center: deg(140), width: deg(30), color: 0, isDecoy: true),
      Zone(center: deg(220), width: deg(30), color: 2),
    ];
    final not = RoundSpec(
      level: 20,
      stageName: 'not',
      kind: RoundKind.inverted,
      zones: zones,
      steps: const [
        RoundStep([0, 2], 0),
      ],
      ballColors: const [0],
      pointerSpeed: speed,
      pointerDir: 1,
      ringSpeed: 0,
      isBreather: false,
    );
    expect(judgeTap(not, deg(90), timing).isHit, isTrue);
    expect(judgeTap(not, deg(220), timing).isHit, isTrue);
    final forbidden = judgeTap(not, deg(140), timing);
    expect(forbidden.kind, HitKind.miss);
    expect(forbidden.wrongZone, zones[1]);
  });

  test('greedy zone counts as a hit; consumed zones are gone', () {
    final zones = [
      Zone(center: deg(90), width: deg(40), color: 0, isTarget: true),
      Zone(center: deg(40), width: deg(8), color: 0, isBonus: true),
    ];
    final greedy = RoundSpec(
      level: 10,
      stageName: 'test',
      zones: zones,
      steps: const [
        RoundStep([0, 1], 0),
      ],
      ballColors: const [0],
      pointerSpeed: speed,
      pointerDir: 1,
      ringSpeed: 0,
      isBreather: false,
    );
    final j = judgeTap(greedy, deg(40), timing);
    expect(j.isHit, isTrue);
    expect(j.zone!.isBonus, isTrue);
    expect(j.zoneIndex, 1);
    // A used-up zone neither counts nor blocks.
    expect(judgeTap(greedy, deg(40), timing, consumed: {1}).isHit, isFalse);
  });

  test('surge rounds: angles stay analytic and timeWhenAt is exact', () {
    final surge = RoundSpec(
      level: 50,
      stageName: 'surge',
      zones: [target],
      steps: const [
        RoundStep([0], 0),
      ],
      ballColors: const [0],
      pointerSpeed: speed,
      pointerDir: 1,
      ringSpeed: 0,
      isBreather: false,
      pulseAmplitude: 0.45,
      pulseOmega: 7,
    );
    final r = ActiveRound(
      spec: surge,
      startTime: 0,
      pointerStart: 0,
      ringStart: 0,
    );
    final t = r.timeWhenAt(0, deg(90));
    expect(r.localPointerAt(t), closeTo(deg(90), 1e-6));
    expect(r.relativeSpeedAt(0.2), isNot(closeTo(speed, 1e-3)));
  });
}
