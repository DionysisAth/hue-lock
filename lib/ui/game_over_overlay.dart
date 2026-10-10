import 'package:flutter/material.dart';

import '../app.dart';
import '../game/game_engine.dart';
import '../game/star_goals.dart';
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
    this.goals = const [],
    this.levelGoalsBefore = 0,
    this.chapterRewards = const [],
    this.nextLocked,
    this.rewardText,
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

  /// What the player is closest to next (Endless, Daily, duels).
  final List<NextGoal> goals;

  /// Level mode: goals met before this run, to mark the new ones.
  final int levelGoalsBefore;
  final List<(ChapterDef, ChapterReward)> chapterRewards;

  /// Level mode: stars still needed to open the next level's chapter.
  final int? nextLocked;
  final String Function(ChapterReward reward)? rewardText;

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
          _Stars(
            mask: levelGoalsBefore | summary.goalsMet,
            fresh: summary.goalsMet & ~levelGoalsBefore,
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
                      if (goals.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        IgnorePointer(
                          child: Column(
                            children: [
                              for (final g in goals)
                                _GoalRow(goal: g, theme: theme),
                            ],
                          ),
                        ),
                      ],
                      if (mode == RunMode.level &&
                          summary != null &&
                          level != null)
                        IgnorePointer(child: _levelDetails(summary)),
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
                            child: _Pulse(
                              enabled: canRetry,
                              child: Text(
                                canRetry
                                    ? 'TAP TO RETRY'
                                    : 'COME BACK TOMORROW',
                                style: TextStyle(
                                  color: theme.text,
                                  fontSize: canRetry ? 18 : 15,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 3,
                                ),
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

  /// Level mode: the star goals (new ones marked), chapter rewards and
  /// what the next chapter still needs.
  Widget _levelDetails(RunSummary summary) {
    final l = level!;
    final have = levelGoalsBefore | summary.goalsMet;
    final reward = rewardText;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: [
          for (var i = 0; i < l.goals.length; i++)
            _GoalCheck(
              goal: l.goals[i],
              value: l.goals[i].value(summary),
              done: have & (1 << (i + 1)) != 0,
              fresh: summary.goalsMet & ~levelGoalsBefore & (1 << (i + 1)) != 0,
              theme: theme,
            ),
          for (final (c, r) in chapterRewards)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                r == chapterStarBonus
                    ? 'ALL ${c.maxStars} STARS IN ${c.title.toUpperCase()}'
                    : 'CHAPTER ${c.number} COMPLETE',
                style: _big(coinColor, 15),
              ),
            ),
          for (final (_, r) in chapterRewards)
            if (reward != null)
              Text(reward(r), style: hudLabel(theme, size: 12)),
          if (summary.completed && nextLocked != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'EARN $nextLocked MORE '
                '${nextLocked == 1 ? 'STAR' : 'STARS'} TO OPEN CHAPTER '
                '${l.chapter + 2}',
                style: hudLabel(theme, size: 12).copyWith(color: coinColor),
              ),
            ),
        ],
      ),
    );
  }
}

/// Three stars: earned ones filled; ones earned just now pop in one by one
/// with a rising chime.
class _Stars extends StatefulWidget {
  const _Stars({required this.mask, required this.fresh});

  /// Goals met (bit 0 = cleared), including earlier runs.
  final int mask;

  /// The bits of [mask] earned by this run.
  final int fresh;

  @override
  State<_Stars> createState() => _StarsState();
}

class _StarsState extends State<_Stars> {
  static const _step = 260;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    final audio = Services.of(context).audio;
    var n = 0;
    for (var i = 0; i < 3; i++) {
      if (widget.fresh & (1 << i) == 0) continue;
      final note = 1 + 2 * n++;
      Future<void>.delayed(Duration(milliseconds: 250 + i * _step), () {
        if (mounted) audio.playPerfect(note);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          _star(
            have: widget.mask & (1 << i) != 0,
            fresh: widget.fresh & (1 << i) != 0,
            delay: 250 + i * _step,
          ),
      ],
    );
  }

  Widget _star({required bool have, required bool fresh, required int delay}) {
    final icon = Icon(
      have ? Icons.star_rounded : Icons.star_outline_rounded,
      size: 40,
      color: have ? coinColor : Colors.white24,
    );
    if (!fresh) return icon;
    final total = delay + 450;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.elasticOut),
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: icon,
    );
  }
}

class _GoalCheck extends StatelessWidget {
  const _GoalCheck({
    required this.goal,
    required this.value,
    required this.done,
    required this.fresh,
    required this.theme,
  });

  final StarGoal goal;
  final int value;
  final bool done;
  final bool fresh;
  final RingTheme theme;

  @override
  Widget build(BuildContext context) {
    final color = done ? coinColor : theme.subtleText;
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            done ? goal.text : '${goal.text}  ($value/${goal.target})',
            style: TextStyle(
              color: done ? theme.text : theme.subtleText,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          if (fresh) ...[const SizedBox(width: 6), Text('NEW', style: _newTag)],
        ],
      ),
    );
  }
}

const _newTag = TextStyle(
  color: coinColor,
  fontWeight: FontWeight.w900,
  fontSize: 12,
  letterSpacing: 1.5,
);

/// One "so close" goal: text and a thin progress bar that fills in once.
class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.goal, required this.theme});

  final NextGoal goal;
  final RingTheme theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        width: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    goal.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (goal.detail != null)
                  Text(
                    goal.detail!,
                    style: TextStyle(
                      color: theme.subtleText,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: goal.fraction.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Container(
                height: 5,
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: theme.text.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: FractionallySizedBox(
                  widthFactor: v,
                  child: Container(
                    decoration: BoxDecoration(
                      color: goal.fraction >= 0.8
                          ? coinColor
                          : HuePalette.standard[3],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gently pulses its child's opacity (an opacity layer only: the child is
/// never repainted).
class _Pulse extends StatefulWidget {
  const _Pulse({required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.55,
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _anim.repeat(reverse: true);
    } else {
      _anim.value = 1;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _anim, child: widget.child);
}
