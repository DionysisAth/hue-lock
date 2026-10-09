import 'package:flutter/material.dart';

import '../app.dart';
import '../render/palette.dart';
import '../render/ring_themes.dart';
import 'hud.dart';

/// Everything in the game, one line each.
class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  static const _sections = <(String, List<(IconData, int, String, String)>)>[
    (
      'THE BASICS',
      [
        (
          Icons.touch_app_rounded,
          3,
          'Tap on its color',
          'Tap when the pointer is on the zone matching the ball.',
        ),
        (
          Icons.timelapse_rounded,
          2,
          'Fuse',
          'The ring around the ball burns down. If the pointer passes the zone, you lose.',
        ),
        (
          Icons.center_focus_strong_rounded,
          1,
          'Perfect',
          'Hit the bright band in the middle of a zone: 3 points and a combo.',
        ),
        (
          Icons.local_fire_department_rounded,
          0,
          'Fever',
          '5 Perfects in a row: double points and a faster pointer. A Good ends it.',
        ),
        (
          Icons.more_horiz_rounded,
          3,
          'Lock sets',
          'Clear the dots above the ball in a row for a bonus.',
        ),
      ],
    ),
    (
      'SPECIAL ROUNDS',
      [
        (
          Icons.block_rounded,
          0,
          'NOT',
          'The ball shows a crossed-out color: hit any color except that one.',
        ),
        (
          Icons.call_split_rounded,
          1,
          'Split',
          'Two-color ball: hit the left color, then the right one, in one lap.',
        ),
        (
          Icons.psychology_rounded,
          2,
          'Boss',
          'Every 25 rounds: watch the colors flash, then hit them in order.',
        ),
      ],
    ),
    (
      'TWISTS',
      [
        (
          Icons.swap_horiz_rounded,
          1,
          'Reverse',
          'The pointer flips direction after each hit.',
        ),
        (
          Icons.rotate_right_rounded,
          3,
          'Spin',
          'The whole ring turns while the pointer moves.',
        ),
        (
          Icons.blur_on_rounded,
          2,
          'Ghost',
          'Zones blink in and out. Remember where they are.',
        ),
        (
          Icons.speed_rounded,
          0,
          'Surge',
          'Orange pointer: its speed swings up and down.',
        ),
        (
          Icons.content_copy_rounded,
          1,
          'Decoys',
          'A wrong color right next to the right one.',
        ),
      ],
    ),
    (
      'EXTRAS',
      [
        (
          Icons.star_rounded,
          2,
          'Greedy zone',
          'Thin, gold-rimmed, +5. Riskier than the safe zone after it.',
        ),
        (Icons.shield_rounded, 1, 'Shield', 'Blue badge: absorbs one miss.'),
        (
          Icons.hourglass_bottom_rounded,
          3,
          'Slow-mo',
          'Green badge: the next 4 rounds are slower.',
        ),
        (
          Icons.open_in_full_rounded,
          2,
          'Wide',
          'Yellow badge: bigger zones for 5 rounds.',
        ),
        (
          Icons.monetization_on_rounded,
          2,
          'Coins',
          'Spend them on balls and rings, or on a continue.',
        ),
      ],
    ),
    (
      'MODES',
      [
        (
          Icons.all_inclusive_rounded,
          3,
          'Endless',
          'Tap on the home screen. Go as far as you can; stages change every 20 rounds.',
        ),
        (
          Icons.school_rounded,
          3,
          'Levels',
          'Short levels that teach each mechanic. Earn up to 3 stars.',
        ),
        (
          Icons.today_rounded,
          2,
          'Daily',
          'The same run for everyone today. One attempt (more with an ad).',
        ),
        (
          Icons.self_improvement_rounded,
          1,
          'Zen',
          'No game over and no score. Just play.',
        ),
        (
          Icons.sports_kabaddi_rounded,
          0,
          'Duel',
          'Send a friend your code; they play your exact run and try to beat you.',
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final theme = ringThemeById(s.profile.profile.theme);
    return Scaffold(
      backgroundColor: theme.bgBottom,
      appBar: AppBar(
        backgroundColor: theme.bgTop,
        foregroundColor: theme.text,
        title: const Text(
          'HOW TO PLAY',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          for (final (title, items) in _sections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 18, 8, 6),
              child: Text(title, style: hudLabel(theme, size: 13)),
            ),
            for (final (icon, color, name, text) in items)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: HuePalette.standard[color].withValues(
                    alpha: 0.2,
                  ),
                  child: Icon(icon, color: HuePalette.standard[color]),
                ),
                title: Text(
                  name,
                  style: TextStyle(
                    color: theme.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  text,
                  style: TextStyle(color: theme.subtleText, height: 1.3),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
