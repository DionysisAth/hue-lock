import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../config/game_config.dart';
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

  /// Short "3-2-1" before play resumes (after a continue or app pause).
  countdown,
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
  });

  final Judgement judgement;
  final int points;
  final int multiplier;
  final int perfectStreak;
  final int coinBonus;
}

class NewBestEvent extends GameEvent {
  const NewBestEvent(this.score);
  final int score;
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

  Judgement? lastMiss;
  RunSummary? lastSummary;
  double _phaseStart = 0;
  double _countdownLeft = 0;

  /// Pointer position shown while idling on the home screen.
  double _idleAngle = 0;

  double get phaseElapsed => time - _phaseStart;
  double get countdownLeft => _countdownLeft;

  bool get canContinue =>
      phase == GamePhase.gameOver && continuesUsed < config.continues.maxPerRun;

  bool get canRestart =>
      phase == GamePhase.gameOver &&
      phaseElapsed >= config.timing.restartLockout;

  int get coinsEarned =>
      score ~/ math.max(1, config.coins.scorePerCoin) + zoneCoins;

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
    lastMiss = null;
    lastSummary = null;
    effects.clear();
    effects.glowTarget = 0;

    final pointer = round?.pointerAngleAt(time) ?? _idleAngle;
    final spec = _generator!.next(
      level: 0,
      pointerLocal: pointer,
      currentDir: 1,
      isFirst: true,
    );
    round = ActiveRound(
      spec: spec,
      startTime: time,
      pointerStart: pointer,
      ringStart: 0,
    );
    _setPhase(GamePhase.playing);
    _emit(RunStarted(this.seed));
  }

  void goHome() {
    if (round != null) _idleAngle = round!.pointerAngleAt(time);
    round = null;
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
        if (_countdownLeft <= 0) _setPhase(GamePhase.playing);
      case GamePhase.dying:
        if (phaseElapsed >= config.timing.deathFreeze) {
          _setPhase(GamePhase.gameOver);
          _emit(const GameOverShown());
        }
      case GamePhase.playing:
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
    final local = r.localPointerAt(t);
    final j = judgeTap(r.spec, local, config.timing);
    if (j.isHit) {
      _onHit(r, j, t);
    } else {
      _onMiss(r, j, t);
    }
    return j;
  }

  void _onHit(ActiveRound r, Judgement j, double t) {
    final s = config.scoring;
    int points;
    if (j.kind == HitKind.perfect) {
      perfects++;
      perfectStreak++;
      bestPerfectStreak = math.max(bestPerfectStreak, perfectStreak);
      multiplier = math.min(
        s.maxMultiplier,
        1 + perfectStreak ~/ math.max(1, s.perfectsPerMultiplierStep),
      );
      points = s.perfectPoints * multiplier;
    } else {
      perfectStreak = 0;
      multiplier = 1;
      points = s.goodPoints;
    }
    score += points;
    level++;
    final coinBonus = j.zone!.hasCoin ? config.coins.coinZoneBonus : 0;
    zoneCoins += coinBonus;

    // Juice.
    final worldAngle = r.ringAngleAt(t) + j.zone!.center;
    final perfect = j.kind == HitKind.perfect;
    effects.locks.add(
      LockFlash(worldAngle, j.zone!.width, j.zone!.color, perfect: perfect),
    );
    effects.burst(
      r.pointerAngleAt(t),
      j.zone!.color,
      count: perfect ? 22 : 10,
      power: perfect ? 1.4 : 0.9,
    );
    effects.hitPulse = 1;
    if (perfect) {
      effects.perfectFlash = 1;
      effects.texts.add(
        FloatingText(
          multiplier > 1 ? 'PERFECT x$multiplier' : 'PERFECT',
          j.zone!.color,
          big: true,
        ),
      );
    }
    if (coinBonus > 0) effects.texts.add(FloatingText('+$coinBonus coins', -1));
    effects.glowTarget = math.min(
      1.0,
      perfectStreak * 0.12 + math.min(level, 120) / 240,
    );

    _emit(
      HitEvent(
        judgement: j,
        points: points,
        multiplier: multiplier,
        perfectStreak: perfectStreak,
        coinBonus: coinBonus,
      ),
    );
    if (!newBestReached && bestAtRunStart > 0 && score > bestAtRunStart) {
      newBestReached = true;
      effects.texts.add(FloatingText('NEW BEST!', -1, life: 1.2, big: true));
      _emit(NewBestEvent(score));
    }

    // The pointer keeps moving; the next round starts from where it is.
    final spec = _generator!.next(
      level: level,
      pointerLocal: r.localPointerAt(t),
      currentDir: r.spec.pointerDir,
      previousColor: r.spec.targetColor,
    );
    assert(() {
      final problems = RoundGenerator.validate(
        config,
        spec,
        r.localPointerAt(t),
      );
      if (problems.isNotEmpty) debugPrint('Unfair round: $problems');
      return true;
    }());
    round = ActiveRound(
      spec: spec,
      startTime: t,
      pointerStart: r.pointerAngleAt(t),
      ringStart: r.ringAngleAt(t),
    );
    notifyListeners();
  }

  void _onMiss(ActiveRound r, Judgement j, double t) {
    r.frozenAt = t;
    lastMiss = j;
    perfectStreak = 0;
    multiplier = 1;
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
    final spec = _generator!.next(
      level: level,
      pointerLocal: old.localPointerAt(t),
      currentDir: old.spec.pointerDir,
      previousColor: old.spec.targetColor,
      isFirst: true,
    );
    round = ActiveRound(
      spec: spec,
      startTime: time,
      pointerStart: old.pointerAngleAt(t),
      ringStart: old.ringAngleAt(t),
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
    _countdownLeft = config.timing.continueCountdown;
    _setPhase(GamePhase.countdown);
  }
}
