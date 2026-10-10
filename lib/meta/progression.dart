import 'dart:math' as math;

import '../config/game_config.dart';
import '../core/seeded_random.dart';
import '../game/game_engine.dart';
import '../render/ball_skins.dart';
import '../render/ring_themes.dart';
import '../services/profile_store.dart';

/// Lifetime counter keys (PlayerProfile.stats).
abstract final class Stat {
  static const runs = 'runs';
  static const rounds = 'rounds';
  static const perfects = 'perfects';
  static const bosses = 'bosses';
  static const fevers = 'fevers';
  static const powerUps = 'powerUps';
  static const notCleared = 'notCleared';
  static const splitCleared = 'splitCleared';
  static const greedy = 'greedy';
  static const bestStreak = 'bestStreak';
  static const bestStage = 'bestStage';
  static const dailyPlays = 'dailyPlays';
  static const duelsWon = 'duelsWon';
  static const zenHits = 'zenHits';
  static const levelsDone = 'levelsDone';
}

// ---------------------------------------------------------------------------
// XP and player level
// ---------------------------------------------------------------------------

/// XP needed to go from [level] to the next one.
int xpToNext(int level) => 80 + 40 * (level - 1);

/// Player level for a lifetime XP total (starts at 1).
int levelForXp(int xp) {
  var level = 1;
  var left = xp;
  while (left >= xpToNext(level)) {
    left -= xpToNext(level);
    level++;
  }
  return level;
}

/// XP into the current level, and the size of that level.
(int, int) levelProgress(int xp) {
  var level = 1;
  var left = xp;
  while (left >= xpToNext(level)) {
    left -= xpToNext(level);
    level++;
  }
  return (left, xpToNext(level));
}

/// XP a finished run is worth.
int xpForRun(RunSummary s) {
  if (s.mode == RunMode.zen) return math.min(30, s.hits ~/ 2);
  return s.level * 2 +
      s.perfects +
      s.bossesCleared * 15 +
      s.fevers * 5 +
      (s.completed ? 10 + s.stars * 5 : 0);
}

/// What reaching a player level gives.
class LevelReward {
  const LevelReward(
    this.level, {
    this.coins = 0,
    this.tokens = 0,
    this.ball,
    this.theme,
  });

  final int level;
  final int coins;
  final int tokens;

  /// Shop items unlocked for free at milestones.
  final String? ball;
  final String? theme;
}

LevelReward rewardForLevel(int level) {
  const milestones = {
    3: LevelReward(3, coins: 60, ball: 'planet'),
    5: LevelReward(5, coins: 80, tokens: 1, ball: 'donut'),
    8: LevelReward(8, coins: 100, ball: 'disco'),
    10: LevelReward(10, coins: 120, tokens: 2, theme: 'neon'),
    12: LevelReward(12, coins: 140, ball: 'gem'),
    15: LevelReward(15, coins: 160, tokens: 2, theme: 'candy'),
  };
  return milestones[level] ?? LevelReward(level, coins: 40 + 5 * level);
}

// ---------------------------------------------------------------------------
// Missions: three at a time, replaced when claimed
// ---------------------------------------------------------------------------

enum MissionType {
  score('Score {n} in one run', perRun: true),
  streak('Get {n} Perfects in a row', perRun: true),
  stage('Reach stage {n} in Endless', perRun: true),
  runs('Play {n} runs'),
  rounds('Clear {n} rounds'),
  perfects('Hit {n} Perfects'),
  bosses('Beat {n} boss rounds'),
  fevers('Trigger Fever {n} times'),
  powerUps('Collect {n} power-ups'),
  notRounds('Clear {n} NOT rounds'),
  daily('Play the Daily Challenge {n} times'),
  levels('Earn {n} level stars');

  const MissionType(this.text, {this.perRun = false});

  final String text;

  /// Progress is the best single run, not a running total.
  final bool perRun;
}

