import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../config/game_config.dart';
import '../core/angles.dart';
import 'effects.dart';
import 'hit_judge.dart';
import 'round.dart';
import 'round_generator.dart';

enum GamePhase {
  /// Home screen; the ring idles in the background.
  home,
  playing,

  /// Freeze-frame right after a miss.
  dying,
  gameOver,

  /// The round is frozen: "3-2-1" after a continue / app pause, or the
  /// color sequence preview before a boss round.
  countdown,
}

/// Names of the stages a run travels through (one every
/// `worlds.every` levels); the list repeats with a "+" after the last one.
const worldNames = ['DAWN', 'NEON REEF', 'EMBER', 'AURORA', 'NEBULA', 'VOID'];

String worldName(int world) {
  final name = worldNames[world % worldNames.length];
  return world >= worldNames.length ? '$name+' : name;
}

sealed class GameEvent {
  const GameEvent();
}

class RunStarted extends GameEvent {
  const RunStarted(this.seed);
  final int seed;
}

class HitEvent extends GameEvent {
  const HitEvent({
    required this.judgement,
    required this.points,
    required this.multiplier,
    required this.perfectStreak,
    required this.coinBonus,
    this.roundComplete = true,
  });

  final Judgement judgement;
  final int points;
  final int multiplier;
  final int perfectStreak;
  final int coinBonus;

  /// False for the first step(s) of a split or boss round.
  final bool roundComplete;
}

class NewBestEvent extends GameEvent {
  const NewBestEvent(this.score);
  final int score;
}

class FeverEvent extends GameEvent {
  const FeverEvent(this.active);
  final bool active;
}

class PowerUpEvent extends GameEvent {
  const PowerUpEvent(this.powerUp);
  final PowerUp powerUp;
}

class ShieldSavedEvent extends GameEvent {
  const ShieldSavedEvent();
}

class SetClearedEvent extends GameEvent {
  const SetClearedEvent(this.locks, this.bonus);
  final int locks;
  final int bonus;
}

class BossEvent extends GameEvent {
  const BossEvent({required this.cleared});
  final bool cleared;
}

class WorldEvent extends GameEvent {
  const WorldEvent(this.world);
  final int world;
}

class MissEvent extends GameEvent {
  const MissEvent(this.judgement, this.summary);
  final Judgement judgement;
  final RunSummary summary;
}

class GameOverShown extends GameEvent {
  const GameOverShown();
}

class ContinuedEvent extends GameEvent {
  const ContinuedEvent();
}

/// Snapshot of a run at the moment of death.
class RunSummary {
  const RunSummary({
    required this.score,
    required this.level,
    required this.perfects,
    required this.bestPerfectStreak,
    required this.coinsEarned,
    required this.newCoins,
    required this.duration,
    required this.stageName,
    required this.world,
    required this.continuesUsed,
    required this.seed,
  });

  final int score;
  final int level;
  final int perfects;
  final int bestPerfectStreak;

  /// Coins earned by the whole run so far.
  final int coinsEarned;

  /// Coins earned since the previous death (to bank now).
  final int newCoins;
  final double duration;
  final String stageName;
  final int world;
  final int continuesUsed;
  final int seed;
}

/// Pure game logic: no Flutter widgets, no wall clock. Time only moves when
/// [tick] is called, and taps carry their own game-time timestamp, so the
/// result never depends on frame rate.
class GameEngine extends ChangeNotifier {
  GameEngine(this.config, {int Function()? seedSource})
    : _seedSource = seedSource ?? (() => DateTime.now().microsecondsSinceEpoch);

  final GameConfig config;
  final int Function() _seedSource;
  final effects = Effects();

  /// Receives discrete events (sound, haptics, saving, analytics).
  void Function(GameEvent event)? onEvent;

  GamePhase phase = GamePhase.home;

  /// Game clock in seconds.
  double time = 0;
  ActiveRound? round;
  RoundGenerator? _generator;
  int seed = 0;

