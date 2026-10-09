import 'dart:math' as math;

import '../config/game_config.dart';
import '../core/angles.dart';
import 'round.dart';

enum HitKind { perfect, good, miss }

class Judgement {
  const Judgement({
    required this.kind,
    required this.localAngle,
    this.zone,
    this.zoneIndex,
    this.wrongZone,
    this.nearMiss = false,
    this.missBySeconds = 0,
    this.early = false,
    this.timeout = false,
  });

  /// The fuse burnt out: the pointer passed the target without a tap.
  const Judgement.timeout(this.localAngle)
    : kind = HitKind.miss,
      zone = null,
      zoneIndex = null,
      wrongZone = null,
      nearMiss = false,
      missBySeconds = 0,
      early = false,
      timeout = true;

  final HitKind kind;

  /// Ring-local angle of the pointer at the moment of the tap.
  final double localAngle;

  /// The goal zone that was hit, and its index in the round.
  final Zone? zone;
  final int? zoneIndex;

  /// The wrong zone that was tapped, if any.
  final Zone? wrongZone;

  /// Missed by less than the near-miss threshold ("SO CLOSE!").
  final bool nearMiss;

  /// How far (in pointer travel time) the tap was from the target edge.
  final double missBySeconds;

  /// The pointer had not reached the target yet.
  final bool early;
  final bool timeout;

  bool get isHit => kind != HitKind.miss;
}

/// Judges a tap at ring-local [localAngle] for step [step] of [spec].
///
/// A tap strictly inside a zone that is not a goal of this step is always a
/// miss. Otherwise any goal zone counts, with a small grace margin at its
/// edges converted from time into angle using the pointer's [relSpeed] at
/// that instant. Zones in [consumed] were used by earlier steps and are gone.
Judgement judgeTap(
  RoundSpec spec,
  double localAngle,
  TimingConfig timing, {
  int step = 0,
  Set<int> consumed = const {},
  double? relSpeed,
}) {
  final speed = relSpeed ?? spec.relativeSpeed.abs();
  final s = spec.steps[step];
  final goals = s.goals.toSet();

  for (var i = 0; i < spec.zones.length; i++) {
    if (consumed.contains(i) || goals.contains(i)) continue;
    if (spec.zones[i].contains(localAngle)) {
      return _miss(spec, s, localAngle, speed, timing, wrong: spec.zones[i]);
    }
  }

  int? best;
  var bestDistance = double.infinity;
  for (final g in goals) {
    if (consumed.contains(g)) continue;
    final z = spec.zones[g];
    final d = z.distanceFromCenter(localAngle);
    if (d <= z.halfWidth + timing.grace * speed && d < bestDistance) {
      best = g;
      bestDistance = d;
    }
  }
  if (best != null) {
    final z = spec.zones[best];
    final perfectHalf = math.min(
      z.halfWidth,
      math.max(
        z.width * timing.perfectFraction / 2,
        timing.perfectMinWindow * speed / 2,
      ),
    );
    return Judgement(
      kind: bestDistance <= perfectHalf ? HitKind.perfect : HitKind.good,
      localAngle: localAngle,
      zone: z,
      zoneIndex: best,
    );
  }
  return _miss(spec, s, localAngle, speed, timing);
}

Judgement _miss(
  RoundSpec spec,
  RoundStep step,
  double localAngle,
  double relSpeed,
  TimingConfig timing, {
  Zone? wrong,
}) {
  final target = spec.zones[step.primary];
  final outside = math.max(
    0.0,
    target.distanceFromCenter(localAngle) - target.halfWidth,
  );
  final seconds = outside / relSpeed;
  final early = angleDiff(localAngle, target.center) * spec.pointerDir < 0;
  return Judgement(
    kind: HitKind.miss,
    localAngle: localAngle,
    wrongZone: wrong,
    nearMiss: seconds <= timing.nearMiss,
    missBySeconds: seconds,
    early: early,
  );
}