class Mission {
  Mission(
    this.type,
    this.target,
    this.coins, {
    this.progress = 0,
    this.claimed = false,
  });

  factory Mission.fromJson(Map<String, dynamic> j) => Mission(
    MissionType.values.firstWhere(
      (t) => t.name == j['type'],
      orElse: () => MissionType.runs,
    ),
    (j['target'] as num?)?.toInt() ?? 1,
    (j['coins'] as num?)?.toInt() ?? 50,
    progress: (j['progress'] as num?)?.toInt() ?? 0,
    claimed: j['claimed'] == true,
  );

  final MissionType type;
  final int target;
  final int coins;
  int progress;
  bool claimed;

  bool get done => progress >= target;
  String get title => type.text.replaceAll('{n}', '$target');
  int get xp => 20 + coins ~/ 4;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'target': target,
    'coins': coins,
    'progress': progress,
    'claimed': claimed,
  };

  int valueFrom(RunSummary s, {required int starsGained}) => switch (type) {
    MissionType.score => s.mode == RunMode.zen ? 0 : s.score,
    MissionType.streak => s.bestPerfectStreak,
    MissionType.stage => s.mode == RunMode.endless ? s.world + 1 : 0,
    MissionType.runs => s.mode == RunMode.zen ? 0 : 1,
    MissionType.rounds => s.level,
    MissionType.perfects => s.perfects,
    MissionType.bosses => s.bossesCleared,
    MissionType.fevers => s.fevers,
    MissionType.powerUps => s.powerUps,
    MissionType.notRounds => s.notCleared,
    MissionType.daily => s.mode == RunMode.daily ? 1 : 0,
    MissionType.levels => starsGained,
  };
}

/// Mission targets grow with the player level.
Mission _newMission(SeededRandom rng, int playerLevel, Set<MissionType> taken) {
  final tier = math.min(6, 1 + playerLevel ~/ 3);
  final options = MissionType.values.where((t) => !taken.contains(t)).toList();
  final type = options[rng.nextInt(options.length)];
  final target = switch (type) {
    MissionType.score => 30 * tier + 20,
    MissionType.streak => 3 + 2 * tier,
    MissionType.stage => 1 + tier,
    MissionType.runs => 3 + 2 * tier,
    MissionType.rounds => 40 * tier,
    MissionType.perfects => 25 * tier,
    MissionType.bosses => tier < 3 ? 1 : 2,
    MissionType.fevers => 1 + tier,
    MissionType.powerUps => 2 + tier,
    MissionType.notRounds => 4 + 3 * tier,
    MissionType.daily => 1 + tier ~/ 3,
    MissionType.levels => 2 + tier,
  };
  return Mission(type, target, 40 + 20 * tier);
}

List<Mission> missionsOf(PlayerProfile p) => [
  for (final m in p.missions) Mission.fromJson(m),
];

/// Keeps exactly three unclaimed missions.
void ensureMissions(PlayerProfile p) {
  final list = missionsOf(p).where((m) => !m.claimed).toList();
  while (list.length < 3) {
    final rng = SeededRandom(0x4d15 + p.missionSerial * 7919);
    p.missionSerial++;
    list.add(
      _newMission(rng, levelForXp(p.xp), {for (final m in list) m.type}),
    );
  }
  p.missions = [for (final m in list) m.toJson()];
}

/// Adds a finished run to mission progress; returns missions just completed.
List<Mission> applyRunToMissions(
  PlayerProfile p,
  RunSummary s, {
  int starsGained = 0,
}) {
  ensureMissions(p);
  final list = missionsOf(p);
  final completed = <Mission>[];
  for (final m in list) {
    if (m.done) continue;
    final v = m.valueFrom(s, starsGained: starsGained);
    m.progress = m.type.perRun ? math.max(m.progress, v) : m.progress + v;
    if (m.done) completed.add(m);
  }
  p.missions = [for (final m in list) m.toJson()];
  return completed;
}