  int score = 0;
  int level = 0;
  int perfectStreak = 0;
  int multiplier = 1;
  int perfects = 0;
  int bestPerfectStreak = 0;
  int zoneCoins = 0;
  int continuesUsed = 0;
  int coinsBanked = 0;
  double runStart = 0;
  int bestAtRunStart = 0;
  bool newBestReached = false;

  /// Fever: a Perfect streak doubles points and speeds the pointer up.
  bool fever = false;

  /// Power-ups: one stored shield, and rounds left of Slow-mo / Wide.
  bool shield = false;
  int slowRounds = 0;
  int wideRounds = 0;

  /// Lock sets: clear [setSize] rounds in a row for a bonus.
  int setSize = 1;
  int setDone = 0;

  /// Current stage of the run (changes every `worlds.every` levels).
  int world = 0;

  Judgement? lastMiss;
  RunSummary? lastSummary;
  double _phaseStart = 0;
  double _countdownLeft = 0;
  double _countdownTotal = 0;
  bool _bossPreview = false;

  /// Pointer position shown while idling on the home screen.
  double _idleAngle = 0;

  double get phaseElapsed => time - _phaseStart;
  double get countdownLeft => _countdownLeft;

  /// True while a boss round shows its color sequence.
  bool get bossPreview => phase == GamePhase.countdown && _bossPreview;

  /// During a boss preview: index into the sequence being shown, or -1
  /// in the short gap after it.
  int get bossPreviewIndex {
    if (!bossPreview) return -1;
    final i = ((_countdownTotal - _countdownLeft) / config.boss.previewPerColor)
        .floor();
    return i < round!.spec.ballColors.length ? i : -1;
  }

  bool get canContinue =>
      phase == GamePhase.gameOver && continuesUsed < config.continues.maxPerRun;

  bool get canRestart =>
      phase == GamePhase.gameOver &&
      phaseElapsed >= config.timing.restartLockout;

  int get coinsEarned =>
      score ~/ math.max(1, config.coins.scorePerCoin) + zoneCoins;

  /// Fraction of the current step's fuse left (1 = full).
  double get fuse => phase == GamePhase.playing || phase == GamePhase.countdown
      ? (round?.fuseAt(time) ?? 1)
      : (round?.fuseAt(round?.frozenAt ?? time) ?? 1);

  double pointerAngle() => round?.pointerAngleAt(time) ?? _idleAngle;

  double ringAngle() => round?.ringAngleAt(time) ?? 0;

  void _setPhase(GamePhase p) {
    phase = p;
    _phaseStart = time;
    notifyListeners();
  }

  void _emit(GameEvent e) => onEvent?.call(e);

  /// Starts a new run immediately (no scene reload, just state reset).
  void startRun({required int best, int? seed}) {
    this.seed = seed ?? (_seedSource() & 0x7FFFFFFF);
    _generator = RoundGenerator(config, this.seed);
    score = 0;
    level = 0;
    perfectStreak = 0;
    multiplier = 1;
    perfects = 0;
    bestPerfectStreak = 0;
    zoneCoins = 0;
    continuesUsed = 0;
    coinsBanked = 0;
    runStart = time;
    bestAtRunStart = best;
    newBestReached = false;
    fever = false;
    shield = false;
    slowRounds = 0;
    wideRounds = 0;
    world = 0;
    lastMiss = null;
    lastSummary = null;
    effects.clear();
    effects.glowTarget = 0;
    _newSet();

    final pointer = round?.pointerAngleAt(time) ?? _idleAngle;
    _startRound(pointer: pointer, ring: 0, dir: 1, t: time, isFirst: true);
    _setPhase(GamePhase.playing);
    _emit(RunStarted(this.seed));
  }

  void goHome() {
    if (round != null) _idleAngle = round!.pointerAngleAt(time);
    round = null;
    fever = false;
    effects.clear();
    effects.glowTarget = 0;
    _setPhase(GamePhase.home);
  }

