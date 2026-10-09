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

/// First-time explanations, by mechanic. Shown with a pause the first time a
/// player ever meets each one (see `announce` in the config).
const intros = <String, (String, String)>{
  'intro': ('TAP ON ITS COLOR', 'before the fuse around the ball runs out'),
  'boss': ('BOSS ROUND', 'watch the colors, then hit them in order'),
  'not': ('NOT!', 'hit any color except this one'),
  'split': ('SPLIT', 'left color first, then right, in one lap'),
  'ghost': ('GHOST', 'zones blink: remember where they are'),
  'surge': ('SURGE', 'the pointer speeds up and slows down'),
  'spin': ('SPIN', 'the ring turns too'),
  'reverse': ('REVERSE', 'the pointer flips after each hit'),
  'greedy': ('GREEDY', 'thin gold zone = +5, or play it safe'),
  'powerup': ('POWER-UP', 'hit the target to collect it'),
};

/// Mechanics that change the rules: they also get a short pause every time.
const _alwaysPause = {'not', 'split'};

/// Optional extras: explained once, but never pause the game.
const _noPause = {'greedy', 'powerup'};

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

/// The player met a mechanic for the first time (persist it so the long
/// explanation is shown only once).
class IntroSeenEvent extends GameEvent {
  const IntroSeenEvent(this.name);
  final String name;
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
  bool _countdownNumber = false;
  bool _bossGoShown = false;
  double _bossIntro = 0;

  /// Mechanics this player has already had explained (persisted by the UI).
  final seen = <String>{};

  /// Pointer position shown while idling on the home screen.
  double _idleAngle = 0;

  double get phaseElapsed => time - _phaseStart;
  double get countdownLeft => _countdownLeft;

  /// True while a boss round shows its color sequence.
  bool get bossPreview => phase == GamePhase.countdown && _bossPreview;

  /// Whether the frozen countdown shows "3-2-1" (continue / app pause) or
  /// is a silent hold behind a banner.
  bool get showCountdownNumber =>
      phase == GamePhase.countdown && _countdownNumber;

  /// During a boss preview: index into the sequence being shown, or -1
  /// during the intro, the gaps between colors and the final "GO" pause.
  int get bossPreviewIndex {
    if (!bossPreview) return -1;
    final b = config.boss;
    final e = _countdownTotal - _countdownLeft - _bossIntro;
    if (e < 0) return -1;
    final slot = b.previewPerColor + b.previewGap;
    final i = (e / slot).floor();
    if (i >= round!.spec.ballColors.length) return -1;
    return e - i * slot < b.previewPerColor ? i : -1;
  }

  /// Boss preview finished showing colors (the "GO" pause).
  bool get _bossInGo {
    final b = config.boss;
    final shown =
        _bossIntro +
        round!.spec.ballColors.length * (b.previewPerColor + b.previewGap);
    return _countdownTotal - _countdownLeft >= shown;
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
    // Playing first: the first round may immediately freeze behind an intro.
    _setPhase(GamePhase.playing);
    _startRound(pointer: pointer, ring: 0, dir: 1, t: time, isFirst: true);
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
        if (_bossPreview && !_bossGoShown && _bossInGo) {
          _bossGoShown = true;
          effects.banner = Announcement(
            'GO!',
            subtitle: 'hit them in order',
            life: config.boss.goDelay + 0.6,
          );
        }
        if (_countdownLeft <= 0) {
          _bossPreview = false;
          _countdownNumber = false;
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
    _announce(r, dir, isFirst: isFirst);
  }

  /// Freezes the round behind a banner when it brings something the player
  /// cannot be expected to react to instantly: a boss sequence, a rule
  /// change (NOT / split) or a mechanic they have never seen.
  void _announce(ActiveRound r, int previousDir, {required bool isFirst}) {
    final spec = r.spec;
    final a = config.announce;
    if (spec.kind == RoundKind.boss) {
      final firstBoss = !seen.contains('boss');
      _markSeen('boss');
      // The first boss ever gets a longer intro to read the explanation.
      _bossIntro = config.boss.intro + (firstBoss ? 1.0 : 0);
      _bossGoShown = false;
      final b = config.boss;
      _hold(
        _bossIntro +
            spec.ballColors.length * (b.previewPerColor + b.previewGap) +
            b.goDelay,
        boss: true,
      );
      effects.banner = Announcement(
        'BOSS ROUND',
        subtitle: firstBoss ? intros['boss']!.$2 : 'watch the colors',
        life: _bossIntro + 0.2,
      );
      _emit(const BossEvent(cleared: false));
      return;
    }

    // Everything this round brings, most important first.
    final found = <String>[
      if (isFirst && level == 0 && !seen.contains('intro')) 'intro',
      if (spec.kind == RoundKind.inverted) 'not',
      if (spec.kind == RoundKind.split) 'split',
      if (spec.ghost) 'ghost',
      if (spec.pulseAmplitude > 0) 'surge',
      if (spec.ringSpeed != 0) 'spin',
      if (!isFirst && level > 0 && spec.pointerDir != previousDir) 'reverse',
      if (spec.zones.any((z) => z.isBonus)) 'greedy',
      if (spec.zones.any((z) => z.powerUp != null)) 'powerup',
    ];
    var hold = 0.0;
    String? banner;
    var bannerIsNew = false;
    for (final name in found) {
      final isNew = !seen.contains(name);
      if (isNew) {
        _markSeen(name);
        if (!_noPause.contains(name)) hold = math.max(hold, a.firstTime);
      } else if (_alwaysPause.contains(name)) {
        hold = math.max(hold, a.repeat);
      } else {
        continue;
      }
      if (banner == null) {
        banner = name;
        bannerIsNew = isNew;
      }
    }
    if (banner == null) return;
    final (title, subtitle) = intros[banner]!;
    final color = banner == 'not' ? spec.ballColors.first : -1;
    effects.banner = Announcement(
      title,
      subtitle: subtitle,
      color: color,
      life: math.max(hold, bannerIsNew ? 2.0 : 1.0) + 0.4,
    );
    if (hold > 0) _hold(hold);
  }

  void _markSeen(String name) {
    if (seen.add(name)) _emit(IntroSeenEvent(name));
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
    // Later steps of a split / boss round need a moment to switch colors:
    // if the next zone is closer than that, it is due on the next pass.
    final reaction = r.step > 0
        ? config.timing.splitSecondLead
        : config.timing.minReaction;
    final reach = reaction * spec.maxRelativeSpeed;
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
      _emit(const ShieldSavedEvent());
      _startRound(
        pointer: r.pointerAngleAt(t),
        ring: r.ringAngleAt(t),
        dir: r.spec.pointerDir,
        t: t,
        previousColor: r.spec.targetColor,
        isFirst: true,
      );
      // A moment to recover before the pointer moves again.
      if (phase != GamePhase.countdown) _hold(config.announce.shield);
      effects.banner = Announcement(
        'SHIELD SAVED YOU',
        subtitle: 'get ready',
        color: 1,
        life: config.announce.shield + 0.3,
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
    _hold(config.timing.continueCountdown, number: true);
  }

  /// Freezes the round for [seconds] (the pointer and ring stand still).
  void _hold(double seconds, {bool number = false, bool boss = false}) {
    _bossPreview = boss;
    _countdownNumber = number;
    _countdownLeft = seconds;
    _countdownTotal = seconds;
    _setPhase(GamePhase.countdown);
  }
}