/// Claims a completed mission; returns it (with its reward) or null.
Mission? claimMission(PlayerProfile p, int index) {
  final list = missionsOf(p);
  if (index < 0 || index >= list.length) return null;
  final m = list[index];
  if (!m.done || m.claimed) return null;
  m.claimed = true;
  p.coins += m.coins;
  p.missions = [for (final x in list) x.toJson()];
  ensureMissions(p);
  return m;
}

// ---------------------------------------------------------------------------
// Daily login reward (7-day streak)
// ---------------------------------------------------------------------------

class DailyReward {
  const DailyReward(this.day, this.coins, {this.tokens = 0});
  final int day;
  final int coins;
  final int tokens;
}

const dailyRewards = [
  DailyReward(1, 40),
  DailyReward(2, 60),
  DailyReward(3, 80),
  DailyReward(4, 100, tokens: 1),
  DailyReward(5, 120),
  DailyReward(6, 150),
  DailyReward(7, 250, tokens: 2),
];

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime _parseDay(String key) {
  final parts = key.split('-').map(int.parse).toList();
  return DateTime.utc(parts[0], parts[1], parts[2]);
}

bool canClaimDailyReward(PlayerProfile p, DateTime nowLocal) =>
    p.lastRewardDay != dayKey(nowLocal);

/// The reward that a claim today would give (streak continues only if the
/// last claim was yesterday).
DailyReward nextDailyReward(PlayerProfile p, DateTime nowLocal) {
  var streak = 1;
  if (p.lastRewardDay.isNotEmpty) {
    final last = _parseDay(p.lastRewardDay);
    final today = _parseDay(dayKey(nowLocal));
    if (today.difference(last).inDays == 1) streak = p.rewardStreak + 1;
  }
  return dailyRewards[(streak - 1) % dailyRewards.length];
}

DailyReward? claimDailyReward(PlayerProfile p, DateTime nowLocal) {
  if (!canClaimDailyReward(p, nowLocal)) return null;
  final reward = nextDailyReward(p, nowLocal);
  final today = _parseDay(dayKey(nowLocal));
  final continues =
      p.lastRewardDay.isNotEmpty &&
      today.difference(_parseDay(p.lastRewardDay)).inDays == 1;
  p.rewardStreak = continues ? p.rewardStreak + 1 : 1;
  p.lastRewardDay = dayKey(nowLocal);
  p.coins += reward.coins;
  p.tokens += reward.tokens;
  return reward;
}

// ---------------------------------------------------------------------------
// Achievements (mirrored to Game Center / Play Games when configured)
// ---------------------------------------------------------------------------

class AchievementDef {
  const AchievementDef(this.id, this.title, this.description, this.test);

  final String id;
  final String title;
  final String description;
  final bool Function(PlayerProfile p) test;
}