  void tick(double dt) {
    if (dt <= 0) return;
    time += dt;
    effects.update(dt);
    switch (phase) {
      case GamePhase.home:
        _idleAngle += dt * 0.9;
      case GamePhase.countdown:
        // Freeze the round: shifting its start keeps every angle constant.
        round?.startTime += dt;
        _countdownLeft -= dt;
        if (_countdownLeft <= 0) {
          _bossPreview = false;
          _setPhase(GamePhase.playing);
        }
      case GamePhase.playing:
        final r = round;
        if (r != null && r.travelAt(time) > r.stepDeadline) {
          // The fuse burnt out: the pointer passed the target untouched.
          _onMiss(r, Judgement.timeout(r.localPointerAt(time)), time);
        }
      case GamePhase.dying:
        if (phaseElapsed >= config.timing.deathFreeze) {
          _setPhase(GamePhase.gameOver);
          _emit(const GameOverShown());
        }
      case GamePhase.gameOver:
        break;
    }
  }

  /// Handles a tap that happened at game time [tapTime] (already mapped from
  /// the input event's timestamp). Returns the judgement for gameplay taps.
  Judgement? tap(double tapTime) {
    switch (phase) {
      case GamePhase.playing:
        return _judge(tapTime);
      case GamePhase.gameOver:
        if (canRestart) startRun(best: math.max(bestAtRunStart, score));
        return null;
      case GamePhase.home:
      case GamePhase.dying:
      case GamePhase.countdown:
        return null;
    }
  }

  Judgement _judge(double tapTime) {
    final r = round!;
    final t = math.max(tapTime, r.startTime);
    final j = judgeTap(
      r.spec,
      r.localPointerAt(t),
      config.timing,
      step: r.step,
      consumed: r.consumed,
      relSpeed: r.relativeSpeedAt(t),
    );
    if (j.isHit) {
      _onHit(r, j, t);
    } else {
      _onMiss(r, j, t);
    }
    return j;
  }

  void _onHit(ActiveRound r, Judgement j, double t) {
    final s = config.scoring;
    final zone = j.zone!;
    final perfect = j.kind == HitKind.perfect;
    final boss = r.spec.kind == RoundKind.boss;

    // Fever applies from the hit after it starts.
    final feverBefore = fever;
    if (perfect) {
      perfects++;
      perfectStreak++;
      bestPerfectStreak = math.max(bestPerfectStreak, perfectStreak);
      multiplier = math.min(
        s.maxMultiplier,
        1 + perfectStreak ~/ math.max(1, s.perfectsPerMultiplierStep),
      );
    } else {
      perfectStreak = 0;
      multiplier = 1;
    }
    var base = perfect ? s.perfectPoints : s.goodPoints;
    if (zone.isBonus) base += config.bonusZone.points;
    if (boss) base += config.boss.stepPoints;
    var points = base * multiplier;
    if (feverBefore) points *= config.fever.pointsMultiplier;
    score += points;

    final coinBonus = zone.hasCoin ? config.coins.coinZoneBonus : 0;
    zoneCoins += coinBonus;

    // Juice.
    final worldAngle = r.ringAngleAt(t) + zone.center;
    effects.locks.add(
      LockFlash(worldAngle, zone.width, zone.color, perfect: perfect),
    );
    effects.burst(
      r.pointerAngleAt(t),
      zone.color,
      count: perfect ? 22 : 10,
      power: perfect ? 1.4 : 0.9,
    );
    effects.hitPulse = 1;
    if (zone.isBonus) {
      effects.texts.add(FloatingText('GREEDY +$points', zone.color, big: true));
    } else if (perfect) {
      effects.perfectFlash = 1;
      effects.texts.add(
        FloatingText(
          multiplier > 1 ? 'PERFECT x$multiplier' : 'PERFECT',
          zone.color,
          big: true,
        ),
      );
    }
    if (coinBonus > 0) effects.texts.add(FloatingText('+$coinBonus coins', -1));

    if (perfect && !fever && perfectStreak >= config.fever.perfectStreak) {
      fever = true;
      effects.banner = Announcement(
        'FEVER!',
        subtitle: 'x${config.fever.pointsMultiplier} points',
        color: zone.color,
        life: 1.2,
      );
      _emit(const FeverEvent(true));
    } else if (!perfect && fever) {
      _endFever();
    }

    final p = zone.powerUp;
    if (p != null) _collect(p);

    final lastStep = r.step == r.spec.steps.length - 1;
    _emit(
      HitEvent(
        judgement: j,
        points: points,
        multiplier: multiplier,
        perfectStreak: perfectStreak,
        coinBonus: coinBonus,
        roundComplete: lastStep,
      ),
    );
    if (!newBestReached && bestAtRunStart > 0 && score > bestAtRunStart) {
      newBestReached = true;
      effects.texts.add(FloatingText('NEW BEST!', -1, life: 1.2, big: true));
      _emit(NewBestEvent(score));
    }

    if (!lastStep) {
      // Split / boss: the same round goes on with the next color.
      r.consumed.add(j.zoneIndex!);
      r.step++;
      _armStep(r, t);
      notifyListeners();
      return;
    }

    // Round complete.
    level++;
    if (slowRounds > 0) slowRounds--;
    if (wideRounds > 0) wideRounds--;
    if (boss) {
      score += config.boss.clearBonus;
      effects.banner = Announcement(
        'BOSS CLEARED',
        subtitle: '+${config.boss.clearBonus}',
        life: 1.3,
      );
      _emit(const BossEvent(cleared: true));
    }
    setDone++;
    if (setDone >= setSize) {
      if (setSize > 1) {
        final bonus = setSize * config.setBonusPerLock;
        score += bonus;
        effects.texts.add(FloatingText('UNLOCKED +$bonus', -1, big: true));
        _emit(SetClearedEvent(setSize, bonus));
      }
      _newSet();
    }
    final w = config.worlds.worldFor(level);
    if (w != world) {
      world = w;
      effects.banner = Announcement(
        'STAGE ${w + 1}',
        subtitle: worldName(w),
        life: 1.8,
      );
      _emit(WorldEvent(w));
    }
    effects.glowTarget = math.min(
      1.0,
      perfectStreak * 0.12 + math.min(level, 120) / 240 + (fever ? 0.4 : 0),
    );

    // The pointer keeps moving; the next round starts from where it is.
    _startRound(
      pointer: r.pointerAngleAt(t),
      ring: r.ringAngleAt(t),
      dir: r.spec.pointerDir,
      t: t,
      previousColor: r.spec.targetColor,
    );
    notifyListeners();
  }

