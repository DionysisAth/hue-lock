import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../config/game_config.dart';

/// One hand-made level (assets/config/levels.json).
class LevelDef {
  LevelDef({
    required this.index,
    required this.chapter,
    required this.chapterTitle,
    required this.title,
    required this.teaches,
    required this.targets,
    required this.overrides,
    required this.stars,
  });

  /// 0-based position in the whole list; also the run seed.
  final int index;
  final int chapter;
  final String chapterTitle;
  final String title;

  /// One-line lesson shown before the level starts.
  final String teaches;

  /// Rounds to clear.
  final int targets;

  /// Deep-merged over the base game config for this level's runs.
  final Map<String, dynamic> overrides;

  /// Perfect ratio needed for 2 and 3 stars.
  final List<double> stars;

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
  final defaultStars = [
    for (final v in root['stars'] as List) (v as num).toDouble(),
  ];
  final out = <LevelDef>[];
  final chapters = root['chapters'] as List;
  for (var c = 0; c < chapters.length; c++) {
    final chapter = chapters[c] as Map<String, dynamic>;
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
      out.add(
        LevelDef(
          index: out.length,
          chapter: c,
          chapterTitle: chapter['title'] as String,
          title: l['title'] as String,
          teaches: l['teaches'] as String,
          targets: (l['targets'] as num).toInt(),
          overrides: overrides,
          stars: defaultStars,
        ),
      );
    }
  }
  return out;
}

Future<List<LevelDef>> loadLevels() async =>
    parseLevels(await rootBundle.loadString('assets/config/levels.json'));

/// A level is playable once the previous one has at least one star.
bool levelUnlocked(List<LevelDef> levels, Map<String, int> stars, int index) =>
    index == 0 || (stars[levels[index - 1].id] ?? 0) > 0;
