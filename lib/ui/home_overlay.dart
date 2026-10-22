import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../meta/progression.dart';
import '../render/game_painter.dart';
import '../render/palette.dart';
import '../render/ring_themes.dart';
import '../services/game_services.dart';
import '../services/profile_store.dart';
import 'hud.dart';
import 'widgets.dart';

/// Home: tap anywhere for Endless; buttons for the other modes and menus.
class HomeOverlay extends StatefulWidget {
  const HomeOverlay({
    super.key,
    required this.theme,
    required this.profile,
    required this.dailyAttemptsLeft,
    required this.progressBadge,
    required this.showLeaderboards,
    required this.onLevels,
    required this.onDaily,
    required this.onZen,
    required this.onRush,
    required this.onDuel,
    required this.onShop,
    required this.onProgress,
    required this.onSettings,
    required this.onHelp,
    required this.onLeaderboards,
    this.weeklyRank,
  });

  final RingTheme theme;
  final PlayerProfile profile;
  final int dailyAttemptsLeft;

  /// Something to claim on the progress screen (mission or daily reward).
  final bool progressBadge;
  final bool showLeaderboards;
  final VoidCallback onLevels;
  final VoidCallback onDaily;
  final VoidCallback onZen;
  final VoidCallback onRush;
  final VoidCallback onDuel;
  final VoidCallback onShop;
  final VoidCallback onProgress;
  final VoidCallback onSettings;
  final VoidCallback onHelp;
  final VoidCallback onLeaderboards;

  /// This week's Endless rank on Play Games / Game Center, once known.
  final RankInfo? weeklyRank;

  @override
  State<HomeOverlay> createState() => _HomeOverlayState();
}

