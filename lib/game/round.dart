import 'dart:math' as math;

import '../core/angles.dart';

enum PowerUp { shield, slow, wide }

enum RoundKind {
  /// Hit the zone of the ball's color.
  normal,

  /// "NOT" round: hit any zone except the ball's color.
  inverted,

  /// Split ball: hit its two colors in order, in one lap.
  split,

  /// Memory round: watch a color sequence, then hit it in order.
  boss,
}

/// A colored arc on the ring, in ring-local angles (radians, 0 = top,
/// clockwise positive).
class Zone {
  const Zone({
    required this.center,
    required this.width,
    required this.color,
    this.isTarget = false,
    this.isDecoy = false,
    this.isBonus = false,
    this.hasCoin = false,
    this.powerUp,
  });

  final double center;
  final double width;

  /// Index into the active color palette.
  final int color;

  /// The zone the round's first step is fairly placed for.
  final bool isTarget;
  final bool isDecoy;

  /// Thin, high-value "greedy" zone.
  final bool isBonus;
  final bool hasCoin;
  final PowerUp? powerUp;

  double get halfWidth => width / 2;

  /// Unsigned angular distance from [angle] to the zone center.
  double distanceFromCenter(double angle) => angleDiff(angle, center).abs();

  bool contains(double angle, {double margin = 0}) =>
      distanceFromCenter(angle) <= halfWidth + margin;
}

/// One tap of a round: any of [goals] (zone indices) counts; [primary] is
/// the one the round is fairly placed for (fuse, near-miss, death guide).
class RoundStep {
  const RoundStep(this.goals, this.primary);

  final List<int> goals;
  final int primary;
}

/// Everything needed to play one round. Pure data, produced by
/// [RoundGenerator] from a seed, so a run can be replayed exactly.
class RoundSpec {
  const RoundSpec({
    required this.level,
    required this.stageName,
    required this.zones,
    required this.steps,
    required this.ballColors,
    required this.pointerSpeed,
    required this.pointerDir,
    required this.ringSpeed,
    required this.isBreather,
    this.kind = RoundKind.normal,
    this.pulseAmplitude = 0,
    this.pulseOmega = 0,
    this.ghost = false,
  });

  /// Rounds cleared before this one in the run.
  final int level;
  final String stageName;
  final RoundKind kind;
  final List<Zone> zones;
  final List<RoundStep> steps;

  /// What the ball shows: the target color (normal), the forbidden color
  /// (inverted), both halves (split) or the sequence (boss).
  final List<int> ballColors;

  /// Base pointer speed magnitude (rad/s).
  final double pointerSpeed;

  /// +1 clockwise, -1 counter-clockwise.
  final int pointerDir;

  /// Signed ring spin (rad/s), 0 when the ring is still.
  final double ringSpeed;
  final bool isBreather;

  /// Surge: pointer speed = base * (1 + a * sin(omega * t)).
  final double pulseAmplitude;
  final double pulseOmega;

  /// Zones blink in and out (visual only).
  final bool ghost;

  int get targetColor => ballColors.first;

  /// Primary zone of the first step.
  Zone get target => zones[steps.first.primary];

  /// Nominal signed speed of the pointer relative to the ring (rad/s).
  double get relativeSpeed => pointerDir * pointerSpeed - ringSpeed;

  /// Fastest the pointer ever sweeps the ring (rad/s). Fairness margins are
  /// computed with this, so they hold at every instant.
  double get maxRelativeSpeed =>
      pointerSpeed * (1 + pulseAmplitude) + ringSpeed.abs();

  /// Slowest the pointer ever sweeps the ring (rad/s); always > 0.
  double get minRelativeSpeed =>
      pointerSpeed * (1 - pulseAmplitude) - ringSpeed.abs();
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

  /// Current step and the zones already hit in earlier steps.
  int step = 0;
  final consumed = <int>{};

  /// One-lap fuse, in units of [travelAt]: the step started at
  /// [stepStartTravel] and must be hit before [stepDeadline].
  double stepStartTravel = 0;
  double stepDeadline = double.infinity;

  RoundStep get currentStep => spec.steps[step];
  Zone get currentPrimary => spec.zones[currentStep.primary];

  double _elapsed(double t) {
    final end = frozenAt == null ? t : math.min(t, frozenAt!);
    return math.max(0, end - startTime);
  }

  /// Pointer distance travelled along its direction after [e] seconds.
  double _pointerTravel(double e) {
    final a = spec.pulseAmplitude;
    if (a == 0) return spec.pointerSpeed * e;
    final w = spec.pulseOmega;
    return spec.pointerSpeed * (e + a / w * (1 - math.cos(w * e)));
  }

  double pointerAngleAt(double t) =>
      wrapAngle(pointerStart + spec.pointerDir * _pointerTravel(_elapsed(t)));

  double ringAngleAt(double t) =>
      wrapAngle(ringStart + spec.ringSpeed * _elapsed(t));

  /// Ring-local angle under the pointer.
  double localPointerAt(double t) =>
      wrapAngle(pointerAngleAt(t) - ringAngleAt(t));

  /// How far the pointer has swept the ring since the round started, in its
  /// own direction. Always increasing.
  double travelAt(double t) {
    final e = _elapsed(t);
    return _pointerTravel(e) - spec.pointerDir * spec.ringSpeed * e;
  }

  /// Instantaneous speed of the pointer over the ring (rad/s).
  double relativeSpeedAt(double t) {
    final e = _elapsed(t);
    final a = spec.pulseAmplitude;
    final p = spec.pointerSpeed * (1 + a * math.sin(spec.pulseOmega * e));
    return (p - spec.pointerDir * spec.ringSpeed).abs();
  }

  /// Fraction of the current step's fuse left at [t] (1 = full, 0 = out).
  double fuseAt(double t) {
    if (stepDeadline == double.infinity) return 1;
    final span = stepDeadline - stepStartTravel;
    return ((stepDeadline - travelAt(t)) / span).clamp(0.0, 1.0);
  }

  /// Game time at which the pointer reaches ring-local [local] next, starting
  /// from [now].
  double timeWhenAt(double now, double local) {
    final from = math.max(now, startTime);
    if (frozenAt != null && from >= frozenAt!) return double.infinity;
    final goal =
        travelAt(from) +
        travelDistance(localPointerAt(from), local, spec.pointerDir);
    var lo = from, hi = from + 1;
    while (travelAt(hi) < goal) {
      hi += hi - from;
    }
    for (var i = 0; i < 60; i++) {
      final mid = (lo + hi) / 2;
      if (travelAt(mid) < goal) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return hi;
  }
}
