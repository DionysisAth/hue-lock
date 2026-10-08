import 'dart:math' as math;

import '../config/game_config.dart';
import '../core/angles.dart';
import '../core/seeded_random.dart';
import 'round.dart';

/// Number of distinct zone colors the game uses.
const paletteSize = 4;

/// Speed / size for a level, after the wave ("breather") adjustment.
class Difficulty {
  const Difficulty({
    required this.pointerSpeed,
    required this.zoneSize,
    required this.isBreather,
  });

  final double pointerSpeed;
  final double zoneSize;
  final bool isBreather;

  static bool isBreatherLevel(GameConfig config, int level) {
    final period = config.wave.period;
    return period > 1 && level >= period && (level + 1) % period == 0;
  }

  factory Difficulty.forLevel(GameConfig config, int level) {
    final breather = isBreatherLevel(config, level);
    final effective = breather
        ? math.max(0, level - config.wave.breatherLevelDrop)
        : level;
    final p = config.pointer;
    final z = config.zone;
    return Difficulty(
      pointerSpeed: math.min(
        p.maxSpeed,
        p.baseSpeed + p.speedPerLevel * effective,
      ),
      zoneSize: math.max(z.minSize, z.startSize + z.sizePerLevel * effective),
      isBreather: breather,
    );
  }
}

/// Generates rounds from a seed. Every round it produces passes
/// [RoundGenerator.validate]: the target is always reachable with at least
/// the configured reaction time, and is always wide enough to hit.
class RoundGenerator {
  RoundGenerator(this.config, int seed) : _rng = SeededRandom(seed);

  final GameConfig config;
  final SeededRandom _rng;

  /// [pointerLocal] is the ring-local angle of the pointer when the round
  /// starts; [currentDir] is the pointer direction during the previous round.
  RoundSpec next({
    required int level,
    required double pointerLocal,
    required int currentDir,
    int? previousColor,
    bool isFirst = false,
  }) {
    final stage = config.stageFor(level);
    final diff = Difficulty.forLevel(config, level);
    final speed = diff.pointerSpeed;

    // Direction: the first round of a run always goes clockwise.
    var dir = currentDir == 0 ? 1 : currentDir;
    if (level == 0) {
      dir = 1;
    } else if (!isFirst && _rng.chance(stage.reverseChance)) {
      dir = -dir;
    }

    // Ring spin, capped well below pointer speed so relative motion never
    // stalls or reverses.
    var ringSpeed = 0.0;
    if (stage.rotateChance > 0 && _rng.chance(stage.rotateChance)) {
      final r = config.ringRotation;
      final frac = math.min(0.45, _rng.range(r.minFraction, r.maxFraction));
      ringSpeed = (_rng.chance(0.5) ? 1 : -1) * frac * speed;
    }
    final relSpeed = (dir * speed - ringSpeed).abs();

    // Target zone: never shorter than the minimum sweep window.
    final timing = config.timing;
    final targetWidth = math.min(
      deg(150),
      math.max(diff.zoneSize, timing.minZoneWindow * relSpeed),
    );
    final reaction = isFirst ? timing.firstRoundLead : timing.minReaction;
    final minLead = reaction * relSpeed;
    final maxLead = math.max(
      minLead,
      config.zone.maxLeadFraction * tau - targetWidth,
    );
    final lead = _rng.range(minLead, maxLead);
    final targetCenter = wrapAngle(
      pointerLocal + dir * (lead + targetWidth / 2),
    );

    // Colors: target differs from the previous ball color when possible.
    var targetColor = _rng.nextInt(paletteSize);
    if (previousColor != null && targetColor == previousColor) {
      targetColor =
          (targetColor + 1 + _rng.nextInt(paletteSize - 1)) % paletteSize;
    }
    final others = [
      for (var c = 0; c < paletteSize; c++)
        if (c != targetColor) c,
    ];
    _shuffle(others);

    final hasCoin =
        level >= config.coins.coinZoneMinLevel &&
        _rng.chance(config.coins.coinZoneChance);
    final zones = <Zone>[
      Zone(
        center: targetCenter,
        width: targetWidth,
        color: targetColor,
        isTarget: true,
        hasCoin: hasCoin,
      ),
    ];

    final colorCount =
        stage.minColors + _rng.nextInt(stage.maxColors - stage.minColors + 1);
    final extra = math.min(colorCount - 1, others.length);
    final otherWidth = math.max(
      config.zone.minSize,
      diff.zoneSize * config.zone.otherZoneSizeFactor,
    );
    // Keep the pointer's starting spot clear so a round never begins with
    // the pointer already sitting on a zone.
    final startClearance = config.zone.minGap;

    var placed = 0;
    // Decoys hug the target, on either side.
    for (var i = 0; i < stage.decoys && placed < extra; i++) {
      final gap = _rng.range(config.zone.decoyGapMin, config.zone.decoyGapMax);
      final sides = _rng.chance(0.5) ? [-1, 1] : [1, -1];
      for (final side in sides) {
        final center = wrapAngle(
          targetCenter + side * (targetWidth / 2 + gap + otherWidth / 2),
        );
        final zone = Zone(
          center: center,
          width: otherWidth,
          color: others[placed],
          isDecoy: true,
        );
        if (_fits(zone, zones, gap, pointerLocal, startClearance)) {
          zones.add(zone);
          placed++;
          break;
        }
      }
    }
    // Remaining colors go anywhere they fit.
    for (var attempt = 0; placed < extra && attempt < 40; attempt++) {
      final zone = Zone(
        center: _rng.range(0, tau),
        width: otherWidth,
        color: others[placed],
      );
      if (_fits(
        zone,
        zones,
        config.zone.minGap,
        pointerLocal,
        startClearance,
      )) {
        zones.add(zone);
        placed++;
      }
    }

    return RoundSpec(
      level: level,
      stageName: stage.name,
      targetColor: targetColor,
      zones: zones,
      pointerSpeed: speed,
      pointerDir: dir,
      ringSpeed: ringSpeed,
      isBreather: diff.isBreather,
    );
  }