class _HomeOverlayState extends State<HomeOverlay>
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
    final p = widget.profile;
    final level = levelForXp(p.xp);
    final (into, size) = levelProgress(p.xp);
    return LayoutBuilder(
      builder: (context, box) {
        final layout = RingLayout(box.biggest);
        final ringBottom = layout.center.dy + layout.radius * 1.18;
        return Stack(
          children: [
            // Top bar + title (not interactive except the level badge).
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: widget.onProgress,
                          child: _LevelBadge(
                            level: level,
                            progress: size == 0 ? 0 : into / size,
                            theme: theme,
                          ),
                        ),
                        const Spacer(),
                        IgnorePointer(
                          child: Row(
                            children: [
                              CoinCount(coins: p.coins, color: theme.text),
                              const SizedBox(width: 12),
                              Icon(
                                Icons.confirmation_number_rounded,
                                size: 18,
                                color: HuePalette.standard[3],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${p.tokens}',
                                style: TextStyle(
                                  color: theme.text,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: box.maxHeight * 0.03),
                  IgnorePointer(
                    child: Column(
                      children: [
                        GameTitle(theme: theme),
                        const SizedBox(height: 10),
                        Text(
                          tr('BEST {n}', {'n': p.bestScore}),
                          style: hudLabel(theme, size: 16),
                        ),
                        if (widget.weeklyRank != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            tr('#{rank} THIS WEEK', {
                              'rank': widget.weeklyRank!.rank,
                            }),
                            style: hudLabel(
                              theme,
                              size: 13,
                            ).copyWith(color: coinColor),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
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
                    tr('TAP TO PLAY'),
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
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ModeButton(
                              label: tr('LEVELS'),
                              icon: Icons.school_rounded,
                              color: HuePalette.standard[3],
                              theme: theme,
                              onTap: widget.onLevels,
                            ),
                            _ModeButton(
                              label: tr('DAILY'),
                              icon: Icons.today_rounded,
                              color: HuePalette.standard[2],
                              theme: theme,
                              badge: widget.dailyAttemptsLeft > 0,
                              onTap: widget.onDaily,
                            ),
                            _ModeButton(
                              label: tr('RUSH'),
                              icon: Icons.timer_rounded,
                              color: const Color(0xFFFF7A2F),
                              theme: theme,
                              onTap: widget.onRush,
                            ),
                            _ModeButton(
                              label: tr('ZEN'),
                              icon: Icons.self_improvement_rounded,
                              color: HuePalette.standard[1],
                              theme: theme,
                              onTap: widget.onZen,
                            ),
                            _ModeButton(
                              label: tr('DUEL'),
                              icon: Icons.sports_kabaddi_rounded,
                              color: HuePalette.standard[0],
                              theme: theme,
                              onTap: widget.onDuel,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _IconAction(
                              icon: Icons.palette_rounded,
                              tooltip: tr('Shop'),
                              theme: theme,
                              onTap: widget.onShop,
                            ),
                            _IconAction(
                              icon: Icons.emoji_events_rounded,
                              tooltip: tr('Progress'),
                              theme: theme,
                              badge: widget.progressBadge,
                              onTap: widget.onProgress,
                            ),
                            if (widget.showLeaderboards)
                              _IconAction(
                                icon: Icons.leaderboard_rounded,
                                tooltip: tr('Leaderboards'),
                                theme: theme,
                                onTap: widget.onLeaderboards,
                              ),
                            _IconAction(
                              icon: Icons.help_outline_rounded,
                              tooltip: tr('How to play'),
                              theme: theme,
                              onTap: widget.onHelp,
                            ),
                            _IconAction(
                              icon: Icons.tune_rounded,
                              tooltip: tr('Settings'),
                              theme: theme,
                              onTap: widget.onSettings,
                            ),
                          ],
                        ),
                      ],
                    ),
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

/// The HUE LOCK logo: rainbow letters with a glossy top and a dark
/// extrusion, and the O drawn as a little color dial whose pointer clicks
/// from color to color. Only the dial repaints (its own boundary); the
/// letters are static.
class GameTitle extends StatefulWidget {
  const GameTitle({super.key, required this.theme, this.fontSize = 54});

  final RingTheme theme;
  final double fontSize;

  @override
  State<GameTitle> createState() => _GameTitleState();
}

class _GameTitleState extends State<GameTitle>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4800),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.fontSize;
    final dial = size * 0.74;
    final style = TextStyle(
      color: Colors.white,
      fontSize: size,
      fontWeight: FontWeight.w900,
      letterSpacing: size * 0.1,
      height: 1,
    );
    // The same row in every layer, so the pieces line up exactly.
    Widget row(Color color, Widget o) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('HUE L', style: style.copyWith(color: color)),
        Padding(
          padding: EdgeInsets.only(right: size * 0.1, bottom: size * 0.06),
          child: SizedBox.square(dimension: dial, child: o),
        ),
        Text('CK', style: style.copyWith(color: color)),
      ],
    );
    final colors = HuePalette.standard.colors;
    final shadow = widget.theme.dark
        ? const Color(0xFF05050C)
        : const Color(0xFF34264A).withValues(alpha: 0.35);
    return Semantics(
      label: 'HUE LOCK',
      excludeSemantics: true,
      child: RepaintBoundary(
        child: Stack(
          children: [
            // Extrusion.
            Transform.translate(
              offset: Offset(0, size * 0.07),
              child: row(
                shadow,
                CustomPaint(painter: _DialPainter(shadow: shadow)),
              ),
            ),
            ShaderMask(
              shaderCallback: (rect) =>
                  LinearGradient(colors: [...colors, colors.first])
                      .createShader(rect),
              child: row(Colors.white, const SizedBox()),
            ),
            // Gloss on the upper half of the letters.
            ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66FFFFFF), Color(0x00FFFFFF)],
                stops: [0.15, 0.55],
              ).createShader(rect),
              child: row(Colors.white, const SizedBox()),
            ),
            row(
              Colors.transparent,
              RepaintBoundary(
                child: CustomPaint(
                  painter: _DialPainter(spin: _spin, colors: colors),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The O of the logo: four colored arcs and a pointer that ticks onto each
/// color in turn with a little overshoot, like a lock dial.
class _DialPainter extends CustomPainter {
  _DialPainter({this.spin, this.colors = const [], this.shadow})
    : super(repaint: spin);

  final Animation<double>? spin;
  final List<Color> colors;
  final Color? shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final w = size.width * 0.24;
    final r = size.width / 2 - w / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    if (shadow != null) {
      canvas.drawCircle(c, r, arc..color = shadow!);
      return;
    }
    const gap = 0.16;
    for (var i = 0; i < 4; i++) {
      canvas.drawArc(
        rect,
        -math.pi / 2 - math.pi / 4 + i * math.pi / 2 + gap / 2,
        math.pi / 2 - gap,
        false,
        arc..color = colors[i],
      );
    }
    // Gloss along the top of the dial.
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r + w * 0.22),
      math.pi * 1.1,
      math.pi * 0.8,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.22
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x55FFFFFF),
    );
    // Four steps per turn; each step eases in with a small overshoot.
    final v = (spin?.value ?? 0) * 4;
    final step = v.floor();
    final k = (v - step) < 0.3
        ? Curves.easeOutBack.transform((v - step) / 0.3)
        : 1.0;
    final a = (step + k) * math.pi / 2;
    final dir = Offset(math.sin(a), -math.cos(a));
    final needle = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.42;
    final from = c + dir * (r - w * 0.75);
    final to = c + dir * (r + w * 0.75);
    canvas.drawLine(
      from,
      to,
      needle
        ..strokeWidth = w * 0.42 + 2
        ..color = const Color(0x99000000),
    );
    canvas.drawLine(
      from,
      to,
      needle
        ..strokeWidth = w * 0.42
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.spin != spin || old.shadow != shadow;
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({
    required this.level,
    required this.progress,
    required this.theme,
  });

  final int level;
  final double progress;
  final RingTheme theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 38,
          height: 38,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: progress,
                strokeWidth: 3.5,
                color: HuePalette.standard[3],
                backgroundColor: theme.text.withValues(alpha: 0.15),
              ),
              Text(
                '$level',
                style: TextStyle(
                  color: theme.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(tr('LEVEL|player'), style: hudLabel(theme, size: 12)),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.theme,
    required this.onTap,
    this.badge = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final RingTheme theme;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Material(
        color: color.withValues(alpha: 0.16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withValues(alpha: 0.7), width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            width: 78,
            height: 66,
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: color, size: 26),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            maxLines: 1,
                            style: TextStyle(
                              color: theme.text,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (badge) const Positioned(top: 7, right: 9, child: _Dot()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.theme,
    required this.onTap,
    this.badge = false,
  });

  final IconData icon;
  final String tooltip;
  final RingTheme theme;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          iconSize: 28,
          icon: Icon(icon, color: theme.text),
        ),
        if (badge) const Positioned(top: 8, right: 8, child: _Dot()),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: HuePalette.standard[0],
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
    );
  }
}