final achievementDefs = <AchievementDef>[
  AchievementDef(
    'first_lock',
    'First Lock',
    'Clear your first round',
    (p) => p.stat(Stat.rounds) >= 1,
  ),
  AchievementDef(
    'score_50',
    'Getting Warm',
    'Score 50 in one run',
    (p) => p.bestScore >= 50,
  ),
  AchievementDef(
    'score_250',
    'On Fire',
    'Score 250 in one run',
    (p) => p.bestScore >= 250,
  ),
  AchievementDef(
    'score_1000',
    'Hue Master',
    'Score 1000 in one run',
    (p) => p.bestScore >= 1000,
  ),
  AchievementDef(
    'streak_10',
    'Sharpshooter',
    '10 Perfects in a row',
    (p) => p.stat(Stat.bestStreak) >= 10,
  ),
  AchievementDef(
    'streak_25',
    'Laser Focus',
    '25 Perfects in a row',
    (p) => p.stat(Stat.bestStreak) >= 25,
  ),
  AchievementDef(
    'fever_1',
    'Feverish',
    'Trigger Fever',
    (p) => p.stat(Stat.fevers) >= 1,
  ),
  AchievementDef(
    'boss_1',
    'Memory Lane',
    'Beat a boss round',
    (p) => p.stat(Stat.bosses) >= 1,
  ),
  AchievementDef(
    'boss_10',
    'Elephant Brain',
    'Beat 10 boss rounds',
    (p) => p.stat(Stat.bosses) >= 10,
  ),
  AchievementDef(
    'stage_3',
    'Explorer',
    'Reach stage 3 (Ember)',
    (p) => p.stat(Stat.bestStage) >= 3,
  ),
  AchievementDef(
    'stage_6',
    'Into the Void',
    'Reach stage 6 (Void)',
    (p) => p.stat(Stat.bestStage) >= 6,
  ),
  AchievementDef(
    'not_50',
    'Contrarian',
    'Clear 50 NOT rounds',
    (p) => p.stat(Stat.notCleared) >= 50,
  ),
  AchievementDef(
    'greedy_25',
    'Greedy',
    'Hit 25 gold zones',
    (p) => p.stat(Stat.greedy) >= 25,
  ),
  AchievementDef(
    'runs_100',
    'Just One More',
    'Play 100 runs',
    (p) => p.stat(Stat.runs) >= 100,
  ),
  AchievementDef(
    'daily_7',
    'Regular',
    'Play 7 Daily Challenges',
    (p) => p.stat(Stat.dailyPlays) >= 7,
  ),
  AchievementDef(
    'duel_win',
    'Rival',
    'Win a friend duel',
    (p) => p.stat(Stat.duelsWon) >= 1,
  ),
  AchievementDef(
    'levels_all',
    'Graduate',
    'Clear every level',
    (p) => p.stat(Stat.levelsDone) >= 24,
  ),
  AchievementDef(
    'level_10',
    'Seasoned',
    'Reach player level 10',
    (p) => levelForXp(p.xp) >= 10,
  ),
];

/// Newly earned achievements (also marks them on the profile).
List<AchievementDef> checkAchievements(PlayerProfile p) {
  final earned = <AchievementDef>[];
  for (final a in achievementDefs) {
    if (!p.achievements.contains(a.id) && a.test(p)) {
      p.achievements.add(a.id);
      earned.add(a);
    }
  }
  return earned;
}

// ---------------------------------------------------------------------------
// Applying a finished run
// ---------------------------------------------------------------------------

class RunRewards {
  RunRewards({
    required this.xp,
    required this.levelsGained,
    required this.missions,
    required this.achievements,
  });

  final int xp;
  final List<LevelReward> levelsGained;
  final List<Mission> missions;
  final List<AchievementDef> achievements;
}

/// Lifetime stats, XP / level rewards, missions and achievements for a run.
RunRewards applyRun(PlayerProfile p, RunSummary s, {int starsGained = 0}) {
  if (s.mode != RunMode.zen) p.addStat(Stat.runs, 1);
  p.addStat(Stat.rounds, s.level);
  p.addStat(Stat.perfects, s.perfects);
  p.addStat(Stat.bosses, s.bossesCleared);
  p.addStat(Stat.fevers, s.fevers);
  p.addStat(Stat.powerUps, s.powerUps);
  p.addStat(Stat.notCleared, s.notCleared);
  p.addStat(Stat.splitCleared, s.splitCleared);
  p.addStat(Stat.greedy, s.greedyHits);
  p.maxStat(Stat.bestStreak, s.bestPerfectStreak);
  if (s.mode == RunMode.endless) p.maxStat(Stat.bestStage, s.world + 1);
  if (s.mode == RunMode.daily) p.addStat(Stat.dailyPlays, 1);
  if (s.mode == RunMode.zen) p.addStat(Stat.zenHits, s.hits);

  final xp = xpForRun(s);
  final before = levelForXp(p.xp);
  p.xp += xp;
  final after = levelForXp(p.xp);
  final gained = <LevelReward>[];
  for (var l = math.max(before + 1, p.rewardedLevel + 1); l <= after; l++) {
    final r = rewardForLevel(l);
    p.coins += r.coins;
    p.tokens += r.tokens;
    if (r.ball != null) p.ownedBalls.add(r.ball!);
    if (r.theme != null) p.ownedThemes.add(r.theme!);
    gained.add(r);
  }
  if (after > p.rewardedLevel) p.rewardedLevel = after;

  final missions = applyRunToMissions(p, s, starsGained: starsGained);
  final achievements = checkAchievements(p);
  return RunRewards(
    xp: xp,
    levelsGained: gained,
    missions: missions,
    achievements: achievements,
  );
}

