import 'package:flutter/material.dart';

import '../app.dart';
import '../meta/levels.dart';
import '../render/ball_skins.dart';
import '../render/palette.dart';
import '../render/ring_themes.dart';
import 'hud.dart';
import 'widgets.dart';

const _headerHeight = 104.0;
const _rowHeight = 112.0;
const _sectionGap = 18.0;

/// Levels mode as a map: chapters top to bottom, each a winding path of
/// levels with its reward at the end. A chapter opens at a total star
/// count. Pops with the [LevelDef] to play, or null.
class LevelsScreen extends StatefulWidget {
  const LevelsScreen({super.key});

  @override
  State<LevelsScreen> createState() => _LevelsScreenState();
}

class _LevelsScreenState extends State<LevelsScreen> {
  ScrollController? _scroll;

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  static double _sectionHeight(ChapterDef c) =>
      _headerHeight + c.levels.length * _rowHeight + _sectionGap;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final p = s.profile.profile;
    final theme = ringThemeById(p.theme);
    final levels = s.levels;
    final stars = p.levelStars;
    final chapters = chaptersOf(levels);

    // Start scrolled to the chapter of the next level to play.
    final current = levels.lastWhere(
      (l) => levelUnlocked(levels, stars, l.index),
      orElse: () => levels.first,
    );
    var offset = 0.0;
    for (final c in chapters) {
      if (c.index >= current.chapter) break;
      offset += _sectionHeight(c);
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
                  '${totalStars(stars)} / ${levels.length * 3}',
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
        controller: _scroll ??= ScrollController(
          initialScrollOffset: (offset - 24).clamp(0, double.infinity),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          for (final c in chapters)
            SizedBox(
              height: _sectionHeight(c),
              child: _ChapterSection(
                chapter: c,
                levels: levels,
                stars: stars,
                claimed: p.chapterRewards.contains(c.id),
                current: current,
                theme: theme,
              ),
            ),
        ],
      ),
    );
  }
}

class _ChapterSection extends StatelessWidget {
  const _ChapterSection({
    required this.chapter,
    required this.levels,
    required this.stars,
    required this.claimed,
    required this.current,
    required this.theme,
  });

  final ChapterDef chapter;
  final List<LevelDef> levels;
  final Map<String, int> stars;
  final bool claimed;
  final LevelDef current;
  final RingTheme theme;