  bool _fits(
    Zone zone,
    List<Zone> existing,
    double gap,
    double pointerLocal,
    double startClearance,
  ) {
    if (zone.contains(pointerLocal, margin: startClearance)) return false;
    for (final other in existing) {
      final d = angleDiff(zone.center, other.center).abs();
      if (d < zone.halfWidth + other.halfWidth + gap - 1e-9) return false;
    }
    return true;
  }

  void _shuffle(List<int> list) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = _rng.nextInt(i + 1);
      final t = list[i];
      list[i] = list[j];
      list[j] = t;
    }
  }

  /// Returns the list of fairness violations for [spec] (empty = fair).
  /// Used by tests and debug asserts.
  static List<String> validate(
    GameConfig config,
    RoundSpec spec,
    double pointerLocal, {
    bool isFirst = false,
  }) {
    const eps = 1e-6;
    final problems = <String>[];
    final targets = spec.zones.where((z) => z.isTarget).toList();
    if (targets.length != 1) {
      problems.add('expected exactly one target, got ${targets.length}');
      return problems;
    }
    final target = targets.single;
    if (spec.zones.where((z) => z.color == target.color).length != 1) {
      problems.add('target color appears on more than one zone');
    }
    final rel = spec.relativeSpeed;
    if (rel.sign != spec.pointerDir.sign ||
        rel.abs() < spec.pointerSpeed * 0.5 - eps) {
      problems.add('ring spin too fast relative to pointer');
    }
    final relAbs = rel.abs();
    final nearEdge = wrapAngle(
      target.center - spec.pointerDir * target.halfWidth,
    );
    final lead = travelDistance(pointerLocal, nearEdge, spec.pointerDir);
    final reaction = isFirst
        ? config.timing.firstRoundLead
        : config.timing.minReaction;
    if (lead / relAbs < reaction - eps) {
      problems.add(
        'target only ${(lead / relAbs * 1000).round()}ms ahead of pointer',
      );
    }
    if (lead + target.width > tau + eps) {
      problems.add('target not reachable within one lap');
    }
    if (target.width / relAbs < config.timing.minZoneWindow - eps) {
      problems.add('target window too short');
    }
    for (final z in spec.zones) {
      if (z.contains(pointerLocal)) {
        problems.add('pointer starts inside a zone');
      }
    }
    for (var i = 0; i < spec.zones.length; i++) {
      for (var j = i + 1; j < spec.zones.length; j++) {
        final a = spec.zones[i], b = spec.zones[j];
        if (angleDiff(a.center, b.center).abs() <
            a.halfWidth + b.halfWidth - eps) {
          problems.add('zones overlap');
        }
        if (a.color == b.color) problems.add('duplicate zone color');
      }
    }
    return problems;
  }
}
