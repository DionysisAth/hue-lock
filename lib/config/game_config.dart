import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

const _deg = math.pi / 180;

/// Typed view of `assets/config/game_config.json`.
///
/// Angles are converted to radians and times to seconds on load so the game
/// code never has to think about units.
class GameConfig {
  GameConfig._(this.raw)
    : timing = TimingConfig._(raw['timing'] as Map<String, dynamic>),
      pointer = PointerConfig._(raw['pointer'] as Map<String, dynamic>),
      zone = ZoneConfig._(raw['zone'] as Map<String, dynamic>),
      wave = WaveConfig._(raw['wave'] as Map<String, dynamic>),
      stages =
          (raw['stages'] as List)
              .map((s) => StageConfig._(s as Map<String, dynamic>))
              .toList()
            ..sort((a, b) => a.fromLevel.compareTo(b.fromLevel)),
      ringRotation = RingRotationConfig._(
        raw['ringRotation'] as Map<String, dynamic>,
      ),
      scoring = ScoringConfig._(raw['scoring'] as Map<String, dynamic>),
      coins = CoinsConfig._(raw['coins'] as Map<String, dynamic>),
      continues = ContinueConfig._(raw['continue'] as Map<String, dynamic>),
      ads = AdsConfig._(raw['ads'] as Map<String, dynamic>),
      oneLap = (raw['oneLap'] as Map<String, dynamic>)['enabled'] as bool,
      pulse = PulseConfig._(raw['pulse'] as Map<String, dynamic>),
      ghost = GhostConfig._(raw['ghost'] as Map<String, dynamic>),
      bonusZone = BonusZoneConfig._(raw['bonusZone'] as Map<String, dynamic>),
      setBonusPerLock = _i(
        raw['locks'] as Map<String, dynamic>,
        'setBonusPerLock',
      ),
      fever = FeverConfig._(raw['fever'] as Map<String, dynamic>),
      powerUps = PowerUpConfig._(raw['powerUps'] as Map<String, dynamic>),
      boss = BossConfig._(raw['boss'] as Map<String, dynamic>),
      worlds = WorldsConfig._(raw['worlds'] as Map<String, dynamic>),
      announce = AnnounceConfig._(raw['announce'] as Map<String, dynamic>);

  factory GameConfig.fromJson(Map<String, dynamic> json) => GameConfig._(json);

  factory GameConfig.fromJsonString(String source) =>
      GameConfig.fromJson(jsonDecode(source) as Map<String, dynamic>);

  static const assetPath = 'assets/config/game_config.json';

  /// Loads the bundled config. [overrides] (e.g. from a remote config service)
  /// are deep-merged on top, so the ramp can be re-tuned without an update.
  static Future<GameConfig> load({Map<String, dynamic>? overrides}) async {
    final base = jsonDecode(
      await rootBundle.loadString(assetPath),
    ) as Map<String, dynamic>;
    return GameConfig.fromJson(
      overrides == null ? base : deepMerge(base, overrides),
    );
  }

  final Map<String, dynamic> raw;
  final TimingConfig timing;
  final PointerConfig pointer;
  final ZoneConfig zone;
  final WaveConfig wave;
  final List<StageConfig> stages;
  final RingRotationConfig ringRotation;
  final ScoringConfig scoring;
  final CoinsConfig coins;
  final ContinueConfig continues;
  final AdsConfig ads;

  /// The target must be hit on the pointer's first fair pass.
  final bool oneLap;
  final PulseConfig pulse;
  final GhostConfig ghost;
  final BonusZoneConfig bonusZone;
  final int setBonusPerLock;
  final FeverConfig fever;
  final PowerUpConfig powerUps;
  final BossConfig boss;
  final WorldsConfig worlds;
  final AnnounceConfig announce;

  StageConfig stageFor(int level) {
    var stage = stages.first;
    for (final s in stages) {
      if (level >= s.fromLevel) stage = s;
    }
    return stage;
  }
}

