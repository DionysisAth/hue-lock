import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/game_engine.dart';
import '../game/round.dart';
import '../game/star_goals.dart';
import '../meta/levels.dart';
import '../meta/progression.dart';
import '../render/palette.dart';
import '../render/ring_themes.dart';
import 'perk_overlay.dart';
import 'widgets.dart';

TextStyle hudLabel(RingTheme theme, {double size = 14}) => TextStyle(
  color: theme.subtleText,
  fontSize: size,
  fontWeight: FontWeight.w700,
  letterSpacing: 2,
);

/// In-run heads-up display: mode line, score (or Zen hits / level progress),
/// Fever meter and active modifiers. Never takes taps.
class Hud extends StatelessWidget {
  const Hud({super.key, required this.engine, required this.theme, this.level});

  final GameEngine engine;
  final RingTheme theme;
  final LevelDef? level;

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

  String _modeLine() {
    final e = engine;
    return switch (e.mode) {
      RunMode.endless => 'STAGE ${e.world + 1} · ${worldName(e.world)}',
      RunMode.daily =>
        'DAILY CHALLENGE #${dailyNumber(dailyChallengeDay(DateTime.now().toUtc()))}',
      RunMode.zen => 'ZEN · NO GAME OVER',
      RunMode.duel => 'DUEL · BEAT ${e.beatScore ?? 0}',
      RunMode.level =>
        level == null
            ? 'LEVEL'
            : 'LEVEL ${level!.number} · ${level!.title.toUpperCase()}',
    };
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
      if (!e.perks.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: PerkIcons(perks: e.perks, color: theme.subtleText),
        ),
    ];
    final target = e.targetRounds;
    final milestone = e.mode == RunMode.zen
        ? null
        : target != null
        ? ('${e.level} / $target', e.level / target, HuePalette.standard[3])
        : _milestone(e);
    final zen = e.mode == RunMode.zen;
    return IgnorePointer(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(
            children: [
              // Mode line, with what the run heads for next (boss / stage)
              // and a hairline progress bar toward it: two extra pixels
              // of height, so the HUD stays clear of the ring.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text.rich(
                  TextSpan(
                    text: _modeLine(),
                    children: [
                      if (milestone != null)
                        TextSpan(
                          text: '  ·  ${milestone.$1}',
                          style: TextStyle(color: milestone.$3),
                        ),
                    ],
                  ),
                  style: hudLabel(theme, size: 12),
                ),
              ),
              if (milestone != null) ...[
                const SizedBox(height: 3),
                _Bar(
                  value: milestone.$2,
                  color: milestone.$3,
                  theme: theme,
                  width: 120,
                  height: 2,
                ),
              ] else
                const SizedBox(height: 4),
              AnimatedScore(score: zen ? e.hits : e.score, theme: theme),
              const SizedBox(height: 6),
              if (target != null)
                _LiveGoals(engine: e, theme: theme)
              else if (zen)
                Text('HITS', style: hudLabel(theme))
              else if (e.mode == RunMode.duel)
                Text(
                  e.score > (e.beatScore ?? 0)
                      ? 'AHEAD BY ${e.score - (e.beatScore ?? 0)}'
                      : '${(e.beatScore ?? 0) - e.score + 1} TO WIN',
                  style: hudLabel(theme),
                )
              else
                _BestLine(engine: e, theme: theme),
              const SizedBox(height: 8),
              FeverMeter(
                streak: e.perfectStreak,
                goal: e.feverGoal,
                fever: e.fever,
                theme: theme,
              ),
              const SizedBox(height: 8),
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

/// "BEST 248", turning gold with the gap to close once it's near.
class _BestLine extends StatelessWidget {
  const _BestLine({required this.engine, required this.theme});

  final GameEngine engine;
  final RingTheme theme;

  @override
  Widget build(BuildContext context) {
    final e = engine;
    final best = e.bestAtRunStart;
    if (e.newBestReached) {
      return Text(
        'NEW BEST',
        style: hudLabel(theme).copyWith(color: coinColor),
      );
    }
    final gap = best - e.score + 1;
    if (best > 0 && e.score > 0 && gap <= math.max(10, best * 0.2)) {
      return Text(
        '$gap TO BEAT YOUR BEST',
        style: hudLabel(theme).copyWith(color: coinColor),
      );
    }
    return Text('BEST $best', style: hudLabel(theme));
  }
}

/// The next thing a run is heading for: the next boss (and its perk) or
/// the next stage, whichever comes first, as (label, progress, color).
(String, double, Color)? _milestone(GameEngine e) {
  final level = e.level;
  final bossEvery = e.config.boss.every;
  final stageEvery = e.config.worlds.every;
  if (e.round?.spec.kind == RoundKind.boss) {
    return ('BOSS ROUND', 1, HuePalette.standard[0]);
  }
  if (bossEvery <= 0) return null;
  final toBoss = bossEvery - level % bossEvery;
  final toStage = e.mode == RunMode.endless && stageEvery > 0
      ? stageEvery - level % stageEvery
      : toBoss + 1;
  if (toBoss <= toStage) {
    return (
      toBoss == 1 ? 'BOSS NEXT' : 'BOSS IN $toBoss',
      1 - toBoss / bossEvery,
      HuePalette.standard[0],
    );
  }
  return (
    'STAGE ${e.world + 2} IN $toStage',
    1 - toStage / stageEvery,
    HuePalette.standard[3],
  );
}

/// A thin static progress bar (no animation, nothing to repaint).
class _Bar extends StatelessWidget {
  const _Bar({
    required this.value,
    required this.color,
    required this.theme,
    this.width = 140,
    this.height = 4,
  });

  final double value;
  final Color color;
  final RingTheme theme;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: theme.text.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(2),
      ),
      child: FractionallySizedBox(
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// Level mode: the star goals with live progress, on one line.
class _LiveGoals extends StatelessWidget {
  const _LiveGoals({required this.engine, required this.theme});

  final GameEngine engine;
  final RingTheme theme;

  @override
  Widget build(BuildContext context) {
    final goals = engine.starGoals;
    if (goals.isEmpty) return const SizedBox.shrink();
    final now = engine.liveSummary;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final g in goals) ...[
            if (g != goals.first) const SizedBox(width: 14),
            Icon(
              g.met(now) ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 14,
              color: g.met(now) ? coinColor : theme.subtleText,
            ),
            const SizedBox(width: 3),
            Text(
              g.type == GoalType.shield
                  ? g.shortText
                  : '${g.shortText} ${math.min(g.value(now), g.target)}/${g.target}',
              style: hudLabel(theme, size: 10).copyWith(
                letterSpacing: 1,
                color: g.met(now) ? coinColor : theme.subtleText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Score that counts up to its new value with a little pop and a "+N".
class AnimatedScore extends StatefulWidget {
  const AnimatedScore({super.key, required this.score, required this.theme});

  final int score;
  final RingTheme theme;

  @override
  State<AnimatedScore> createState() => _AnimatedScoreState();
}

class _AnimatedScoreState extends State<AnimatedScore>
    with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  int _from = 0;
  int _gain = 0;

  @override
  void initState() {
    super.initState();
    _from = widget.score;
  }

  @override
  void didUpdateWidget(AnimatedScore old) {
    super.didUpdateWidget(old);
    if (widget.score != old.score) {
      _from = widget.score < old.score ? widget.score : _shown;
      _gain = widget.score - old.score;
      _anim.forward(from: 0);
    }
  }

  int get _shown {
    final k = Curves.easeOut.transform(_anim.value);
    return (_from + (widget.score - _from) * k).round();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final v = _anim.value;
        // Quick swell and settle.
        final scale = 1 + 0.22 * math.sin(math.min(1, v * 2.2) * math.pi);
        final showGain = _gain > 0 && _anim.isAnimating;
        return SizedBox(
          height: 66,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Scaled as a cached layer: scaling live text would
              // re-rasterize its glyphs at a new size every frame.
              Transform.scale(
                scale: scale,
                filterQuality: scale == 1 ? null : FilterQuality.medium,
                child: Text(
                  '${_anim.isAnimating ? _shown : widget.score}',
                  style: TextStyle(
                    color: theme.text,
                    fontSize: 64,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (showGain)
                Positioned(
                  right: -8,
                  top: -6 - 18 * v,
                  child: FractionalTranslation(
                    translation: const Offset(1, 0),
                    child: Opacity(
                      opacity: (1 - v).clamp(0.0, 1.0),
                      child: Text(
                        '+$_gain',
                        style: TextStyle(
                          color: HuePalette.standard[2],
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Perfect streak progress toward Fever: one segment per Perfect.
class FeverMeter extends StatelessWidget {
  const FeverMeter({
    super.key,
    required this.streak,
    required this.goal,
    required this.fever,
    required this.theme,
  });

  final int streak;
  final int goal;
  final bool fever;
  final RingTheme theme;

  static const _hot = Color(0xFFFF7A2F);

  @override
  Widget build(BuildContext context) {
    final filled = fever ? goal : math.min(streak, goal);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < goal; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            // No overshoot: an overshooting curve would lerp the glow past
            // zero (a negative blur) when Fever ends.
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            width: i < filled ? 22 : 16,
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: i < filled
                  ? Color.lerp(
                      HuePalette.standard[2],
                      _hot,
                      goal <= 1 ? 1 : i / (goal - 1),
                    )
                  : theme.text.withValues(alpha: 0.14),
              boxShadow: i < filled && theme.dark
                  ? [
                      BoxShadow(
                        color: _hot.withValues(alpha: fever ? 0.8 : 0.4),
                        blurRadius: fever ? 10 : 5,
                      ),
                    ]
                  : null,
            ),
          ),
      ],
    );
  }
}
