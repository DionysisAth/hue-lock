import 'package:flutter/material.dart';

import '../game/game_engine.dart';
import '../meta/levels.dart';
import '../meta/progression.dart';
import '../render/game_painter.dart';
import '../render/palette.dart';
import '../render/ring_themes.dart';
import 'hud.dart';
import 'widgets.dart';

/// End-of-run screen. Score and verdict above the ring, actions below it,
/// "tap anywhere" restarts (when this mode allows it).
class GameOverOverlay extends StatelessWidget {
  const GameOverOverlay({
    super.key,
    required this.engine,
    required this.theme,
    required this.best,
    required this.coins,
    required this.tokens,
    required this.continueCost,
    required this.adReady,
    required this.doubled,
    required this.canRetry,
    required this.onContinueAd,
    required this.onContinueCoins,
    required this.onContinueToken,
    required this.onDouble,
    required this.onHome,
    this.level,
    this.dailyAttemptsLeft = 0,
    this.onShare,
    this.onNextLevel,
    this.onLevels,
    this.onLeaderboard,
    this.onExtraAttempt,
  });

  final GameEngine engine;
  final RingTheme theme;

  /// The best to compare with: Endless best, today's Daily best, ...
  final int best;
  final int coins;
  final int tokens;
  final int continueCost;
  final bool adReady;
  final bool doubled;
  final bool canRetry;
  final LevelDef? level;
  final int dailyAttemptsLeft;
  final VoidCallback onContinueAd;
  final VoidCallback onContinueCoins;
  final VoidCallback onContinueToken;
  final VoidCallback onDouble;
  final VoidCallback onHome;
  final VoidCallback? onShare;
  final VoidCallback? onNextLevel;
  final VoidCallback? onLevels;
  final VoidCallback? onLeaderboard;
  final VoidCallback? onExtraAttempt;

  TextStyle _big(Color color, [double size = 26]) => TextStyle(
    color: color,
    fontSize: size,
    fontWeight: FontWeight.w900,
    letterSpacing: 2,
  );