  void _collect(PowerUp p) {
    final c = config.powerUps;
    switch (p) {
      case PowerUp.shield:
        shield = true;
        effects.texts.add(FloatingText('SHIELD', -1, big: true));
      case PowerUp.slow:
        slowRounds = c.slowRounds;
        effects.texts.add(FloatingText('SLOW-MO', -1, big: true));
      case PowerUp.wide:
        wideRounds = c.wideRounds;
        effects.texts.add(FloatingText('WIDE', -1, big: true));
    }
    _emit(PowerUpEvent(p));
  }

  void _endFever() {
    if (!fever) return;
    fever = false;
    _emit(const FeverEvent(false));
  }

  void _newSet() {
    final stage = config.stageFor(level);
    final spread = math.max(1, stage.maxLocks - stage.minLocks + 1);
    setDone = 0;
    setSize = stage.minLocks + (seed + level * 7) % spread;
  }

  /// Creates the next round at time [t] from the given pointer/ring angles.
  void _startRound({
    required double pointer,
    required double ring,
    required int dir,
    required double t,
    int? previousColor,
    bool isFirst = false,
  }) {
    final pu = config.powerUps;
    var speed = 1.0;
    if (fever) speed *= config.fever.speedFactor;
    if (slowRounds > 0) speed *= pu.slowFactor;
    final local = wrapAngle(pointer - ring);
    final spec = _generator!.next(
      level: level,
      pointerLocal: local,
      currentDir: dir,
      previousColor: previousColor,
      isFirst: isFirst,
      speedFactor: speed,
      sizeFactor: wideRounds > 0 ? pu.wideFactor : 1,
    );
    assert(() {
      final problems = RoundGenerator.validate(
        config,
        spec,
        local,
        isFirst: isFirst,
      );
      if (problems.isNotEmpty) debugPrint('Unfair round: $problems');
      return true;
    }());
    final r = ActiveRound(
      spec: spec,
      startTime: t,
      pointerStart: pointer,
      ringStart: ring,
    );
    round = r;
    _armStep(r, t);
    if (spec.kind == RoundKind.boss) {
      // Show the sequence, then go.
      _bossPreview = true;
      _countdownTotal =
          spec.ballColors.length * config.boss.previewPerColor + 0.45;
      _countdownLeft = _countdownTotal;
      effects.banner = Announcement(
        'BOSS ROUND',
        subtitle: 'remember the colors',
        life: _countdownTotal,
      );
      _emit(const BossEvent(cleared: false));
      _setPhase(GamePhase.countdown);
    }
  }

