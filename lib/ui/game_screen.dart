import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:share_plus/share_plus.dart';

import '../app.dart';
import '../game/effects.dart';
import '../game/game_engine.dart';
import '../game/hit_judge.dart';
import '../meta/levels.dart';
import '../meta/progression.dart';
import '../services/profile_store.dart';
import '../render/ball_skins.dart';
import '../render/game_painter.dart';
import '../render/palette.dart';
import '../render/ring_themes.dart';
import '../render/text_sprites.dart';
import '../services/feedback.dart';
import 'game_over_overlay.dart';
import 'home_overlay.dart';
import 'how_to_play_screen.dart';
import 'hud.dart';
import 'levels_screen.dart';
import 'mode_dialogs.dart';
import 'perk_overlay.dart';
import 'progress_screen.dart';
import 'settings_screen.dart';
import 'shop_screen.dart';

class _FrameNotifier extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// The single game screen. Home, HUD, game-over and countdown are overlays on
/// one persistent canvas, so restarting never reloads anything.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AppServices s;
  GameEngine? _engine;
  late final Ticker _ticker;
  final _frame = _FrameNotifier();
  final _sinceFrame = Stopwatch();
  final _shotKey = GlobalKey();
  Duration? _lastFrameStamp;
  bool _doubledThisRun = false;
  bool _adBusy = false;

  /// Level being played (Levels mode).
  LevelDef? _level;
  int _starsGained = 0;

  /// Level mode: goals met on this level before the last run (bit mask).
  int _levelGoalsBefore = 0;

  /// Level mode: chapter rewards the last run unlocked.
  List<(ChapterDef, ChapterReward)> _chapterRewards = const [];

  /// Short messages (mission done, achievement, level up) shown at the top.
  final _toasts = <String>[];

  GameEngine get engine => _engine!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_engine == null) {
      s = Services.of(context);
      _engine = GameEngine(s.config)..onEvent = _onEvent;
      s.profile.update(ensureMissions);
      _ticker.start();
      _updateMusic();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _offerDailyReward();
        if (s.warmUpEffects) {
          Future<void>.delayed(const Duration(milliseconds: 600), _warmUp);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _engine?.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // Never let a run continue while the player can't see it.
      engine.pause();
      _lastFrameStamp = null;
      if (state != AppLifecycleState.inactive) s.music.suspend();
      if (state == AppLifecycleState.paused) {
        s.gameServices.saveProfile(s.profile.profile);
      }
    } else {
      s.music.resume();
    }
  }

  /// Renders every effect once off-screen at startup, so their shaders are
  /// compiled before the first Perfect (no stutter on older GPUs).
  Future<void> _warmUp() async {
    if (!mounted) return;
    final e = GameEngine(s.config)..seen.addAll(intros.keys);
    e.startRun(best: 0, seed: 1);
    final fx = e.effects
      ..perfectFlash = 1
      ..edgeFlash = 1
      ..zoom = 1
      ..ringPulse = 0.5
      ..shieldFlash = 1
      ..ballMorph = 0.5
      ..glow = 1
      ..banner = Announcement('WARM UP', subtitle: 'warm up');
    fx.shatter(0, 0.5, 0);
    fx.sparkle(0);
    fx.burst(0, 1);
    fx.confetti(count: 6);
    fx.waves.add(Shockwave(0, 0, 2));
    fx.locks.add(LockFlash(0, 0.5, 3, perfect: true));
    fx.texts.add(FloatingText('WARM', 1, huge: true));
    e
      ..multiplier = 5
      ..shield = true;
    try {
      for (final theme in ringThemes) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..scale(0.25);
        GamePainter(
          engine: e,
          theme: theme,
          skin: ballSkins.first,
          palette: HuePalette.standard,
          colorblind: true,
          repaint: _frame,
          pixelRatio: 1,
        ).paint(canvas, const Size(400, 860));
        final picture = recorder.endRecording();
        final image = await picture.toImage(100, 215);
        image.dispose();
        picture.dispose();
      }
      // The texts every Perfect shows, as ready-made sprites.
      if (!mounted) return;
      final p = s.profile.profile;
      final theme = ringThemeById(p.theme);
      final palette = HuePalette.of(colorblind: p.colorblind);
      final dpr = View.of(context).devicePixelRatio;
      for (var c = 0; c < 4; c++) {
        for (final word in [
          'PERFECT',
          for (var m = 2; m <= s.config.scoring.maxMultiplier; m++)
            'PERFECT x$m',
        ]) {
          TextSprites.get(
            word,
            color: palette[c],
            fontSize: 30,
            glow: theme.dark ? 12 : 0,
            pixelRatio: dpr,
          );
        }
      }
      // Combo breaks happen mid-run too.
      TextSprites.get(
        'COMBO LOST',
        color: theme.text,
        fontSize: 20,
        glow: theme.dark ? 12 : 0,
        pixelRatio: dpr,
      );
      for (var m = 2; m < s.config.scoring.maxMultiplier; m++) {
        TextSprites.get(
          'COMBO SAVED x$m',
          color: palette[2],
          fontSize: 20,
          glow: theme.dark ? 12 : 0,
          pixelRatio: dpr,
        );
      }
    } catch (err) {
      debugPrint('Effect warm-up failed: $err');
    }
    e.dispose();
  }

  void _offerDailyReward() {
    final p = s.profile.profile;
    if (!mounted || p.totalRuns == 0) return;
    if (!canClaimDailyReward(p, DateTime.now())) return;
    DailyReward? reward;
    s.profile.update((p) => reward = claimDailyReward(p, DateTime.now()));
    if (reward == null) return;
    s.audio.play(Sfx.coin);
    showDailyRewardDialog(
      context,
      theme: ringThemeById(p.theme),
      reward: reward!,
    );
  }

  /// Music builds with the combo: pad and bass at the start, drums once
  /// the run is going, the driving bass at combo x2 and the full mix from
  /// combo x4. A broken combo drops it back.
  void _updateMusic() {
    final e = engine;
    final int intensity;
    if (e.phase == GamePhase.home || e.mode == RunMode.zen) {
      intensity = 1;
    } else if (e.multiplier >= 4) {
      intensity = 4;
    } else {
      final base = e.level >= 8 ? 2 : 1;
      intensity = math.min(3, base + (e.multiplier >= 2 ? 1 : 0));
    }
    s.music.setIntensity(intensity);
  }

  void _updateTempo() {
    final w = s.config.worlds;
    s.music.setTempo(math.min(w.maxTempo, 1 + w.tempoStep * engine.world));
  }

  void _onTick(Duration _) {
    final stamp = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    final last = _lastFrameStamp;
    _lastFrameStamp = stamp;
    _sinceFrame
      ..reset()
      ..start();
    if (last == null) return;
    final dt = (stamp - last).inMicroseconds / 1e6;
    if (dt > 0.5) {
      // A long stall (app switch, debugger): treat it as a pause.
      engine.pause();
      return;
    }
    engine.tick(dt);
    _frame.ping();
  }

  /// Maps the input event's own timestamp onto the game clock, so the hit is
  /// judged where the pointer was when the finger landed, not at the next
  /// frame.
  double _tapTime(PointerDownEvent e) {
    final last = _lastFrameStamp;
    if (last != null) {
      final delta = (e.timeStamp - last).inMicroseconds / 1e6;
      if (delta >= -s.config.timing.maxTapLookback && delta <= 0.1) {
        return engine.time + delta;
      }
    }
    // Timestamp unusable (clock mismatch): best estimate is "now".
    return engine.time + math.min(_sinceFrame.elapsedMicroseconds / 1e6, 0.05);
  }

  void _onPointerDown(PointerDownEvent e) {
    if (_adBusy) return;
    switch (engine.phase) {
      case GamePhase.playing:
        engine.tap(_tapTime(e));
      case GamePhase.home:
        _startEndless();
      case GamePhase.gameOver:
        if (engine.canRestart && _canRetry) _restart();
      case GamePhase.dying:
      case GamePhase.countdown:
      case GamePhase.perk:
        break;
    }
  }

  // ---------------------------------------------------------------------
  // Starting runs
  // ---------------------------------------------------------------------

  void _prepare() {
    engine.seen
      ..clear()
      ..addAll(s.profile.profile.seenIntros);
    _starsGained = 0;
  }

  void _startEndless() {
    _prepare();
    _level = null;
    engine.startRun(best: s.profile.profile.bestScore);
  }

  void _startZen() {
    _prepare();
    _level = null;
    engine.startRun(best: 0, mode: RunMode.zen);
  }

  String get _today => dailyChallengeDay(DateTime.now().toUtc());

  int get _dailyLeft {
    final p = s.profile.profile;
    return p.dailyDay == _today ? dailyAttemptsLeft(p) : dailyFreeAttempts;
  }

  void _startDaily() {
    s.profile.update((p) => rollDaily(p, _today));
    if (dailyAttemptsLeft(s.profile.profile) <= 0) return;
    s.profile.update((p) => p.dailyAttempts++);
    _prepare();
    _level = null;
    engine.startRun(
      best: s.profile.profile.dailyBest,
      seed: dailySeed(_today),
      mode: RunMode.daily,
    );
  }

  void _startDuel(int seed, int target) {
    _prepare();
    _level = null;
    engine.startRun(best: 0, seed: seed, mode: RunMode.duel, beatScore: target);
  }

  void _startLevel(LevelDef level) {
    _prepare();
    _level = level;
    _levelGoalsBefore = levelGoalsOf(s.profile.profile, level.id);
    _chapterRewards = const [];
    engine.startRun(
      best: 0,
      seed: level.seed,
      mode: RunMode.level,
      config: level.configFrom(s.config),
      targetRounds: level.targets,
      starGoals: level.goals,
    );
  }

  /// "Tap to retry" is allowed (Daily needs an attempt left).
  bool get _canRetry => engine.mode != RunMode.daily || _dailyLeft > 0;

  void _restart() {
    switch (engine.mode) {
      case RunMode.daily:
        _startDaily();
      case RunMode.level:
        _startLevel(_level!);
      case RunMode.endless:
        _prepare();
        engine.restart(best: s.profile.profile.bestScore);
      case RunMode.zen:
      case RunMode.duel:
        _prepare();
        engine.restart(best: 0);
    }
  }

  // ---------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------

  void _onEvent(GameEvent e) {
    switch (e) {
      case RunStarted():
        _doubledThisRun = false;
        s.profile.update((p) {
          p.totalRuns++;
          p.runsSinceInterstitial++;
        });
        s.analytics.log('run_start', {
          'run': s.profile.profile.totalRuns,
          'mode': engine.mode.name,
        });
        _updateTempo();
        _updateMusic();
      case HitEvent(:final judgement, :final perfectStreak, :final coinBonus):
        _updateMusic();
        if (judgement.kind == HitKind.perfect) {
          s.audio.playPerfect(perfectStreak);
          s.haptics.perfect();
        } else {
          s.audio.play(Sfx.hit);
          s.haptics.hit();
        }
        if (coinBonus > 0) s.audio.play(Sfx.coin);
      case NewBestEvent():
        s.audio.play(Sfx.newBest);
        s.haptics.celebrate();
      case ComboUpEvent():
        s.audio.play(Sfx.comboUp);
      case ComboLostEvent():
        s.audio.play(Sfx.comboLost);
        _updateMusic();
      case PerkOfferEvent():
        s.haptics.celebrate();
      case PerkChosenEvent(:final perk):
        s.audio.play(Sfx.powerUp);
        s.haptics.hit();
        s.analytics.log('perk', {'perk': perk.name, 'level': engine.level});
      case StreakEvent():
        s.audio.play(Sfx.streak);
        s.haptics.celebrate();
      case PowerUpEvent(:final powerUp):
        s.audio.play(Sfx.powerUp);
        s.analytics.log('power_up', {'type': powerUp.name});
      case ShieldSavedEvent():
        s.audio.play(Sfx.shield);
        s.haptics.fail();
      case ZenMissEvent():
        s.audio.play(Sfx.ui);
        s.haptics.hit();
      case SetClearedEvent():
        s.audio.play(Sfx.coin);
      case BossEvent(:final cleared):
        s.audio.play(cleared ? Sfx.stage : Sfx.boss);
        if (!cleared) s.analytics.log('boss_start', {'level': engine.level});
      case WorldEvent(:final world):
        s.audio.play(Sfx.stage);
        s.analytics.log('stage_reached', {'stage': world + 1});
        _updateTempo();
      case MissEvent(:final judgement, :final summary):
        s.music.cut();
        s.audio.play(Sfx.fail);
        s.haptics.fail();
        s.profile.update((p) {
          if (summary.mode == RunMode.endless) {
            p.bestScore = math.max(p.bestScore, summary.score);
          }
          if (summary.mode == RunMode.daily) {
            p.dailyBest = math.max(p.dailyBest, summary.score);
          }
          p.coins += summary.newCoins;
        });
        s.analytics.log('run_end', {
          'mode': summary.mode.name,
          'score': summary.score,
          'level': summary.level,
          'stage': summary.stageName,
          'duration_s': summary.duration.toStringAsFixed(1),
          'perfects': summary.perfects,
          'near_miss': judgement.nearMiss,
          'wrong_color': judgement.wrongZone != null,
          'timeout': judgement.timeout,
          'stage_reached': summary.world + 1,
          'continues': summary.continuesUsed,
        });
      case LevelCompleteEvent(:final summary):
        s.music.cut();
        s.audio.play(Sfx.newBest);
        s.haptics.celebrate();
        final level = _level;
        if (level != null) {
          final p0 = s.profile.profile;
          final before = p0.levelStars[level.id] ?? 0;
          _levelGoalsBefore = levelGoalsOf(p0, level.id);
          final openBefore = {
            for (final c in chaptersOf(s.levels))
              if (chapterOpen(c, p0.levelStars)) c.index,
          };
          s.profile.update((p) {
            final after = recordLevelGoals(p, level.id, summary.goalsMet);
            if (after > before) {
              s.gameServices.submitStars(totalStars(p.levelStars));
            }
            _starsGained = math.max(0, after - before);
            p.coins +=
                summary.newCoins + (before == 0 ? 30 : 0) + 10 * _starsGained;
            p.stats[Stat.levelsDone] = p.levelStars.values
                .where((v) => v > 0)
                .length;
            _chapterRewards = claimChapterRewards(p, s.levels);
          });
          for (final (c, r) in _chapterRewards) {
            _toast(
              r == chapterStarBonus
                  ? 'Every star in ${c.title}! ${_rewardText(r)}'
                  : 'Chapter ${c.number} complete! ${_rewardText(r)}',
            );
          }
          for (final c in chaptersOf(s.levels)) {
            if (!openBefore.contains(c.index) &&
                chapterOpen(c, s.profile.profile.levelStars)) {
              _toast('Chapter ${c.number} unlocked: ${c.title}');
            }
          }
        }
        s.analytics.log('level_complete', {
          'level': level?.number,
          'stars': summary.stars,
        });
      case RunFinishedEvent(:final summary):
        _onRunFinished(summary);
      case IntroSeenEvent(:final name):
        s.profile.update((p) => p.seenIntros.add(name));
      case GameOverShown():
        // Without a continue on offer the run is over now; apply its
        // rewards right away so they show on this screen.
        if (!engine.canContinue) engine.finishRun();
      case ContinuedEvent():
        _updateMusic();
    }
  }

  String _rewardText(ChapterReward r) => [
    if (r.coins > 0) '+${r.coins} coins',
    if (r.tokens > 0) '+${r.tokens} token${r.tokens == 1 ? '' : 's'}',
    if (r.ball != null) '${ballSkinById(r.ball!).name} ball',
    if (r.theme != null) '${ringThemeById(r.theme!).name} ring',
  ].join(', ');

  void _onRunFinished(RunSummary summary) {
    late RunRewards rewards;
    s.profile.update((p) {
      if (summary.mode == RunMode.duel &&
          summary.score > (engine.beatScore ?? 0)) {
        p.addStat(Stat.duelsWon, 1);
      }
      rewards = applyRun(p, summary, starsGained: _starsGained);
    });
    _starsGained = 0;
    for (final l in rewards.levelsGained) {
      _toast('LEVEL UP! Player level ${l.level}');
    }
    for (final m in rewards.missions) {
      _toast('Mission done: ${m.title}');
    }
    for (final a in rewards.achievements) {
      _toast('Achievement: ${a.title}');
      s.gameServices.unlock(a.id);
    }
    if (rewards.levelsGained.isNotEmpty || rewards.achievements.isNotEmpty) {
      s.audio.play(Sfx.streak);
    }
    switch (summary.mode) {
      case RunMode.endless:
        s.gameServices.submitEndless(summary.score);
      case RunMode.daily:
        s.gameServices.submitDaily(summary.score);
      case RunMode.zen:
      case RunMode.duel:
      case RunMode.level:
        break;
    }
    s.gameServices.saveProfile(s.profile.profile);
  }

  void _toast(String message) {
    if (!mounted) return;
    setState(() => _toasts.add(message));
    Future<void>.delayed(Duration(milliseconds: 2600 * _toasts.length), () {
      if (mounted && _toasts.isNotEmpty) setState(() => _toasts.removeAt(0));
    });
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  Future<void> _continueWithAd() async {
    if (_adBusy) return;
    setState(() => _adBusy = true);
    final earned = await s.ads.showRewarded();
    if (!mounted) return;
    setState(() => _adBusy = false);
    if (earned && engine.continueRun()) {
      s.analytics.log('continue', {'via': 'ad'});
      s.analytics.log('ad_rewarded', {'placement': 'continue'});
    }
  }

  void _continueWithCoins() {
    final cost = s.config.continues.coinCost;
    if (s.profile.profile.coins < cost) return;
    if (engine.continueRun()) {
      s.profile.update((p) => p.coins -= cost);
      s.audio.play(Sfx.ui);
      s.analytics.log('continue', {'via': 'coins'});
    }
  }

  void _continueWithToken() {
    if (s.profile.profile.tokens <= 0) return;
    if (engine.continueRun()) {
      s.profile.update((p) => p.tokens--);
      s.audio.play(Sfx.ui);
      s.analytics.log('continue', {'via': 'token'});
    }
  }

  Future<void> _doubleCoins() async {
    if (_adBusy || _doubledThisRun) return;
    setState(() => _adBusy = true);
    final earned = await s.ads.showRewarded();
    if (!mounted) return;
    setState(() {
      _adBusy = false;
      if (earned) _doubledThisRun = true;
    });
    if (earned) {
      final bonus = engine.lastSummary?.coinsEarned ?? 0;
      s.profile.update((p) => p.coins += bonus);
      s.audio.play(Sfx.coin);
      s.analytics.log('ad_rewarded', {'placement': 'double_coins'});
    }
  }

  Future<void> _extraDailyAttempt() async {
    final p = s.profile.profile;
    if (_adBusy || p.dailyExtraAttempts >= dailyMaxAdAttempts) return;
    setState(() => _adBusy = true);
    final earned = await s.ads.showRewarded();
    if (!mounted) return;
    setState(() => _adBusy = false);
    if (earned) {
      s.profile.update((p) {
        rollDaily(p, _today);
        p.dailyExtraAttempts++;
      });
      s.analytics.log('ad_rewarded', {'placement': 'daily_attempt'});
      _startDaily();
    }
  }

  Future<void> _goHome() async {
    s.audio.play(Sfx.ui);
    final p = s.profile.profile;
    if (s.adPolicy.shouldShowInterstitial(p)) {
      setState(() => _adBusy = true);
      final shown = await s.ads.showInterstitial();
      if (!mounted) return;
      setState(() => _adBusy = false);
      if (shown) {
        s.profile.update((p) => p.runsSinceInterstitial = 0);
        s.analytics.log('ad_interstitial');
      }
    }
    engine.goHome();
    _level = null;
    _updateMusic();
  }

  Future<T?> _open<T>(Widget screen) {
    s.audio.play(Sfx.ui);
    return Navigator.of(context)
        .push(MaterialPageRoute<T>(builder: (_) => screen));
  }

  Future<void> _openLevels() async {
    final level = await _open<LevelDef>(const LevelsScreen());
    if (level != null && mounted) _startLevel(level);
  }

  Future<void> _openDaily() async {
    s.audio.play(Sfx.ui);
    s.profile.update((p) => rollDaily(p, _today));
    final p = s.profile.profile;
    final choice = await showDailyDialog(
      context,
      theme: ringThemeById(p.theme),
      day: _today,
      attemptsLeft: dailyAttemptsLeft(p),
      best: p.dailyBest,
      adReady:
          s.ads.rewardedReady.value &&
          p.dailyExtraAttempts < dailyMaxAdAttempts,
      leaderboards: s.gameServices.signedIn,
    );
    if (!mounted) return;
    switch (choice) {
      case DailyChoice.play:
        _startDaily();
      case DailyChoice.watchAd:
        await _extraDailyAttempt();
      case DailyChoice.leaderboard:
        await s.gameServices.showLeaderboards();
      case null:
        break;
    }
  }

  Future<void> _openDuel() async {
    s.audio.play(Sfx.ui);
    final code = await showDuelDialog(
      context,
      theme: ringThemeById(s.profile.profile.theme),
    );
    if (code != null && mounted) _startDuel(code.$1, code.$2);
  }

  /// Shares a picture of this screen plus a duel code for the same run.
  Future<void> _share() async {
    final summary = engine.lastSummary;
    if (summary == null) return;
    final code = DuelCode.encode(engine.seed, summary.score);
    final where = switch (summary.mode) {
      RunMode.daily => ' in Daily Challenge #${dailyNumber(_today)}',
      _ => '',
    };
    final text =
        'I scored ${summary.score} in Hue Lock$where! '
        'Think you can beat it? Open Hue Lock, tap DUEL and enter $code';
    final files = <XFile>[];
    try {
      final boundary =
          _shotKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      final image = await boundary?.toImage(pixelRatio: 2);
      final bytes = await image?.toByteData(format: ui.ImageByteFormat.png);
      if (bytes != null) {
        files.add(
          XFile.fromData(
            bytes.buffer.asUint8List(),
            mimeType: 'image/png',
            name: 'hue-lock-score.png',
          ),
        );
      }
    } catch (e) {
      debugPrint('Score image failed: $e');
    }
    s.analytics.log('share', {'mode': summary.mode.name});
    await SharePlus.instance.share(
      ShareParams(text: text, files: files.isEmpty ? null : files),
    );
  }

  /// The game-over "so close" goals: the player to pass on this week's
  /// leaderboard first (when signed in), then what the run came closest to.
  List<NextGoal> _goals() {
    final summary = engine.lastSummary;
    if (summary == null) return const [];
    final rival = engine.mode == RunMode.endless
        ? _rivalGoal(summary.score)
        : null;
    return [
      ?rival,
      ...nextGoals(
        s.profile.profile,
        summary,
        config: s.config,
        // The best before this run: the saved one already includes it.
        best: engine.bestAtRunStart,
        applied: !engine.runOpen,
        max: rival == null ? 2 : 1,
      ),
    ];
  }

  NextGoal? _rivalGoal(int score) {
    final rank = s.gameServices.weeklyRank;
    final target = rank?.rivalScore;
    if (rank == null || target == null) return null;
    final best = math.max(score, rank.score);
    if (best > target) return null;
    final name = rank.rivalName ?? 'the next player';
    return NextGoal(
      '${target - score + 1} points to pass $name (#${rank.rank - 1})',
      (score / (target + 1)).clamp(0.0, 1.0),
      detail: 'you: #${rank.rank} this week',
    );
  }

  /// Stars still needed to open [next]'s chapter, or null if it's open.
  int? _gateFor(LevelDef next, PlayerProfile p) {
    final c = next.chapterDef;
    if (chapterOpen(c, p.levelStars)) return null;
    return c.unlockStars - totalStars(p.levelStars);
  }

  bool get _progressBadge {
    final p = s.profile.profile;
    return canClaimDailyReward(p, DateTime.now()) ||
        missionsOf(p).any((m) => m.done && !m.claimed);
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([s.profile, engine, s.gameServices]),
      builder: (context, _) {
        final p = s.profile.profile;
        final theme = ringThemeById(p.theme);
        final palette = HuePalette.of(colorblind: p.colorblind);
        return Scaffold(
          backgroundColor: theme.bgBottom,
          body: RepaintBoundary(
            key: _shotKey,
            child: Stack(
              children: [
                // The game repaints every frame on its own layer; the HUD
                // and overlays only repaint when they change.
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _onPointerDown,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: GamePainter(
                          engine: engine,
                          theme: theme,
                          skin: ballSkinById(p.ball),
                          palette: palette,
                          colorblind: p.colorblind,
                          repaint: _frame,
                          pixelRatio: MediaQuery.devicePixelRatioOf(context),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(child: RepaintBoundary(child: _overlay(theme))),
                if (engine.mode == RunMode.zen &&
                    engine.phase != GamePhase.home)
                  Positioned(
                    top: 0,
                    left: 0,
                    child: SafeArea(
                      child: IconButton(
                        tooltip: 'End Zen',
                        onPressed: _goHome,
                        icon: Icon(Icons.close_rounded, color: theme.text),
                      ),
                    ),
                  ),
                if (_toasts.isNotEmpty)
                  Positioned(
                    left: 24,
                    right: 24,
                    top: 0,
                    child: SafeArea(
                      child: IgnorePointer(
                        child: _Toast(text: _toasts.first, theme: theme),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _overlay(RingTheme theme) {
    final p = s.profile.profile;
    switch (engine.phase) {
      case GamePhase.home:
        return HomeOverlay(
          theme: theme,
          profile: p,
          dailyAttemptsLeft: _dailyLeft,
          progressBadge: _progressBadge,
          showLeaderboards: s.gameServices.signedIn,
          onLevels: _openLevels,
          onDaily: _openDaily,
          onZen: _startZen,
          onDuel: _openDuel,
          onShop: () => _open<void>(const ShopScreen()),
          onProgress: () => _open<void>(const ProgressScreen()),
          onSettings: () => _open<void>(const SettingsScreen()),
          onHelp: () => _open<void>(const HowToPlayScreen()),
          onLeaderboards: s.gameServices.showLeaderboards,
          weeklyRank: s.gameServices.weeklyRank,
        );
      case GamePhase.playing:
      case GamePhase.dying:
        return Hud(engine: engine, theme: theme, level: _level);
      case GamePhase.perk:
        return Stack(
          children: [
            Positioned.fill(
              child: Hud(engine: engine, theme: theme, level: _level),
            ),
            Positioned.fill(
              child: PerkOverlay(
                engine: engine,
                theme: theme,
                onChoose: engine.choosePerk,
              ),
            ),
          ],
        );
      case GamePhase.countdown:
        return Stack(
          children: [
            Positioned.fill(
              child: Hud(engine: engine, theme: theme, level: _level),
            ),
            // Holds behind a banner (boss preview, NOT / split warning) show
            // no number; only continue / resume count down.
            if (engine.showCountdownNumber)
              IgnorePointer(
                child: Center(
                  child: ListenableBuilder(
                    listenable: _frame,
                    builder: (_, _) => Text(
                      '${math.max(1, engine.countdownLeft.ceil())}',
                      style: TextStyle(
                        color: theme.text,
                        fontSize: 64,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      case GamePhase.gameOver:
        final mode = engine.mode;
        final level = _level;
        final levels = s.levels;
        final hasNext =
            level != null &&
            level.index + 1 < levels.length &&
            levelUnlocked(levels, p.levelStars, level.index + 1);
        return ValueListenableBuilder<bool>(
          valueListenable: s.ads.rewardedReady,
          builder: (context, adReady, _) => GameOverOverlay(
            engine: engine,
            theme: theme,
            goals: _goals(),
            levelGoalsBefore: _levelGoalsBefore,
            chapterRewards: _chapterRewards,
            nextLocked: level != null && level.index + 1 < levels.length
                ? _gateFor(levels[level.index + 1], p)
                : null,
            rewardText: _rewardText,
            best: mode == RunMode.daily ? p.dailyBest : p.bestScore,
            coins: p.coins,
            tokens: p.tokens,
            continueCost: s.config.continues.coinCost,
            adReady: adReady && !_adBusy,
            doubled: _doubledThisRun,
            canRetry: _canRetry,
            level: level,
            dailyAttemptsLeft: _dailyLeft,
            onContinueAd: _continueWithAd,
            onContinueCoins: _continueWithCoins,
            onContinueToken: _continueWithToken,
            onDouble: _doubleCoins,
            onHome: _goHome,
            onShare: mode == RunMode.endless || mode == RunMode.daily
                ? _share
                : null,
            onNextLevel: hasNext && engine.lastSummary?.completed == true
                ? () => _startLevel(levels[level.index + 1])
                : null,
            onLevels: mode == RunMode.level ? _openLevels : null,
            onLeaderboard:
                s.gameServices.signedIn &&
                    (mode == RunMode.endless || mode == RunMode.daily)
                ? s.gameServices.showLeaderboards
                : null,
            onExtraAttempt:
                mode == RunMode.daily &&
                    p.dailyExtraAttempts < dailyMaxAdAttempts
                ? _extraDailyAttempt
                : null,
          ),
        );
    }
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.text, required this.theme});

  final String text;
  final RingTheme theme;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(text),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Transform.translate(
        offset: Offset(0, -30 * (1 - v)),
        child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: theme.bgTop.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: HuePalette.standard[2], width: 1.5),
          boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black38)],
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: theme.text,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