Map<String, dynamic> deepMerge(
  Map<String, dynamic> base,
  Map<String, dynamic> overrides,
) {
  final out = Map<String, dynamic>.of(base);
  overrides.forEach((key, value) {
    final existing = out[key];
    if (existing is Map<String, dynamic> && value is Map<String, dynamic>) {
      out[key] = deepMerge(existing, value);
    } else {
      out[key] = value;
    }
  });
  return out;
}

double _d(Map<String, dynamic> m, String k) => (m[k] as num).toDouble();
int _i(Map<String, dynamic> m, String k) => (m[k] as num).toInt();
double _ms(Map<String, dynamic> m, String k) => _d(m, k) / 1000;

class TimingConfig {
  TimingConfig._(Map<String, dynamic> m)
    : grace = _ms(m, 'graceMs'),
      perfectFraction = _d(m, 'perfectFraction'),
      perfectMinWindow = _ms(m, 'perfectMinWindowMs'),
      nearMiss = _ms(m, 'nearMissMs'),
      minReaction = _ms(m, 'minReactionMs'),
      splitSecondLead = _ms(m, 'splitSecondLeadMs'),
      firstRoundLead = _ms(m, 'firstRoundLeadMs'),
      minZoneWindow = _ms(m, 'minZoneWindowMs'),
      maxTapLookback = _ms(m, 'maxTapLookbackMs'),
      deathFreeze = _ms(m, 'deathFreezeMs'),
      restartLockout = _ms(m, 'restartLockoutMs'),
      continueCountdown = _ms(m, 'continueCountdownMs');

  /// Extra time on each side of a zone that still counts as a hit.
  final double grace;

  /// Fraction of a zone (centered) that counts as Perfect.
  final double perfectFraction;

  /// The Perfect window never gets shorter than this (seconds).
  final double perfectMinWindow;

  /// A miss this close (seconds of pointer travel) to the target is "SO CLOSE".
  final double nearMiss;

  /// The target always starts at least this far ahead of the pointer.
  final double minReaction;

  /// The second color of a split ball is at least this far behind the first.
  final double splitSecondLead;
  final double firstRoundLead;

  /// A target is never shorter than this to sweep through.
  final double minZoneWindow;

  /// How far back an input timestamp may be trusted relative to the last frame.
  final double maxTapLookback;
  final double deathFreeze;
  final double restartLockout;
  final double continueCountdown;
}

class PointerConfig {
  PointerConfig._(Map<String, dynamic> m)
    : baseSpeed = _d(m, 'baseSpeedDegPerSec') * _deg,
      speedPerLevel = _d(m, 'speedPerLevel') * _deg,
      maxSpeed = _d(m, 'maxSpeedDegPerSec') * _deg;

  final double baseSpeed;
  final double speedPerLevel;
  final double maxSpeed;
}

class ZoneConfig {
  ZoneConfig._(Map<String, dynamic> m)
    : startSize = _d(m, 'startSizeDeg') * _deg,
      sizePerLevel = _d(m, 'sizePerLevel') * _deg,
      minSize = _d(m, 'minSizeDeg') * _deg,
      otherZoneSizeFactor = _d(m, 'otherZoneSizeFactor'),
      minGap = _d(m, 'minGapDeg') * _deg,
      decoyGapMin = ((m['decoyGapDeg'] as List)[0] as num).toDouble() * _deg,
      decoyGapMax = ((m['decoyGapDeg'] as List)[1] as num).toDouble() * _deg,
      maxLeadFraction = _d(m, 'maxLeadFraction');

  final double startSize;
  final double sizePerLevel;
  final double minSize;
  final double otherZoneSizeFactor;
  final double minGap;
  final double decoyGapMin;
  final double decoyGapMax;

  /// The target is placed within this fraction of a lap ahead of the pointer.
  final double maxLeadFraction;
}