  /// Arms the one-lap fuse for the round's current step: it runs out when
  /// the pointer has passed the step's primary zone on its first fair pass.
  void _armStep(ActiveRound r, double t) {
    final travel = r.travelAt(t);
    r.stepStartTravel = travel;
    if (!config.oneLap) {
      r.stepDeadline = double.infinity;
      return;
    }
    final spec = r.spec;
    final z = r.currentPrimary;
    final dir = spec.pointerDir;
    final nearEdge = wrapAngle(z.center - dir * z.halfWidth);
    var d = travelDistance(r.localPointerAt(t), nearEdge, dir);
    final reach = config.timing.minReaction * spec.maxRelativeSpeed;
    if (d < reach && !z.contains(r.localPointerAt(t))) d += tau;
    r.stepDeadline =
        travel + d + z.width + config.timing.grace * spec.maxRelativeSpeed;
  }

  void _onMiss(ActiveRound r, Judgement j, double t) {
    if (shield) {
      // The shield absorbs the miss: fresh, fair round from right here.
      shield = false;
      perfectStreak = 0;
      multiplier = 1;
      _endFever();
      effects.shieldFlash = 1;
      effects.shake = 0.5;
      effects.texts.add(FloatingText('SHIELD SAVED YOU', -1, big: true));
      _emit(const ShieldSavedEvent());
      _startRound(
        pointer: r.pointerAngleAt(t),
        ring: r.ringAngleAt(t),
        dir: r.spec.pointerDir,
        t: t,
        previousColor: r.spec.targetColor,
        isFirst: true,
      );
      notifyListeners();
      return;
    }
    r.frozenAt = t;
    lastMiss = j;
    perfectStreak = 0;
    multiplier = 1;
    _endFever();
    effects.shake = 1;
    effects.glowTarget = 0;
    final earned = coinsEarned;
    final summary = RunSummary(
      score: score,
      level: level,
      perfects: perfects,
      bestPerfectStreak: bestPerfectStreak,
      coinsEarned: earned,
      newCoins: earned - coinsBanked,
      duration: t - runStart,
      stageName: r.spec.stageName,
      world: world,
      continuesUsed: continuesUsed,
      seed: seed,
    );
    coinsBanked = earned;
    lastSummary = summary;
    _setPhase(GamePhase.dying);
    _emit(MissEvent(j, summary));
  }

  /// Continues the failed run once: a fresh, fair round from the pointer's
  /// current spot, after a short countdown.
  bool continueRun() {
    if (!canContinue) return false;
    final old = round!;
    final t = old.frozenAt ?? time;
    continuesUsed++;
    lastMiss = null;
    _startRound(
      pointer: old.pointerAngleAt(t),
      ring: old.ringAngleAt(t),
      dir: old.spec.pointerDir,
      t: time,
      previousColor: old.spec.targetColor,
      isFirst: true,
    );
    _startCountdown();
    _emit(const ContinuedEvent());
    return true;
  }

  /// Called when the app goes to the background mid-run.
  void pause() {
    if (phase == GamePhase.playing) _startCountdown();
  }

  void _startCountdown() {
    _bossPreview = false;
    _countdownLeft = config.timing.continueCountdown;
    _countdownTotal = _countdownLeft;
    _setPhase(GamePhase.countdown);
  }
}
