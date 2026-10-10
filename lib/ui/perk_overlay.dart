import 'package:flutter/material.dart';

import '../game/game_engine.dart';
import '../game/perks.dart';
import '../render/palette.dart';
import '../render/ring_themes.dart';
import 'hud.dart';
import 'widgets.dart';

IconData perkIcon(Perk p) => switch (p) {
  Perk.steady => Icons.center_focus_strong_rounded,
  Perk.shield => Icons.shield_rounded,
  Perk.chill => Icons.ac_unit_rounded,
  Perk.wide => Icons.open_in_full_rounded,
  Perk.magnet => Icons.monetization_on_rounded,
  Perk.hot => Icons.local_fire_department_rounded,
  Perk.keeper => Icons.link_rounded,
  Perk.greed => Icons.diamond_rounded,
};

Color perkColor(Perk p) => switch (p) {
  Perk.steady => const Color(0xFFFFFFFF),
  Perk.shield => HuePalette.standard[1],
  Perk.chill => const Color(0xFF7FE7FF),
  Perk.wide => HuePalette.standard[3],
  Perk.magnet => coinColor,
  Perk.hot => const Color(0xFFFF7A2F),
  Perk.keeper => const Color(0xFFB08CFF),
  Perk.greed => HuePalette.standard[2],
};

/// After a boss: three perk cards. Built once per offer (no per-frame
/// work); the cards slide in, then wait for a tap.
class PerkOverlay extends StatelessWidget {
  const PerkOverlay({
    super.key,
    required this.engine,
    required this.theme,
    required this.onChoose,
  });

  final GameEngine engine;
  final RingTheme theme;
  final void Function(Perk perk) onChoose;

  /// Taps right after the boss's last hit are ignored, so a quick extra tap
  /// can't pick a card by accident.
  static const lockout = 0.45;

  @override
  Widget build(BuildContext context) {
    final offer = engine.perkOffer ?? const <Perk>[];
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.62),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'BOSS CLEARED',
                    style: TextStyle(
                      color: HuePalette.standard[3],
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'PICK A PERK FOR THIS RUN',
                    style: hudLabel(
                      theme,
                      size: 13,
                    ).copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 18),
                  for (var i = 0; i < offer.length; i++)
                    _PerkCard(
                      key: ValueKey(offer[i]),
                      perk: offer[i],
                      stacks: engine.perks[offer[i]],
                      delay: i * 90,
                      onTap: () {
                        if (engine.phaseElapsed < lockout) return;
                        onChoose(offer[i]);
                      },
                    ),
                  if (!engine.perks.isEmpty) ...[
                    const SizedBox(height: 10),
                    PerkIcons(perks: engine.perks, color: Colors.white70),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PerkCard extends StatelessWidget {
  const _PerkCard({
    super.key,
    required this.perk,
    required this.stacks,
    required this.delay,
    required this.onTap,
  });

  final Perk perk;
  final int stacks;
  final int delay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = perkColor(perk);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + delay),
      curve: Interval(delay / (320 + delay), 1, curve: Curves.easeOutCubic),
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 24 * (1 - v)),
          child: child,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: const Color(0xFF1B1C34),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: color.withValues(alpha: 0.7), width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.18),
                    ),
                    child: Icon(perkIcon(perk), color: color, size: 30),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stacks > 0
                              ? '${perk.title.toUpperCase()} +1'
                              : perk.title.toUpperCase(),
                          style: TextStyle(
                            color: color,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          perk.description,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The run's perks as a row of small icons (with a count when stacked).
class PerkIcons extends StatelessWidget {
  const PerkIcons({super.key, required this.perks, required this.color});

  final PerkSet perks;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        for (final (perk, n) in perks.entries)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(perkIcon(perk), size: 16, color: perkColor(perk)),
              if (n > 1)
                Text(
                  'x$n',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
