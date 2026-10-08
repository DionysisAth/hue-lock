import '../core/angles.dart';

/// A colored arc on the ring, in ring-local angles (radians, 0 = top,
/// clockwise positive).
class Zone {
  const Zone({
    required this.center,
    required this.width,
    required this.color,
    this.isTarget = false,
    this.isDecoy = false,
    this.hasCoin = false,
  });

  final double center;
  final double width;

  /// Index into the active color palette.
  final int color;
  final bool isTarget;
  final bool isDecoy;
  final bool hasCoin;

  double get halfWidth => width / 2;

  /// Unsigned angular distance from [angle] to the zone center.
  double distanceFromCenter(double angle) => angleDiff(angle, center).abs();

  bool contains(double angle, {double margin = 0}) =>
      distanceFromCenter(angle) <= halfWidth + margin;
}

/// Everything needed to play one round. Pure data, produced by
/// [RoundGenerator] from a seed, so a run can be replayed exactly.
class RoundSpec {
  const RoundSpec({
    required this.level,
    required this.stageName,
    required this.targetColor,
    required this.zones,
    required this.pointerSpeed,
    required this.pointerDir,
    required this.ringSpeed,
    required this.isBreather,
  });

  /// Rounds cleared before this one in the run.
  final int level;
  final String stageName;
  final int targetColor;
  final List<Zone> zones;

  /// Pointer speed magnitude (rad/s).
  final double pointerSpeed;

  /// +1 clockwise, -1 counter-clockwise.
  final int pointerDir;

  /// Signed ring spin (rad/s), 0 when the ring is still.
  final double ringSpeed;
  final bool isBreather;

  Zone get target => zones.firstWhere((z) => z.isTarget);

  /// Signed speed of the pointer relative to the ring (rad/s). Its sign always
  /// equals [pointerDir] because ring spin is capped below pointer speed.
  double get relativeSpeed => pointerDir * pointerSpeed - ringSpeed;
}

/// A [RoundSpec] placed on the game clock. Angles are analytic functions of
/// time, so hits can be judged at the exact input timestamp instead of the
/// last rendered frame.
class ActiveRound {
  ActiveRound({
    required this.spec,
    required this.startTime,
    required this.pointerStart,
    required this.ringStart,
  });

  final RoundSpec spec;

  /// Game time the round started; shifted forward while the game is frozen.
  double startTime;
  final double pointerStart;
  final double ringStart;

  /// Once set, the round is frozen at this time (death freeze-frame).
  double? frozenAt;

  double _elapsed(double t) {
    final end = frozenAt == null ? t : (t < frozenAt! ? t : frozenAt!);
    final e = end - startTime;
    return e < 0 ? 0 : e;
  }

  double pointerAngleAt(double t) => wrapAngle(
    pointerStart + spec.pointerDir * spec.pointerSpeed * _elapsed(t),
  );

  double ringAngleAt(double t) =>
      wrapAngle(ringStart + spec.ringSpeed * _elapsed(t));

  /// Ring-local angle under the pointer.
  double localPointerAt(double t) =>
      wrapAngle(pointerAngleAt(t) - ringAngleAt(t));
}
