import 'package:flutter/material.dart';

import '../app.dart';
import '../meta/levels.dart';
import '../render/palette.dart';
import '../render/ring_themes.dart';
import 'hud.dart';
import 'widgets.dart';

/// Levels mode: chapters that each teach one mechanic. Pops with the
/// [LevelDef] to play, or null.
class LevelsScreen extends StatelessWidget {
  const LevelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final p = s.profile.profile;
    final theme = ringThemeById(p.theme);
    final levels = s.levels;
    final totalStars = p.levelStars.values.fold<int>(0, (a, b) => a + b);
    final chapters = <int, List<LevelDef>>{};
    for (final l in levels) {
      chapters.putIfAbsent(l.chapter, () => []).add(l);
    }
    return Scaffold(
      backgroundColor: theme.bgBottom,
      appBar: AppBar(
        backgroundColor: theme.bgTop,
        foregroundColor: theme.text,
        title: const Text(
          'LEVELS',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                const Icon(Icons.star_rounded, color: coinColor),
                const SizedBox(width: 4),
                Text(
                  '$totalStars / ${levels.length * 3}',
                  style: TextStyle(
                    color: theme.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          for (final entry in chapters.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
              child: Text(
                'CHAPTER ${entry.key + 1} · ${entry.value.first.chapterTitle.toUpperCase()}',
                style: hudLabel(theme, size: 13),
              ),
            ),
            Row(
              children: [
                for (final l in entry.value)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: _LevelTile(
                        level: l,
                        stars: p.levelStars[l.id] ?? 0,
                        unlocked: levelUnlocked(levels, p.levelStars, l.index),
                        theme: theme,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LevelTile extends StatelessWidget {
  const _LevelTile({
    required this.level,
    required this.stars,
    required this.unlocked,
    required this.theme,
  });

  final LevelDef level;
  final int stars;
  final bool unlocked;
  final RingTheme theme;

  @override
  Widget build(BuildContext context) {
    final color = HuePalette.standard[level.chapter % 4];
    return Opacity(
      opacity: unlocked ? 1 : 0.45,
      child: Material(
        color: color.withValues(alpha: stars > 0 ? 0.22 : 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withValues(alpha: 0.6), width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: unlocked
              ? () async {
                  final play = await showLevelIntro(context, level, theme);
                  if (play == true && context.mounted) {
                    Navigator.of(context).pop(level);
                  }
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            child: Column(
              children: [
                unlocked
                    ? Text(
                        '${level.number}',
                        style: TextStyle(
                          color: theme.text,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    : Icon(Icons.lock_rounded, color: theme.text, size: 28),
                const SizedBox(height: 2),
                Text(
                  level.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.subtleText,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Icon(
                        i < stars
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 16,
                        color: i < stars ? coinColor : theme.subtleText,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The lesson card shown before a level. Returns true to play.
Future<bool?> showLevelIntro(
  BuildContext context,
  LevelDef level,
  RingTheme theme,
) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: theme.bgTop,
      title: Text(
        'LEVEL ${level.number} · ${level.title.toUpperCase()}',
        style: TextStyle(color: theme.text, fontWeight: FontWeight.w900),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            level.teaches,
            style: TextStyle(color: theme.text, fontSize: 16, height: 1.35),
          ),
          const SizedBox(height: 14),
          Text(
            'Clear ${level.targets} targets without missing.\n'
            '★★ ${(level.stars[0] * 100).round()}% Perfect   '
            '★★★ ${(level.stars[1] * 100).round()}% Perfect',
            style: TextStyle(color: theme.subtleText, height: 1.4),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('PLAY'),
        ),
      ],
    ),
  );
}