// ---------------------------------------------------------------------------
// "So close": what the player is nearest to after a run
// ---------------------------------------------------------------------------

class NextGoal {
  const NextGoal(this.text, this.fraction, {this.detail});

  final String text;

  /// How far along, 0..1.
  final double fraction;

  /// Short progress label ("42 / 50"), if any.
  final String? detail;
}

/// What a player reached [s] is closest to: a new best, the next stage or
/// boss, a mission, the next player-level unlock. Most nearly done first.
/// [applied]: the run's XP and mission progress are already in [p].
List<NextGoal> nextGoals(
  PlayerProfile p,
  RunSummary s, {
  required GameConfig config,
  required int best,
  required bool applied,
  int max = 2,
}) {
  if (s.mode == RunMode.zen || s.mode == RunMode.level) return const [];
  final out = <NextGoal>[];

  if ((s.mode == RunMode.endless || s.mode == RunMode.daily) &&
      best > 0 &&
      s.score <= best) {
    out.add(
      NextGoal(
        best - s.score + 1 == 1
            ? '1 more point for a new best'
            : '${best - s.score + 1} more points for a new best',
        s.score / (best + 1),
        detail: '${s.score} / ${best + 1}',
      ),
    );
  }

  final stageEvery = config.worlds.every;
  final bossEvery = config.boss.every;
  if (s.mode == RunMode.endless && stageEvery > 0) {
    final into = s.level % stageEvery;
    final left = stageEvery - into;
    out.add(
      NextGoal(
        '$left ${left == 1 ? 'round' : 'rounds'} to Stage ${s.world + 2} · '
        '${worldName(s.world + 1)}',
        into / stageEvery,
      ),
    );
  }
  if (bossEvery > 0 && s.level > 0) {
    final into = s.level % bossEvery;
    out.add(
      into == 0
          ? const NextGoal('Beat the boss to pick a perk', 0.97)
          : NextGoal(
              '${bossEvery - into} rounds to the next boss and a perk',
              into / bossEvery,
            ),
    );
  }

  for (final m in missionsOf(p)) {
    if (m.claimed || (applied && m.done)) continue;
    final v = m.valueFrom(s, starsGained: 0);
    final progress = applied
        ? m.progress
        : (m.type.perRun ? math.max(m.progress, v) : m.progress + v);
    if (progress >= m.target) continue;
    out.add(
      NextGoal(
        'Mission: ${m.title}',
        progress / m.target,
        detail: '$progress / ${m.target}',
      ),
    );
  }

  final xp = applied ? p.xp : p.xp + xpForRun(s);
  final level = levelForXp(xp);
  final (into, size) = levelProgress(xp);
  final reward = rewardForLevel(level + 1);
  final unlock = reward.ball != null
      ? 'the ${ballSkinById(reward.ball!).name} ball'
      : reward.theme != null
      ? 'the ${ringThemeById(reward.theme!).name} ring'
      : '${reward.coins} coins';
  out.add(
    NextGoal(
      'Player level ${level + 1}: $unlock',
      into / size,
      detail: '${size - into} XP to go',
    ),
  );

  out.sort((a, b) => b.fraction.compareTo(a.fraction));
  return out.take(max).toList();
}

// ---------------------------------------------------------------------------
// Daily Challenge and friend duels
// ---------------------------------------------------------------------------