  List<Widget> _verdict(RunSummary? summary) {
    final miss = engine.lastMiss;
    final mode = engine.mode;
    if (mode == RunMode.level && summary != null) {
      if (summary.completed) {
        return [
          Text('LEVEL COMPLETE', style: _big(HuePalette.standard[3], 24)),
          const SizedBox(height: 6),
          _Stars(stars: summary.stars),
          const SizedBox(height: 4),
          Text(
            '${(summary.perfectRatio * 100).round()}% PERFECT',
            style: hudLabel(theme, size: 12),
          ),
        ];
      }
      return [
        Text('TRY AGAIN', style: _big(HuePalette.standard[0], 24)),
        Text(
          '${summary.level} / ${engine.targetRounds ?? 0} cleared',
          style: hudLabel(theme, size: 13),
        ),
      ];
    }
    if (mode == RunMode.duel && summary != null) {
      final target = engine.beatScore ?? 0;
      final won = summary.score > target;
      return [
        Text(
          won ? 'YOU WIN!' : 'YOU LOSE',
          style: _big(won ? HuePalette.standard[3] : HuePalette.standard[0]),
        ),
        Text('${summary.score} vs $target', style: hudLabel(theme, size: 13)),
      ];
    }
    if (miss != null && miss.nearMiss) {
      return [
        Text('SO CLOSE!', style: _big(HuePalette.standard[0])),
        Text(
          '${(miss.missBySeconds * 1000).round()} ms '
          '${miss.early ? 'early' : 'late'}',
          style: hudLabel(theme, size: 13),
        ),
      ];
    }
    if (miss != null && miss.timeout) {
      return [
        Text('TOO SLOW', style: _big(HuePalette.standard[2], 24)),
        Text('the fuse ran out', style: hudLabel(theme, size: 13)),
      ];
    }
    if (miss?.wrongZone != null) {
      return [Text('WRONG COLOR', style: hudLabel(theme, size: 15))];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final summary = engine.lastSummary;
    final mode = engine.mode;
    final score = summary?.score ?? engine.score;
    final isNewBest =
        mode != RunMode.level &&
        mode != RunMode.duel &&
        summary != null &&
        summary.score > engine.bestAtRunStart &&
        summary.score > 0;
    final xp = summary == null ? 0 : xpForRun(summary);
    final canContinue = engine.canContinue;

    return LayoutBuilder(
      builder: (context, box) {
        final layout = RingLayout(box.biggest);
        final ringTop = layout.center.dy - layout.radius * 1.32;
        final ringBottom = layout.center.dy + layout.radius * 1.32;
        return Stack(
          children: [
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
                        if (mode == RunMode.daily)
                          Text(
                            'DAILY CHALLENGE',
                            style: hudLabel(theme, size: 12),
                          ),
                        if (mode == RunMode.level && level != null)
                          Text(
                            'LEVEL ${level!.number} · ${level!.title.toUpperCase()}',
                            style: hudLabel(theme, size: 12),
                          ),
                        Text(
                          '$score',
                          style: TextStyle(
                            color: theme.text,
                            fontSize: 64,
                            height: 1,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (mode != RunMode.level && mode != RunMode.duel)
                          Text(
                            isNewBest
                                ? (mode == RunMode.daily
                                      ? 'BEST TODAY!'
                                      : 'NEW BEST!')
                                : '${mode == RunMode.daily ? 'TODAY' : 'BEST'} $best',
                            style: isNewBest
                                ? _big(HuePalette.standard[2], 16)
                                : hudLabel(theme),
                          ),
                        const SizedBox(height: 6),
                        ..._verdict(summary),
                        if (summary != null && mode == RunMode.endless) ...[
                          const SizedBox(height: 6),
                          Text(
                            'STAGE ${summary.world + 1} · ${worldName(summary.world)}',
                            style: hudLabel(theme, size: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
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
                            const SizedBox(width: 10),
                            IgnorePointer(
                              child: Text(
                                '+$xp XP',
                                style: TextStyle(
                                  color: HuePalette.standard[3],
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (!doubled &&
                                summary.coinsEarned > 0 &&
                                mode == RunMode.endless) ...[
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
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            PillButton(
                              label: 'CONTINUE',
                              icon: Icons.play_circle_fill_rounded,
                              theme: theme,
                              color: HuePalette.standard[3],
                              onPressed: adReady ? onContinueAd : null,
                            ),
                            if (tokens > 0)
                              PillButton(
                                label: 'TOKEN ($tokens)',
                                icon: Icons.confirmation_number_rounded,
                                theme: theme,
                                color: HuePalette.standard[1],
                                onPressed: onContinueToken,
                              ),
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
                      if (mode == RunMode.level && summary != null) ...[
                        const SizedBox(height: 14),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (onLevels != null)
                              PillButton(
                                label: 'LEVELS',
                                icon: Icons.grid_view_rounded,
                                theme: theme,
                                filled: false,
                                onPressed: onLevels,
                              ),
                            if (onNextLevel != null) ...[
                              const SizedBox(width: 10),
                              PillButton(
                                label: 'NEXT',
                                icon: Icons.arrow_forward_rounded,
                                theme: theme,
                                color: HuePalette.standard[3],
                                onPressed: onNextLevel,
                              ),
                            ],
                          ],
                        ),
                      ],
                      if (mode == RunMode.daily) ...[
                        const SizedBox(height: 12),
                        Text(
                          dailyAttemptsLeft > 0
                              ? '$dailyAttemptsLeft attempt${dailyAttemptsLeft == 1 ? '' : 's'} left today'
                              : 'No attempts left today',
                          style: hudLabel(theme, size: 13),
                        ),
                        if (dailyAttemptsLeft <= 0 &&
                            onExtraAttempt != null) ...[
                          const SizedBox(height: 8),
                          PillButton(
                            label: 'ONE MORE TRY',
                            icon: Icons.play_circle_fill_rounded,
                            theme: theme,
                            color: HuePalette.standard[2],
                            onPressed: adReady ? onExtraAttempt : null,
                          ),
                        ],
                      ],
                      if (onShare != null || onLeaderboard != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (onShare != null)
                              PillButton(
                                label: 'CHALLENGE A FRIEND',
                                icon: Icons.share_rounded,
                                theme: theme,
                                filled: false,
                                onPressed: onShare,
                              ),
                            if (onLeaderboard != null) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Leaderboard',
                                onPressed: onLeaderboard,
                                icon: Icon(
                                  Icons.leaderboard_rounded,
                                  color: theme.text,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),
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
                              canRetry ? 'TAP TO RETRY' : 'COME BACK TOMORROW',
                              style: TextStyle(
                                color: theme.text,
                                fontSize: canRetry ? 18 : 15,
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

class _Stars extends StatelessWidget {
  const _Stars({required this.stars});

  final int stars;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 380 + i * 220),
            curve: Curves.elasticOut,
            builder: (context, v, child) =>
                Transform.scale(scale: i < stars ? v : 1, child: child),
            child: Icon(
              i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 40,
              color: i < stars ? coinColor : Colors.white24,
            ),
          ),
      ],
    );
  }
}
