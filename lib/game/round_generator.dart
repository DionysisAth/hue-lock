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
  /// [speedFactor] / [sizeFactor] apply perks, Slow-mo and Wide.
  RoundSpec next({
    required int level,
    required double pointerLocal,
    required int currentDir,
    int? previousColor,
    bool isFirst = false,
    double speedFactor = 1,
    double sizeFactor = 1,
    bool allowPowerUps = true,
  }) {
    final stage = config.stageFor(level);
    final diff = Difficulty.forLevel(config, level);
    var dir = currentDir == 0 ? 1 : currentDir;

    if (!isFirst && config.boss.isBossLevel(level)) {
      return _boss(level, stage, diff, pointerLocal, dir, speedFactor);
    }

    final speed = diff.pointerSpeed * speedFactor;
    if (level == 0) {
      dir = 1;
    } else if (!isFirst && _rng.chance(stage.reverseChance)) {
      dir = -dir;
    }

    var pulseA = 0.0, pulseW = 0.0;
    if (!isFirst && stage.pulseChance > 0 && _rng.chance(stage.pulseChance)) {
      pulseA = config.pulse.amplitude.clamp(0.0, 0.8);
      pulseW = tau / config.pulse.period;
    }

    // Ring spin, capped well below the pointer's slowest speed so relative
    // motion never stalls or reverses.
    var ringSpeed = 0.0;
    if (stage.rotateChance > 0 && _rng.chance(stage.rotateChance)) {
      final r = config.ringRotation;
      final frac = math.min(
        0.45 * (1 - pulseA),
        _rng.range(r.minFraction, r.maxFraction),
      );
      ringSpeed = (_rng.chance(0.5) ? 1 : -1) * frac * speed;
    }
    final maxRel = speed * (1 + pulseA) + ringSpeed.abs();

    var kind = RoundKind.normal;
    final roll = _rng.nextDouble();
    if (!isFirst && roll < stage.splitChance) {
      kind = RoundKind.split;
    } else if (!isFirst && roll < stage.splitChance + stage.invertedChance) {
      kind = RoundKind.inverted;
    }
    final ghost =
        !isFirst && stage.ghostChance > 0 && _rng.chance(stage.ghostChance);

    // Primary zone: never shorter than the minimum sweep window, and always
    // at least the reaction time ahead of the pointer.
    final timing = config.timing;
    final width = math.min(
      deg(150),
      math.max(diff.zoneSize * sizeFactor, timing.minZoneWindow * maxRel),
    );
    final minLead = _minLead(config, kind, maxRel, width, isFirst: isFirst);
    var maxLead = math.max(minLead, config.zone.maxLeadFraction * tau - width);
    if (kind == RoundKind.split) {
      maxLead = math.max(minLead, math.min(maxLead, minLead + deg(60)));
    }
    final lead = _rng.range(minLead, maxLead);
    final primaryCenter = wrapAngle(pointerLocal + dir * (lead + width / 2));

    var color = _rng.nextInt(paletteSize);
    if (previousColor != null && color == previousColor) {
      color = (color + 1 + _rng.nextInt(paletteSize - 1)) % paletteSize;
    }
    final others = [
      for (var c = 0; c < paletteSize; c++)
        if (c != color) c,
    ];
    _shuffle(others);

    final otherWidth = math.max(
      config.zone.minSize,
      diff.zoneSize * sizeFactor * config.zone.otherZoneSizeFactor,
    );
    final clearance = config.zone.minGap;

    // Coins and power-ups ride on the primary zone of plain rounds.
    var hasCoin = false;
    PowerUp? powerUp;
    if (kind != RoundKind.split) {
      if (level >= config.coins.coinZoneMinLevel &&
          _rng.chance(config.coins.coinZoneChance)) {
        hasCoin = true;
      } else if (allowPowerUps &&
          level >= config.powerUps.minLevel &&
          _rng.chance(config.powerUps.chance)) {
        final types = config.powerUps.types;
        powerUp = types[_rng.nextInt(types.length)];
      }
    }

    RoundSpec build(
      RoundKind kind,
      List<Zone> zones,
      List<RoundStep> steps,
      List<int> ballColors,
    ) => RoundSpec(
      level: level,
      stageName: stage.name,
      kind: kind,
      zones: zones,
      steps: steps,
      ballColors: ballColors,
      pointerSpeed: speed,
      pointerDir: dir,
      ringSpeed: ringSpeed,
      isBreather: diff.isBreather,
      pulseAmplitude: pulseA,
      pulseOmega: pulseW,
      ghost: ghost,
    );

    switch (kind) {
      case RoundKind.split:
        final zones = <Zone>[
          Zone(
            center: primaryCenter,
            width: width,
            color: color,
            isTarget: true,
          ),
        ];
        // The second color sits after the first, ideally far enough to
        // react. If that does not fit in the lap it moves closer; the fuse
        // then grants an extra lap for it (see GameEngine._armStep).
        final far = primaryCenter + dir * width / 2;
        final room = tau - clearance - lead - 2 * width - config.zone.minGap;
        final ideal = _rng.range(
          timing.splitSecondLead * maxRel,
          timing.splitSecondLead * maxRel + deg(40),
        );
        final gap = math.min(ideal, room);
        final second = Zone(
          center: wrapAngle(far + dir * (gap + width / 2)),
          width: width,
          color: others[0],
        );
        if (gap >= config.zone.minGap &&
            _fits(second, zones, config.zone.minGap, pointerLocal, clearance)) {
          zones.add(second);
          if (_rng.chance(0.5)) {
            _placeRandom(zones, others[1], otherWidth, pointerLocal, clearance);
          }
          return build(
            RoundKind.split,
            zones,
            const [
              RoundStep([0], 0),
              RoundStep([1], 1),
            ],
            [color, others[0]],
          );
        }
        // No room for the second half: play it as a normal round.
        return build(
          RoundKind.normal,
          zones,
          const [
            RoundStep([0], 0),
          ],
          [color],
        );

      case RoundKind.inverted:
        // The ball shows the forbidden color; the fair zone is another one.
        final forbidden = color;
        final zones = <Zone>[
          Zone(
            center: primaryCenter,
            width: width,
            color: others[0],
            isTarget: true,
            hasCoin: hasCoin,
            powerUp: powerUp,
          ),
        ];
        // The forbidden zone hugs the primary, preferably before it.
        final gap = _rng.range(
          config.zone.decoyGapMin,
          config.zone.decoyGapMax,
        );
        var placed = false;
        for (final side in [-dir, dir]) {
          final z = Zone(
            center: wrapAngle(
              primaryCenter + side * (width / 2 + gap + otherWidth / 2),
            ),
            width: otherWidth,
            color: forbidden,
            isDecoy: true,
          );
          if (_fits(z, zones, gap, pointerLocal, clearance)) {
            zones.add(z);
            placed = true;
            break;
          }
        }
        placed =
            placed ||
            _placeRandom(zones, forbidden, otherWidth, pointerLocal, clearance);
        if (!placed) {
          return build(
            RoundKind.normal,
            zones,
            const [
              RoundStep([0], 0),
            ],
            [others[0]],
          );
        }
        final count = math.max(
          3,
          stage.minColors + _rng.nextInt(stage.maxColors - stage.minColors + 1),
        );
        for (var i = 1; i < others.length && zones.length < count; i++) {
          _placeRandom(zones, others[i], otherWidth, pointerLocal, clearance);
        }
        return build(
          RoundKind.inverted,
          zones,
          [
            RoundStep([
              for (var i = 0; i < zones.length; i++)
                if (zones[i].color != forbidden) i,
            ], 0),
          ],
          [forbidden],
        );

      case RoundKind.normal:
      case RoundKind.boss:
        final zones = <Zone>[
          Zone(
            center: primaryCenter,
            width: width,
            color: color,
            isTarget: true,
            hasCoin: hasCoin,
            powerUp: powerUp,
          ),
        ];
        final count =
            stage.minColors +
            _rng.nextInt(stage.maxColors - stage.minColors + 1);
        final extra = math.min(count - 1, others.length);
        var placed = 0;
        for (var i = 0; i < stage.decoys && placed < extra; i++) {
          final gap = _rng.range(
            config.zone.decoyGapMin,
            config.zone.decoyGapMax,
          );
          final sides = _rng.chance(0.5) ? [-1, 1] : [1, -1];
          for (final side in sides) {
            final z = Zone(
              center: wrapAngle(
                primaryCenter + side * (width / 2 + gap + otherWidth / 2),
              ),
              width: otherWidth,
              color: others[placed],
              isDecoy: true,
            );
            if (_fits(z, zones, gap, pointerLocal, clearance)) {
              zones.add(z);
              placed++;
              break;
            }
          }
        }
        while (placed < extra) {
          if (!_placeRandom(
            zones,
            others[placed],
            otherWidth,
            pointerLocal,
            clearance,
          )) {
            break;
          }
          placed++;
        }

        final goals = [0];
        // Greedy zone: thin, worth more, and placed before the safe one so
        // going for it is a real choice.
        if (stage.bonusChance > 0 && _rng.chance(stage.bonusChance)) {
          final bw = math.max(
            config.bonusZone.size * sizeFactor,
            config.bonusZone.minWindow * maxRel,
          );
          final lo = minLead + bw / 2;
          final hi = lead - config.zone.minGap - bw / 2;
          if (hi > lo) {
            final bonus = Zone(
              center: wrapAngle(pointerLocal + dir * _rng.range(lo, hi)),
              width: bw,
              color: color,
              isBonus: true,
            );
            if (_fits(
              bonus,
              zones,
              config.zone.minGap,
              pointerLocal,
              clearance,
            )) {
              zones.add(bonus);
              goals.add(zones.length - 1);
            }
          }
        }
        return build(RoundKind.normal, zones, [RoundStep(goals, 0)], [color]);
    }
  }

  RoundSpec _boss(
    int level,
    StageConfig stage,
    Difficulty diff,
    double pointerLocal,
    int dir,
    double speedFactor,
  ) {
    final b = config.boss;
    final speed = diff.pointerSpeed * b.speedFactor * speedFactor;
    final width = math.min(
      deg(70),
      math.max(b.zoneSize, config.timing.minZoneWindow * speed),
    );
    // Four zones, 90 degrees apart, with the pointer in the middle of a gap.
    final colors = [for (var c = 0; c < paletteSize; c++) c];
    _shuffle(colors);
    final zones = [
      for (var i = 0; i < paletteSize; i++)
        Zone(
          center: wrapAngle(pointerLocal + deg(45) + i * tau / paletteSize),
          width: width,
          color: colors[i],
          isTarget: i == 0,
        ),
    ];
    final order = [for (var i = 0; i < paletteSize; i++) i];
    _shuffle(order);
    final length = b.minLength + _rng.nextInt(b.maxLength - b.minLength + 1);
    final sequence = order.take(math.min(length, paletteSize)).toList();
    return RoundSpec(
      level: level,
      stageName: 'boss',
      kind: RoundKind.boss,
      zones: zones,
      steps: [
        for (final z in sequence) RoundStep([z], z),
      ],
      ballColors: [for (final z in sequence) zones[z].color],
      pointerSpeed: speed,
      pointerDir: dir,
      ringSpeed: 0,
      isBreather: false,
    );
  }

  bool _placeRandom(
    List<Zone> zones,
    int color,
    double width,
    double pointerLocal,
    double clearance,
  ) {
    for (var attempt = 0; attempt < 40; attempt++) {
      final z = Zone(center: _rng.range(0, tau), width: width, color: color);
      if (_fits(z, zones, config.zone.minGap, pointerLocal, clearance)) {
        zones.add(z);
        return true;
      }
    }
    return false;
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

  /// How far ahead (radians of pointer travel) a round's target must start.
  /// The first round gets extra time. Rule changes (NOT / split, which never
  /// pause) get extra time too, as much of it as fits in the lap at this
  /// speed, but never less than the normal reaction time.
  static double _minLead(
    GameConfig config,
    RoundKind kind,
    double maxRel,
    double width, {
    required bool isFirst,
  }) {
    final timing = config.timing;
    if (isFirst) return timing.firstRoundLead * maxRel;
    final normal = timing.minReaction * maxRel;
    if (kind != RoundKind.inverted && kind != RoundKind.split) return normal;
    final room = config.zone.maxLeadFraction * tau - width;
    return math.max(normal, math.min(timing.ruleChangeLead * maxRel, room));
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
    final zones = spec.zones;
    if (spec.steps.isEmpty) return ['round has no steps'];
    for (final s in spec.steps) {
      if (s.goals.isEmpty || !s.goals.contains(s.primary)) {
        problems.add('step without a valid primary goal');
      }
      if (s.goals.any((g) => g < 0 || g >= zones.length)) {
        problems.add('goal index out of range');
        return problems;
      }
    }
    if (spec.minRelativeSpeed <=
        0.2 * spec.pointerSpeed * (1 - spec.pulseAmplitude)) {
      problems.add('ring spin too fast relative to pointer');
    }
    final maxRel = spec.maxRelativeSpeed;
    final timing = config.timing;
    // The primary zone of every step must be wide enough to hit; extra
    // goals (other valid colors in a NOT round) are optional.
    for (final s in spec.steps) {
      final z = zones[s.primary];
      if (z.width / maxRel < timing.minZoneWindow - eps) {
        problems.add('target window too short');
      }
      for (final g in s.goals) {
        if (zones[g].isBonus &&
            zones[g].width / maxRel < config.bonusZone.minWindow - eps) {
          problems.add('greedy zone window too short');
        }
      }
    }
    for (final z in zones) {
      if (z.contains(pointerLocal)) {
        problems.add('pointer starts inside a zone');
      }
    }
    for (var i = 0; i < zones.length; i++) {
      for (var j = i + 1; j < zones.length; j++) {
        final a = zones[i], b = zones[j];
        if (angleDiff(a.center, b.center).abs() <
            a.halfWidth + b.halfWidth - eps) {
          problems.add('zones overlap');
        }
        if (!a.isBonus && !b.isBonus && a.color == b.color) {
          problems.add('duplicate zone color');
        }
      }
    }

    final dir = spec.pointerDir;
    double nearEdge(Zone z) => wrapAngle(z.center - dir * z.halfWidth);
    double farEdge(Zone z) => wrapAngle(z.center + dir * z.halfWidth);

    if (spec.kind != RoundKind.boss) {
      final primary = spec.target;
      final lead = travelDistance(pointerLocal, nearEdge(primary), dir);
      final need = _minLead(
        config,
        spec.kind,
        maxRel,
        primary.width,
        isFirst: isFirst,
      );
      if (lead < need - eps) {
        problems.add(
          'target only ${(lead / maxRel * 1000).round()}ms ahead of pointer',
        );
      }
      if (lead + primary.width > tau + eps) {
        problems.add('target not reachable within one lap');
      }
    }
    final ball = spec.ballColors.first;
    final goals0 = spec.steps.first.goals.toSet();
    switch (spec.kind) {
      case RoundKind.normal:
        for (var i = 0; i < zones.length; i++) {
          if ((zones[i].color == ball) != goals0.contains(i)) {
            problems.add('goal/color mismatch');
          }
        }
      case RoundKind.inverted:
        if (!zones.any((z) => z.color == ball)) {
          problems.add('NOT round without the forbidden color');
        }
        for (var i = 0; i < zones.length; i++) {
          if ((zones[i].color != ball) != goals0.contains(i)) {
            problems.add('NOT round goal/color mismatch');
          }
        }
      case RoundKind.split:
        if (spec.steps.length != 2) problems.add('split needs two steps');
        final a = zones[spec.steps[0].primary];
        final b = zones[spec.steps[1].primary];
        // Both halves ahead of the pointer within one lap, in order.
        final lead = travelDistance(pointerLocal, nearEdge(a), dir);
        final gap = travelDistance(farEdge(a), nearEdge(b), dir);
        if (lead + a.width + gap + b.width > tau + eps) {
          problems.add('split halves do not fit in one lap');
        }
        if (spec.ballColors.length != 2 ||
            spec.ballColors[0] != a.color ||
            spec.ballColors[1] != b.color) {
          problems.add('split ball colors mismatch');
        }
      case RoundKind.boss:
        final b = config.boss;
        if (spec.steps.length < b.minLength ||
            spec.steps.length > b.maxLength) {
          problems.add('boss sequence length out of range');
        }
    }
    return problems;
  }
}
