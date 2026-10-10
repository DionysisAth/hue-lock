import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../config/game_config.dart';
import '../game/star_goals.dart';
import '../services/profile_store.dart';

/// What finishing every level of a chapter gives (once).
class ChapterReward {
  const ChapterReward({this.coins = 0, this.tokens = 0, this.ball, this.theme});

  factory ChapterReward.fromJson(Map<String, dynamic> j) => ChapterReward(
    coins: (j['coins'] as num?)?.toInt() ?? 0,
    tokens: (j['tokens'] as num?)?.toInt() ?? 0,
    ball: j['ball'] as String?,
    theme: j['theme'] as String?,
  );

  final int coins;
  final int tokens;
  final String? ball;
  final String? theme;
}

/// Extra reward for every star of a chapter (all goals of all its levels).
const chapterStarBonus = ChapterReward(coins: 50, tokens: 1);

class ChapterDef {
  ChapterDef({
    required this.index,
    required this.title,
    required this.unlockStars,
    required this.reward,
  });

  final int index;
  final String title;

  /// Total level stars needed to open this chapter.
  final int unlockStars;
  final ChapterReward reward;
  final levels = <LevelDef>[];

  String get id => 'C${index + 1}';
  int get number => index + 1;
  int get maxStars => levels.length * 3;
}

/// One hand-made level (assets/config/levels.json).
class LevelDef {
  LevelDef({
    required this.index,
    required this.chapterDef,
    required this.title,
    required this.teaches,
    required this.targets,
    required this.overrides,
    required this.goals,
  });

  /// 0-based position in the whole list; also the run seed.
  final int index;
  final ChapterDef chapterDef;
  final String title;

  /// One-line lesson shown before the level starts.
  final String teaches;

  /// Rounds to clear.
  final int targets;

  /// Deep-merged over the base game config for this level's runs.
  final Map<String, dynamic> overrides;

  /// The goals for the second and third star (the first is for clearing).
  final List<StarGoal> goals;

  int get chapter => chapterDef.index;
  String get chapterTitle => chapterDef.title;
  String get id => 'L${index + 1}';
  int get number => index + 1;
  int get seed => 0x1E7E1 + index * 7919;

  GameConfig configFrom(GameConfig base) =>
      GameConfig.fromJson(deepMerge(base.raw, overrides));
}

/// Every stage key, off by default, so a level only lists what it uses.
const _stageDefaults = <String, dynamic>{
  'fromLevel': 0,
  'name': 'level',
  'colors': [1, 1],
  'locks': [1, 2],
  'reverse': 0.0,
  'decoys': 0,
  'rotate': 0.0,
  'bonus': 0.0,
  'inverted': 0.0,
  'split': 0.0,
  'ghost': 0.0,
  'pulse': 0.0,
};

List<LevelDef> parseLevels(String source) {
  final root = jsonDecode(source) as Map<String, dynamic>;
  final out = <LevelDef>[];
  final chapters = root['chapters'] as List;
  for (var c = 0; c < chapters.length; c++) {
    final chapter = chapters[c] as Map<String, dynamic>;
    final def = ChapterDef(
      index: c,
      title: chapter['title'] as String,
      unlockStars: (chapter['unlockStars'] as num?)?.toInt() ?? 0,
      reward: ChapterReward.fromJson(
        (chapter['reward'] as Map<String, dynamic>?) ?? const {},
      ),
    );
    for (final raw in chapter['levels'] as List) {
      final l = raw as Map<String, dynamic>;
      double d(String k, double fallback) =>
          (l[k] as num?)?.toDouble() ?? fallback;
      final stage = {
        ..._stageDefaults,
        ...(l['stage'] as Map<String, dynamic>? ?? const {}),
      };
      final bossLength = (l['bossLength'] as List?) ?? const [3, 3];
      final overrides = <String, dynamic>{
        'stages': [stage],
        'pointer': {
          'baseSpeedDegPerSec': d('speed', 120),
          'speedPerLevel': d('speedPerTarget', 2),
          'maxSpeedDegPerSec': 330,
        },
        'zone': {
          'startSizeDeg': d('size', 52),
          'sizePerLevel': d('sizePerTarget', -0.4),
        },
        // No breather rounds, stages or surprise bosses inside a level.
        'wave': {'period': 0, 'breatherLevelDrop': 0},
        'worlds': {'every': 0},
        'boss': {
          'every': (l['bossEvery'] as num?)?.toInt() ?? 0,
          'sequenceLength': bossLength,
        },
        'powerUps': {'chance': d('powerUpChance', 0), 'minLevel': 1},
        'coins': {'coinZoneChance': 0.0},
      };
      final level = LevelDef(
        index: out.length,
        chapterDef: def,
        title: l['title'] as String,
        teaches: l['teaches'] as String,
        targets: (l['targets'] as num).toInt(),
        overrides: overrides,
        goals: [
          for (final g
              in (l['goals'] as List?) ?? const ['ratio:50', 'ratio:80'])
            StarGoal.parse(g as String),
        ],
      );
      def.levels.add(level);
      out.add(level);
    }
  }
  return out;
}

