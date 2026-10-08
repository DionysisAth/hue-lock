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
    this.wrongZone,
    this.nearMiss = false,
    this.missBySeconds = 0,
    this.early = false,
  });

  final HitKind kind;

  /// Ring-local angle of the pointer at the moment of the tap.
  final double localAngle;

  /// The target, when it was hit.
  final Zone? zone;

  /// The wrong-colored zone that was tapped, if any.
  final Zone? wrongZone;

  /// Missed by less than the near-miss threshold ("SO CLOSE!").
  final bool nearMiss;

  /// How far (in pointer travel time) the tap was from the target edge.
  final double missBySeconds;

  /// The pointer had not reached the target yet.
  final bool early;

  bool get isHit => kind != HitKind.miss;
}

/// Judges a tap at ring-local [localAngle].
///
/// A tap strictly inside a wrong-colored zone is always a miss. Otherwise the
/// target counts with a small grace margin at its edges, converted from time
/// into angle using the current relative pointer speed.
Judgement judgeTap(RoundSpec spec, double localAngle, TimingConfig timing) {
  final relSpeed = spec.relativeSpeed.abs();
  final target = spec.target;

  for (final z in spec.zones) {
    if (!z.isTarget && z.contains(localAngle)) {
      return _miss(spec, target, localAngle, relSpeed, timing, wrong: z);
    }
  }

  final d = target.distanceFromCenter(localAngle);
  if (d <= target.halfWidth + timing.grace * relSpeed) {
    final perfectHalf = math.min(
      target.halfWidth,
      math.max(
        target.width * timing.perfectFraction / 2,
        timing.perfectMinWindow * relSpeed / 2,
      ),
    );
    return Judgement(
      kind: d <= perfectHalf ? HitKind.perfect : HitKind.good,
      localAngle: localAngle,
      zone: target,
    );
  }
  return _miss(spec, target, localAngle, relSpeed, timing);
}

Judgement _miss(
  RoundSpec spec,
  Zone target,
  double localAngle,
  double relSpeed,
  TimingConfig timing, {
  Zone? wrong,
}) {
  final outside = math.max(
    0.0,
    target.distanceFromCenter(localAngle) - target.halfWidth,
  );
  final seconds = outside / relSpeed;
  final travelDir = spec.relativeSpeed.sign;
  final early = angleDiff(localAngle, target.center) * travelDir < 0;
  return Judgement(
    kind: HitKind.miss,
    localAngle: localAngle,
    wrongZone: wrong,
    nearMiss: seconds <= timing.nearMiss,
    missBySeconds: seconds,
    early: early,
  );
}