class WaveConfig {
  WaveConfig._(Map<String, dynamic> m)
    : period = _i(m, 'period'),
      breatherLevelDrop = _i(m, 'breatherLevelDrop');

  /// Every [period]th round is an easier "breather" round.
  final int period;
  final int breatherLevelDrop;
}

class StageConfig {
  StageConfig._(Map<String, dynamic> m)
    : fromLevel = _i(m, 'fromLevel'),
      name = m['name'] as String,
      minColors = ((m['colors'] as List)[0] as num).toInt(),
      maxColors = ((m['colors'] as List)[1] as num).toInt(),
      reverseChance = _d(m, 'reverse'),
      decoys = _i(m, 'decoys'),
      rotateChance = _d(m, 'rotate'),
      minLocks = ((m['locks'] as List)[0] as num).toInt(),
      maxLocks = ((m['locks'] as List)[1] as num).toInt(),
      bonusChance = _d(m, 'bonus'),
      invertedChance = _d(m, 'inverted'),
      splitChance = _d(m, 'split'),
      ghostChance = _d(m, 'ghost'),
      pulseChance = _d(m, 'pulse');

  final int fromLevel;
  final String name;
  final int minColors;
  final int maxColors;

  /// Chance the pointer flips direction after a hit.
  final double reverseChance;

  /// Number of decoy zones placed right next to the target.
  final int decoys;

  /// Chance the ring itself spins during a round.
  final double rotateChance;

  /// Locks per set (rounds cleared in a row for a set bonus).
  final int minLocks;
  final int maxLocks;

  /// Chance of a thin, high-value extra zone of the ball's color.
  final double bonusChance;

  /// Chance of a "NOT" round: hit any color except the ball's.
  final double invertedChance;

  /// Chance of a split ball: hit two colors in order in one lap.
  final double splitChance;

  /// Chance the zones blink in and out.
  final double ghostChance;

  /// Chance the pointer surges (speed swings) during the round.
  final double pulseChance;
}

class PulseConfig {
  PulseConfig._(Map<String, dynamic> m)
    : amplitude = _d(m, 'amplitude'),
      period = _ms(m, 'periodMs');

  final double amplitude;
  final double period;
}

class GhostConfig {
  GhostConfig._(Map<String, dynamic> m)
    : period = _ms(m, 'periodMs'),
      visibleFraction = _d(m, 'visibleFraction');

  final double period;
  final double visibleFraction;
}

class BonusZoneConfig {
  BonusZoneConfig._(Map<String, dynamic> m)
    : size = _d(m, 'sizeDeg') * _deg,
      minWindow = _ms(m, 'minWindowMs'),
      points = _i(m, 'points');

  final double size;
  final double minWindow;
  final int points;
}

class FeverConfig {
  FeverConfig._(Map<String, dynamic> m)
    : perfectStreak = _i(m, 'perfectStreak'),
      pointsMultiplier = _i(m, 'pointsMultiplier'),
      speedFactor = _d(m, 'speedFactor');

  final int perfectStreak;
  final int pointsMultiplier;
  final double speedFactor;
}

class PowerUpConfig {
  PowerUpConfig._(Map<String, dynamic> m)
    : chance = _d(m, 'chance'),
      minLevel = _i(m, 'minLevel'),
      slowRounds = _i(m, 'slowRounds'),
      slowFactor = _d(m, 'slowFactor'),
      wideRounds = _i(m, 'wideRounds'),
      wideFactor = _d(m, 'wideFactor');

  final double chance;
  final int minLevel;
  final int slowRounds;
  final double slowFactor;
  final int wideRounds;
  final double wideFactor;
}