/// The Daily Challenge day follows Pacific time, which is when Play Games
/// daily leaderboards reset, so everyone's "today" matches the board.
String dailyChallengeDay(DateTime nowUtc) {
  final y = nowUtc.year;
  // US DST: second Sunday of March 10:00 UTC to first Sunday of November
  // 09:00 UTC.
  DateTime nthSunday(int month, int n) {
    var d = DateTime.utc(y, month, 1);
    while (d.weekday != DateTime.sunday) {
      d = d.add(const Duration(days: 1));
    }
    return d.add(Duration(days: 7 * (n - 1)));
  }

  final dstStart = nthSunday(3, 2).add(const Duration(hours: 10));
  final dstEnd = nthSunday(11, 1).add(const Duration(hours: 9));
  final dst = !nowUtc.isBefore(dstStart) && nowUtc.isBefore(dstEnd);
  return dayKey(nowUtc.subtract(Duration(hours: dst ? 7 : 8)));
}

/// Same seed for everyone on the same day.
int dailySeed(String day) {
  var h = 0x811c9dc5;
  for (final c in 'hue-lock-daily-$day'.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0x7FFFFFFF;
  }
  return h;
}

/// Challenge number shown to players (#1 = launch day).
int dailyNumber(String day) =>
    _parseDay(day).difference(DateTime.utc(2026, 10, 1)).inDays + 1;

const dailyFreeAttempts = 1;
const dailyMaxAdAttempts = 2;

/// Resets the daily counters when the day changed.
void rollDaily(PlayerProfile p, String today) {
  if (p.dailyDay == today) return;
  p.dailyDay = today;
  p.dailyAttempts = 0;
  p.dailyExtraAttempts = 0;
  p.dailyBest = 0;
}

int dailyAttemptsLeft(PlayerProfile p) =>
    dailyFreeAttempts + p.dailyExtraAttempts - p.dailyAttempts;

/// Friend duel code: the run's seed and the score to beat, e.g.
/// "HL-4F7KQ2MXA9C". No server: the friend types it in.
abstract final class DuelCode {
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'; // Crockford

  /// 5-bit checksum mixing every bit of both values, so a mistyped
  /// character is almost always caught.
  static int _check(int seed, int score) {
    var h = (seed * 0x45d9f3b + score * 0x119de1f3 + 0x27d4eb2d) & 0xFFFFFFFF;
    h ^= h >> 16;
    h = (h * 0x45d9f3b) & 0xFFFFFFFF;
    h ^= h >> 16;
    return h & 31;
  }

  static String encode(int seed, int score) {
    final s = seed & 0x7FFFFFFF;
    final sc = score.clamp(0, 0xFFFFF);
    final check = _check(s, sc);
    var v =
        (BigInt.from(s) << 25) | (BigInt.from(sc) << 5) | BigInt.from(check);
    final chars = <String>[];
    for (var i = 0; i < 12; i++) {
      chars.add(_alphabet[(v & BigInt.from(31)).toInt()]);
      v >>= 5;
    }
    return 'HL-${chars.reversed.join()}';
  }

  /// (seed, score) or null if the code is not valid.
  static (int, int)? decode(String code) {
    var c = code.toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), '');
    if (c.startsWith('HL')) c = c.substring(2);
    c = c.replaceAll('O', '0').replaceAll('I', '1').replaceAll('L', '1');
    if (c.length != 12) return null;
    var v = BigInt.zero;
    for (final ch in c.split('')) {
      final i = _alphabet.indexOf(ch);
      if (i < 0) return null;
      v = (v << 5) | BigInt.from(i);
    }
    final check = (v & BigInt.from(31)).toInt();
    final score = ((v >> 5) & BigInt.from(0xFFFFF)).toInt();
    final seed = (v >> 25).toInt();
    if (seed > 0x7FFFFFFF) return null;
    if (_check(seed, score) != check) return null;
    return (seed, score);
  }
}