  @override
  Widget build(BuildContext context) {
    final open = chapterOpen(chapter, stars);
    final color = HuePalette.standard[chapter.index % 4];
    // Alternate the winding direction per chapter.
    final xs = chapter.index.isEven
        ? const [-0.5, 0.0, 0.5, 0.0]
        : const [0.5, 0.0, -0.5, 0.0];
    return Column(
      children: [
        SizedBox(
          height: _headerHeight - 8,
          child: _ChapterHeader(
            chapter: chapter,
            open: open,
            earned: chapterStars(chapter, stars),
            total: totalStars(stars),
            claimed: claimed,
            color: color,
            theme: theme,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: chapter.levels.length * _rowHeight,
          child: LayoutBuilder(
            builder: (context, box) {
              Offset at(int i) => Offset(
                box.maxWidth / 2 * (1 + xs[i % xs.length]),
                _rowHeight * i + 40,
              );
              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _PathPainter(
                        points: [
                          for (var i = 0; i < chapter.levels.length; i++) at(i),
                        ],
                        color: color.withValues(alpha: open ? 0.45 : 0.15),
                      ),
                    ),
                  ),
                  for (var i = 0; i < chapter.levels.length; i++)
                    Positioned(
                      left: at(i).dx - 60,
                      top: at(i).dy - 36,
                      width: 120,
                      child: _LevelNode(
                        level: chapter.levels[i],
                        stars: stars[chapter.levels[i].id] ?? 0,
                        unlocked: levelUnlocked(
                          levels,
                          stars,
                          chapter.levels[i].index,
                        ),
                        current: chapter.levels[i] == current,
                        color: color,
                        theme: theme,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChapterHeader extends StatelessWidget {
  const _ChapterHeader({
    required this.chapter,
    required this.open,
    required this.earned,
    required this.total,
    required this.claimed,
    required this.color,
    required this.theme,
  });

  final ChapterDef chapter;
  final bool open;
  final int earned;
  final int total;
  final bool claimed;
  final Color color;
  final RingTheme theme;

  String get _reward {
    final r = chapter.reward;
    return [
      if (r.ball != null) '${ballSkinById(r.ball!).name} ball',
      if (r.theme != null) '${ringThemeById(r.theme!).name} ring',
      if (r.coins > 0) '${r.coins} coins',
      if (r.tokens > 0) '${r.tokens} token${r.tokens == 1 ? '' : 's'}',
    ].join(' + ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: open ? 0.14 : 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: open ? 0.6 : 0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'CHAPTER ${chapter.number}',
                  style: hudLabel(theme, size: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  open ? chapter.title.toUpperCase() : '???',
                  style: TextStyle(
                    color: theme.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      claimed
                          ? Icons.check_circle_rounded
                          : Icons.card_giftcard_rounded,
                      size: 15,
                      color: claimed ? HuePalette.standard[3] : coinColor,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        _reward,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.subtleText,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          decoration: claimed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (open)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded, color: coinColor, size: 20),
                const SizedBox(width: 3),
                Text(
                  '$earned/${chapter.maxStars}',
                  style: TextStyle(
                    color: theme.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            )
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, color: theme.text, size: 22),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, color: coinColor, size: 14),
                    Text(
                      '$total/${chapter.unlockStars}',
                      style: const TextStyle(
                        color: coinColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// The trail between a chapter's levels (painted once, never animated).
class _PathPainter extends CustomPainter {
  _PathPainter({required this.points, required this.color});

  final List<Offset> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    // From under each node's name to the top of the next node, so the
    // trail never runs through the stars and names.
    final path = Path();
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1] + const Offset(0, 56);
      final b = points[i] - const Offset(0, 33);
      final mid = (a.dy + b.dy) / 2;
      path
        ..moveTo(a.dx, a.dy)
        ..cubicTo(a.dx, mid, b.dx, mid, b.dx, b.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_PathPainter old) =>
      old.color != color || old.points.length != points.length;
}

class _LevelNode extends StatelessWidget {
  const _LevelNode({
    required this.level,
    required this.stars,
    required this.unlocked,
    required this.current,
    required this.color,
    required this.theme,
  });

  final LevelDef level;
  final int stars;
  final bool unlocked;
  final bool current;
  final Color color;
  final RingTheme theme;

  Future<void> _open(BuildContext context) async {
    final play = await showLevelIntro(
      context,
      level,
      theme,
      goalsMet: levelGoalsOf(Services.of(context).profile.profile, level.id),
    );
    if (play == true && context.mounted) Navigator.of(context).pop(level);
  }

  @override
  Widget build(BuildContext context) {
    final cleared = stars > 0;
    final onTap = unlocked ? () => _open(context) : null;
    // The whole node (circle, stars and name) opens the level.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Material(
            shape: CircleBorder(
              side: BorderSide(
                color: unlocked ? color : color.withValues(alpha: 0.3),
                width: current ? 4 : 2,
              ),
            ),
            // Opaque, so the path behind doesn't show through.
            color: cleared
                ? Color.alphaBlend(
                    color.withValues(alpha: 0.32),
                    theme.bgBottom,
                  )
                : (unlocked ? theme.bgTop : theme.bgBottom),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: 58,
                height: 58,
                child: Center(
                  child: unlocked
                      ? Text(
                          '${level.number}',
                          style: TextStyle(
                            color: theme.text,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      : Icon(
                          Icons.lock_rounded,
                          color: theme.subtleText,
                          size: 22,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Icon(
                  i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 15,
                  color: i < stars ? coinColor : theme.subtleText,
                ),
            ],
          ),
          Text(
            level.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: current && !cleared ? color : theme.subtleText,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// The lesson card shown before a level, with its star goals ([goalsMet]
/// bit i+1 = goal i already met). Returns true to play.
Future<bool?> showLevelIntro(
  BuildContext context,
  LevelDef level,
  RingTheme theme, {
  int goalsMet = 0,
}) {
  Widget goalLine(String text, bool done) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Icon(
          done ? Icons.star_rounded : Icons.star_outline_rounded,
          color: done ? coinColor : theme.subtleText,
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: done ? theme.text : theme.subtleText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

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
          const SizedBox(height: 10),
          goalLine(
            'Clear ${level.targets} targets without missing',
            goalsMet & 1 != 0,
          ),
          for (var i = 0; i < level.goals.length; i++)
            goalLine(level.goals[i].text, goalsMet & (1 << (i + 1)) != 0),
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