class BossConfig {
  BossConfig._(Map<String, dynamic> m)
    : every = _i(m, 'every'),
      minLength = ((m['sequenceLength'] as List)[0] as num).toInt(),
      maxLength = ((m['sequenceLength'] as List)[1] as num).toInt(),
      intro = _ms(m, 'introMs'),
      previewPerColor = _ms(m, 'previewPerColorMs'),
      previewGap = _ms(m, 'previewGapMs'),
      goDelay = _ms(m, 'goDelayMs'),
      zoneSize = _d(m, 'zoneSizeDeg') * _deg,
      speedFactor = _d(m, 'speedFactor'),
      stepPoints = _i(m, 'stepPoints'),
      clearBonus = _i(m, 'clearBonus');

  /// A boss round every [every] levels (0 disables them).
  final int every;
  final int minLength;
  final int maxLength;

  /// Banner only, before the first color shows.
  final double intro;
  final double previewPerColor;

  /// Blank ball between two colors, so each one reads as separate.
  final double previewGap;

  /// "GO" pause after the last color, before the pointer moves.
  final double goDelay;

  /// Total frozen time before a boss round with [length] colors starts.
  double previewTotal(int length) =>
      intro + length * (previewPerColor + previewGap) + goDelay;
  final double zoneSize;
  final double speedFactor;
  final int stepPoints;
  final int clearBonus;

  bool isBossLevel(int level) => every > 0 && level > 0 && level % every == 0;
}

class WorldsConfig {
  WorldsConfig._(Map<String, dynamic> m)
    : every = _i(m, 'every'),
      tempoStep = _d(m, 'tempoStep'),
      maxTempo = _d(m, 'maxTempo');

  final int every;
  final double tempoStep;
  final double maxTempo;

  int worldFor(int level) => every <= 0 ? 0 : level ~/ every;
}

class RingRotationConfig {
  RingRotationConfig._(Map<String, dynamic> m)
    : minFraction = _d(m, 'minFractionOfPointer'),
      maxFraction = _d(m, 'maxFractionOfPointer');

  /// Ring speed as a fraction of pointer speed. Kept below 0.5 so the pointer
  /// always sweeps the ring in its own direction (see fairness rules).
  final double minFraction;
  final double maxFraction;
}

class ScoringConfig {
  ScoringConfig._(Map<String, dynamic> m)
    : goodPoints = _i(m, 'goodPoints'),
      perfectPoints = _i(m, 'perfectPoints'),
      perfectsPerMultiplierStep = _i(m, 'perfectsPerMultiplierStep'),
      maxMultiplier = _i(m, 'maxMultiplier');

  final int goodPoints;
  final int perfectPoints;
  final int perfectsPerMultiplierStep;
  final int maxMultiplier;
}

class CoinsConfig {
  CoinsConfig._(Map<String, dynamic> m)
    : scorePerCoin = _i(m, 'scorePerCoin'),
      coinZoneChance = _d(m, 'coinZoneChance'),
      coinZoneMinLevel = _i(m, 'coinZoneMinLevel'),
      coinZoneBonus = _i(m, 'coinZoneBonus');

  final int scorePerCoin;
  final double coinZoneChance;
  final int coinZoneMinLevel;
  final int coinZoneBonus;
}

class ContinueConfig {
  ContinueConfig._(Map<String, dynamic> m)
    : maxPerRun = _i(m, 'maxPerRun'),
      coinCost = _i(m, 'coinCost');

  final int maxPerRun;
  final int coinCost;
}

class AdsConfig {
  AdsConfig._(Map<String, dynamic> m)
    : interstitialEveryRuns = _i(m, 'interstitialEveryRuns'),
      noAdsFirstRuns = _i(m, 'noAdsFirstRuns');

  final int interstitialEveryRuns;
  final int noAdsFirstRuns;
}

class AnnounceConfig {
  AnnounceConfig._(Map<String, dynamic> m)
    : repeat = _ms(m, 'repeatMs'),
      shield = _ms(m, 'shieldMs');

  /// Pause before every later NOT / split round.
  final double repeat;

  /// Pause after a shield absorbs a miss.
  final double shield;
}
