import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app.dart';
import '../game/game_engine.dart';
import '../game/hit_judge.dart';
import '../render/ball_skins.dart';
import '../render/game_painter.dart';
import '../render/palette.dart';
import '../render/ring_themes.dart';
import '../services/feedback.dart';
import 'settings_screen.dart';
import 'shop_screen.dart';
import 'widgets.dart';

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
  Duration? _lastFrameStamp;
  bool _doubledThisRun = false;
  bool _adBusy = false;

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
      _ticker.start();
      _updateMusic();
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
    } else {
      s.music.resume();
    }
  }

  /// Music builds with the run: pad at the start, full mix in Fever.
  void _updateMusic() {
    final e = engine;
    final int intensity;
    if (e.phase == GamePhase.home) {
      intensity = 1;
    } else if (e.fever) {
      intensity = 4;
    } else if (e.level >= 30) {
      intensity = 3;
    } else if (e.level >= 8) {
      intensity = 2;
    } else {
      intensity = 1;
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
        _startRun();
      case GamePhase.gameOver:
        if (engine.canRestart) _startRun();
      case GamePhase.dying:
      case GamePhase.countdown:
        break;
    }
  }

  void _startRun() {
    engine.startRun(best: s.profile.profile.bestScore);
  }

  void _onEvent(GameEvent e) {
    switch (e) {
      case RunStarted():
        _doubledThisRun = false;
        s.profile.update((p) {
          p.totalRuns++;
          p.runsSinceInterstitial++;
        });
        s.analytics.log('run_start', {'run': s.profile.profile.totalRuns});
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
      case FeverEvent(:final active):
        if (active) {
          s.audio.play(Sfx.fever);
          s.haptics.perfect();
        }
        _updateMusic();
      case PowerUpEvent(:final powerUp):
        s.audio.play(Sfx.powerUp);
        s.analytics.log('power_up', {'type': powerUp.name});
      case ShieldSavedEvent():
        s.audio.play(Sfx.shield);
        s.haptics.fail();
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
          p.bestScore = math.max(p.bestScore, summary.score);
          p.coins += summary.newCoins;
        });
        s.analytics.log('run_end', {
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
      case GameOverShown():
        break;
      case ContinuedEvent():
        _updateMusic();
    }
  }

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
    _updateMusic();
  }

  Future<void> _open(Widget screen) async {
    s.audio.play(Sfx.ui);
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([s.profile, engine]),
      builder: (context, _) {
        final p = s.profile.profile;
        final theme = ringThemeById(p.theme);
        final palette = HuePalette.of(colorblind: p.colorblind);
        return Scaffold(
          backgroundColor: theme.bgBottom,
          body: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _onPointerDown,
                  child: CustomPaint(
                    painter: GamePainter(
                      engine: engine,
                      theme: theme,
                      skin: ballSkinById(p.ball),
                      palette: palette,
                      colorblind: p.colorblind,
                      repaint: _frame,
                    ),
                  ),
                ),
              ),
              Positioned.fill(child: _overlay(theme)),
            ],
          ),
        );
      },
    );
  }

  Widget _overlay(RingTheme theme) {
    switch (engine.phase) {
      case GamePhase.home:
        return _HomeOverlay(
          theme: theme,
          best: s.profile.profile.bestScore,
          coins: s.profile.profile.coins,
          onShop: () => _open(const ShopScreen()),
          onSettings: () => _open(const SettingsScreen()),
        );
      case GamePhase.playing:
      case GamePhase.dying:
        return _Hud(engine: engine, theme: theme);
      case GamePhase.countdown:
        return Stack(
          children: [
            Positioned.fill(
              child: _Hud(engine: engine, theme: theme),
            ),
            // A boss preview shows its colors in the ball instead.
            if (!engine.bossPreview)
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
        return ValueListenableBuilder<bool>(
          valueListenable: s.ads.rewardedReady,
          builder: (context, adReady, _) => _GameOverOverlay(
            engine: engine,
            theme: theme,
            best: s.profile.profile.bestScore,
            coins: s.profile.profile.coins,
            continueCost: s.config.continues.coinCost,
            adReady: adReady && !_adBusy,
            doubled: _doubledThisRun,
            onContinueAd: _continueWithAd,
            onContinueCoins: _continueWithCoins,
            onDouble: _doubleCoins,
            onHome: _goHome,
          ),
        );
    }
  }
}

TextStyle _label(RingTheme theme, {double size = 14}) => TextStyle(
  color: theme.subtleText,
  fontSize: size,
  fontWeight: FontWeight.w700,
  letterSpacing: 2,
);

class _Hud extends StatelessWidget {
  const _Hud({required this.engine, required this.theme});

  final GameEngine engine;
  final RingTheme theme;

  Widget _chip(String label, {IconData? icon, Color? color}) {
    final c = color ?? theme.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: c),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: c,
              fontWeight: FontWeight.w900,
              fontSize: 13,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = engine;
    final chips = <Widget>[
      if (e.fever)
        _chip(
          'FEVER x${e.config.fever.pointsMultiplier}',
          icon: Icons.local_fire_department_rounded,
          color: const Color(0xFFFF7A2F),
        ),
      if (e.multiplier > 1) _chip('COMBO x${e.multiplier}'),
      if (e.shield)
        _chip(
          'SHIELD',
          icon: Icons.shield_rounded,
          color: HuePalette.standard[1],
        ),
      if (e.slowRounds > 0)
        _chip(
          'SLOW ${e.slowRounds}',
          icon: Icons.hourglass_bottom_rounded,
          color: HuePalette.standard[3],
        ),
      if (e.wideRounds > 0)
        _chip(
          'WIDE ${e.wideRounds}',
          icon: Icons.open_in_full_rounded,
          color: HuePalette.standard[2],
        ),
    ];
    return IgnorePointer(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(
            children: [
              Text(
                'STAGE ${e.world + 1} · ${worldName(e.world)}',
                style: _label(theme, size: 12),
              ),
              const SizedBox(height: 4),
              Text(
                '${e.score}',
                style: TextStyle(
                  color: theme.text,
                  fontSize: 64,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                e.newBestReached
                    ? 'NEW BEST'
                    : 'BEST ${math.max(e.bestAtRunStart, e.score)}',
                style: _label(theme),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: chips,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeOverlay extends StatefulWidget {
  const _HomeOverlay({
    required this.theme,
    required this.best,
    required this.coins,
    required this.onShop,
    required this.onSettings,
  });

  final RingTheme theme;
  final int best;
  final int coins;
  final VoidCallback onShop;
  final VoidCallback onSettings;

  @override
  State<_HomeOverlay> createState() => _HomeOverlayState();
}

class _HomeOverlayState extends State<_HomeOverlay>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return LayoutBuilder(
      builder: (context, box) {
        final layout = RingLayout(box.biggest);
        final ringBottom = layout.center.dy + layout.radius * 1.3;
        return Stack(
          children: [
            IgnorePointer(
              child: SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 20),
                        child: CoinCount(
                          coins: widget.coins,
                          color: theme.text,
                        ),
                      ),
                    ),
                    SizedBox(height: box.maxHeight * 0.04),
                    _Title(theme: theme),
                    const SizedBox(height: 10),
                    Text('BEST ${widget.best}', style: _label(theme, size: 16)),
                  ],
                ),
              ),
            ),
            Positioned(
              top: ringBottom,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: Tween(begin: 0.35, end: 1.0).animate(_pulse),
                  child: Text(
                    'TAP TO PLAY',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PillButton(
                        label: 'SHOP',
                        icon: Icons.palette_rounded,
                        theme: theme,
                        onPressed: widget.onShop,
                      ),
                      const SizedBox(width: 16),
                      PillButton(
                        label: 'SETTINGS',
                        icon: Icons.tune_rounded,
                        theme: theme,
                        filled: false,
                        onPressed: widget.onSettings,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.theme});

  final RingTheme theme;

  @override
  Widget build(BuildContext context) {
    final colors = HuePalette.standard.colors;
    return ShaderMask(
      shaderCallback: (rect) =>
          LinearGradient(colors: colors).createShader(rect),
      child: const Text(
        'HUE LOCK',
        style: TextStyle(
          color: Colors.white,
          fontSize: 52,
          fontWeight: FontWeight.w900,
          letterSpacing: 6,
          height: 1,
        ),
      ),
    );
  }
}

class _GameOverOverlay extends StatelessWidget {
  const _GameOverOverlay({
    required this.engine,
    required this.theme,
    required this.best,
    required this.coins,
    required this.continueCost,
    required this.adReady,
    required this.doubled,
    required this.onContinueAd,
    required this.onContinueCoins,
    required this.onDouble,
    required this.onHome,
  });

  final GameEngine engine;
  final RingTheme theme;
  final int best;
  final int coins;
  final int continueCost;
  final bool adReady;
  final bool doubled;
  final VoidCallback onContinueAd;
  final VoidCallback onContinueCoins;
  final VoidCallback onDouble;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final summary = engine.lastSummary;
    final miss = engine.lastMiss;
    final isNewBest =
        summary != null &&
        summary.score > engine.bestAtRunStart &&
        summary.score > 0;
    final canContinue = engine.canContinue;

    return LayoutBuilder(
      builder: (context, box) {
        final layout = RingLayout(box.biggest);
        final ringTop = layout.center.dy - layout.radius * 1.32;
        final ringBottom = layout.center.dy + layout.radius * 1.32;
        return Stack(
          children: [
            // Score block above the ring.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: ringTop,
              child: IgnorePointer(
                child: SafeArea(
                  bottom: false,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${summary?.score ?? engine.score}',
                          style: TextStyle(
                            color: theme.text,
                            fontSize: 64,
                            height: 1,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isNewBest ? 'NEW BEST!' : 'BEST $best',
                          style: isNewBest
                              ? TextStyle(
                                  color: HuePalette.standard[2],
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                )
                              : _label(theme),
                        ),
                        if (miss != null && miss.nearMiss) ...[
                          const SizedBox(height: 8),
                          Text(
                            'SO CLOSE!',
                            style: TextStyle(
                              color: HuePalette.standard[0],
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                          Text(
                            '${(miss.missBySeconds * 1000).round()} ms '
                            '${miss.early ? 'early' : 'late'}',
                            style: _label(theme, size: 13),
                          ),
                        ] else if (miss != null && miss.timeout) ...[
                          const SizedBox(height: 8),
                          Text(
                            'TOO SLOW',
                            style: TextStyle(
                              color: HuePalette.standard[2],
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                          Text(
                            'the fuse ran out',
                            style: _label(theme, size: 13),
                          ),
                        ] else if (miss?.wrongZone != null) ...[
                          const SizedBox(height: 8),
                          Text('WRONG COLOR', style: _label(theme, size: 15)),
                        ],
                        if (summary != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'STAGE ${summary.world + 1} · ${worldName(summary.world)}',
                            style: _label(theme, size: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Actions below the ring.
            Positioned(
              left: 16,
              right: 16,
              top: ringBottom,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (summary != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IgnorePointer(
                              child: CoinCount(
                                coins: summary.coinsEarned * (doubled ? 2 : 1),
                                color: theme.text,
                                prefix: '+',
                              ),
                            ),
                            if (!doubled && summary.coinsEarned > 0) ...[
                              const SizedBox(width: 12),
                              PillButton(
                                label: 'x2',
                                icon: Icons.play_circle_fill_rounded,
                                theme: theme,
                                color: coinColor,
                                onPressed: adReady ? onDouble : null,
                              ),
                            ],
                          ],
                        ),
                      if (canContinue) ...[
                        const SizedBox(height: 14),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PillButton(
                              label: 'CONTINUE',
                              icon: Icons.play_circle_fill_rounded,
                              theme: theme,
                              color: HuePalette.standard[3],
                              onPressed: adReady ? onContinueAd : null,
                            ),
                            const SizedBox(width: 10),
                            PillButton(
                              label: '$continueCost',
                              icon: Icons.monetization_on_rounded,
                              theme: theme,
                              filled: false,
                              onPressed: coins >= continueCost
                                  ? onContinueCoins
                                  : null,
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 18),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Home',
                            onPressed: onHome,
                            icon: Icon(
                              Icons.home_rounded,
                              color: theme.text,
                              size: 30,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IgnorePointer(
                            child: Text(
                              'TAP TO RETRY',
                              style: TextStyle(
                                color: theme.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 46),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