/// The chapters of [levels], in order.
List<ChapterDef> chaptersOf(List<LevelDef> levels) => [
  for (final l in levels)
    if (l.chapterDef.levels.first == l) l.chapterDef,
];

int totalStars(Map<String, int> stars) =>
    stars.values.fold<int>(0, (a, b) => a + b);

/// Stars earned in [chapter].
int chapterStars(ChapterDef chapter, Map<String, int> stars) =>
    chapter.levels.fold<int>(0, (a, l) => a + (stars[l.id] ?? 0));

/// Enough stars overall to open [chapter].
bool chapterOpen(ChapterDef chapter, Map<String, int> stars) =>
    totalStars(stars) >= chapter.unlockStars;

/// Every level of [chapter] cleared.
bool chapterCleared(ChapterDef chapter, Map<String, int> stars) =>
    chapter.levels.every((l) => (stars[l.id] ?? 0) > 0);

/// Goals met so far on a level (bit 0 = cleared), including saves from
/// before goals were tracked one by one.
int levelGoalsOf(PlayerProfile p, String id) =>
    p.levelGoals[id] ?? ((1 << (p.levelStars[id] ?? 0)) - 1);

/// Adds a level run's goals to the profile; returns the new star count.
int recordLevelGoals(PlayerProfile p, String id, int mask) {
  final merged = levelGoalsOf(p, id) | mask;
  p.levelGoals[id] = merged;
  p.levelStars[id] = starCount(merged);
  return p.levelStars[id]!;
}

/// Rewards for chapters newly cleared (and newly completed with every
/// star). Gives them to the profile and marks them as claimed.
List<(ChapterDef, ChapterReward)> claimChapterRewards(
  PlayerProfile p,
  List<LevelDef> levels,
) {
  final out = <(ChapterDef, ChapterReward)>[];
  void give(ChapterDef c, String key, ChapterReward r) {
    if (!p.chapterRewards.add(key)) return;
    p.coins += r.coins;
    p.tokens += r.tokens;
    if (r.ball != null) p.ownedBalls.add(r.ball!);
    if (r.theme != null) p.ownedThemes.add(r.theme!);
    out.add((c, r));
  }

  for (final c in chaptersOf(levels)) {
    if (chapterCleared(c, p.levelStars)) give(c, c.id, c.reward);
    if (chapterStars(c, p.levelStars) >= c.maxStars) {
      give(c, '${c.id}*', chapterStarBonus);
    }
  }
  return out;
}

Future<List<LevelDef>> loadLevels() async =>
    parseLevels(await rootBundle.loadString('assets/config/levels.json'));

/// A level is playable once the previous one has at least one star and its
/// chapter is open (enough stars in total).
bool levelUnlocked(List<LevelDef> levels, Map<String, int> stars, int index) =>
    index == 0 ||
    ((stars[levels[index - 1].id] ?? 0) > 0 &&
        chapterOpen(levels[index].chapterDef, stars));
