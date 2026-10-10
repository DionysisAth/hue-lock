import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_lock/core/angles.dart';
import 'package:hue_lock/game/game_engine.dart';
import 'package:hue_lock/game/star_goals.dart';
import 'package:hue_lock/game/round.dart';
import 'package:hue_lock/game/round_generator.dart';
import 'package:hue_lock/meta/levels.dart';
import 'package:hue_lock/meta/progression.dart';
import 'package:hue_lock/services/profile_store.dart';

import 'test_helpers.dart';

RunSummary run({
  RunMode mode = RunMode.endless,
  int score = 0,
  int level = 0,
  int perfects = 0,
  int hits = 0,
  int bosses = 0,
  int fevers = 0,
  int streak = 0,
  int world = 0,
  bool completed = false,
  int stars = 0,
}) => RunSummary(
  score: score,
  level: level,
  perfects: perfects,
  bestPerfectStreak: streak,
  coinsEarned: 0,
  newCoins: 0,
  duration: 30,
  stageName: '',
  world: world,
  continuesUsed: 0,
  seed: 1,
  mode: mode,
  hits: hits,
  bossesCleared: bosses,
  fevers: fevers,
  completed: completed,
  stars: stars,
);

void main() {
  final config = loadTestConfig();
  final levels = parseLevels(
    File('assets/config/levels.json').readAsStringSync(),
  );

  group('XP and player levels', () {
    test('levels follow the XP curve', () {
      expect(levelForXp(0), 1);
      expect(levelForXp(xpToNext(1) - 1), 1);
      expect(levelForXp(xpToNext(1)), 2);
      expect(levelForXp(xpToNext(1) + xpToNext(2)), 3);
      expect(levelProgress(xpToNext(1) + 5), (5, xpToNext(2)));
    });

    test('a run gives XP, stats and level rewards exactly once', () {
      final p = PlayerProfile();
      final s = run(score: 300, level: 60, perfects: 50, hits: 60, bosses: 2);
      final r = applyRun(p, s);
      expect(r.xp, xpForRun(s));
      expect(p.xp, r.xp);
      expect(p.stat(Stat.runs), 1);
      expect(p.stat(Stat.rounds), 60);
      expect(p.stat(Stat.bosses), 2);
      final level = levelForXp(p.xp);
      expect(level, greaterThan(1));
      expect(r.levelsGained.map((l) => l.level), [
        for (var l = 2; l <= level; l++) l,
      ]);
      expect(p.rewardedLevel, level);
      if (level >= 3) expect(p.ownedBalls, contains('planet'));
      // XP from a later run never re-grants rewards already given.
      final coins = p.coins;
      p.xp = 0;
      final again = applyRun(p, run(level: 1));
      expect(again.levelsGained, isEmpty);
      expect(p.coins, greaterThanOrEqualTo(coins));
    });

    test('Zen gives a little XP and does not count as a run', () {
      final p = PlayerProfile();
      final r = applyRun(p, run(mode: RunMode.zen, hits: 40));
      expect(r.xp, 20);
      expect(p.stat(Stat.runs), 0);
      expect(p.stat(Stat.zenHits), 40);
    });
  });

  group('missions', () {
    test('three at a time; progress, claim and replace', () {
      final p = PlayerProfile();
      ensureMissions(p);
      expect(missionsOf(p), hasLength(3));
      expect(missionsOf(p).map((m) => m.type).toSet(), hasLength(3));

      // A huge run completes most missions.
      final big = run(
        score: 5000,
        level: 200,
        perfects: 180,
        hits: 200,
        bosses: 8,
        fevers: 10,
        streak: 60,
        world: 9,
      );
      for (var i = 0; i < 10; i++) {
        applyRunToMissions(p, big, starsGained: 3);
      }
      final done = missionsOf(p).indexWhere((m) => m.done);
      expect(done, isNot(-1));
      final before = p.coins;
      final claimed = claimMission(p, done);
      expect(claimed, isNotNull);
      expect(p.coins, before + claimed!.coins);
      expect(missionsOf(p), hasLength(3), reason: 'replaced');
      expect(missionsOf(p).every((m) => !m.claimed), isTrue);
      // Cannot claim an unfinished mission.
      final open = missionsOf(p).indexWhere((m) => !m.done);
      if (open >= 0) expect(claimMission(p, open), isNull);
    });
  });

  group('daily login reward', () {
    test('streak grows day by day, resets after a gap, wraps after 7', () {
      final p = PlayerProfile();
      final d0 = DateTime(2026, 10, 1, 9);
      expect(claimDailyReward(p, d0)!.day, 1);
      expect(claimDailyReward(p, d0.add(const Duration(hours: 5))), isNull);
      expect(p.coins, dailyRewards[0].coins);
      for (var i = 1; i < 7; i++) {
        expect(claimDailyReward(p, d0.add(Duration(days: i)))!.day, i + 1);
      }
      expect(p.tokens, 3, reason: 'days 4 and 7 give tokens');
      expect(claimDailyReward(p, d0.add(const Duration(days: 7)))!.day, 1);
      // Skipping a day restarts the streak.
      claimDailyReward(p, d0.add(const Duration(days: 8)));
      expect(p.rewardStreak, 9);
      expect(claimDailyReward(p, d0.add(const Duration(days: 10)))!.day, 1);
      expect(p.rewardStreak, 1);
    });
  });

  group('achievements', () {
    test('unlock once when their condition is met', () {
      final p = PlayerProfile();
      expect(checkAchievements(p), isEmpty);
      p.bestScore = 300;
      p.addStat(Stat.rounds, 5);
      final got = checkAchievements(p).map((a) => a.id);
      expect(got, containsAll(['first_lock', 'score_50', 'score_250']));
      expect(got, isNot(contains('score_1000')));
      expect(checkAchievements(p), isEmpty, reason: 'only once');
      expect(achievementDefs.map((a) => a.id).toSet(), hasLength(18));
    });
  });

  group('Daily Challenge', () {
    test('the day follows Pacific time, with US daylight saving', () {
      // PDT (UTC-7).
      expect(dailyChallengeDay(DateTime.utc(2026, 10, 9, 6, 59)), '2026-10-08');
      expect(dailyChallengeDay(DateTime.utc(2026, 10, 9, 7, 0)), '2026-10-09');
      // PST (UTC-8).
      expect(dailyChallengeDay(DateTime.utc(2026, 12, 1, 7, 59)), '2026-11-30');
      expect(dailyChallengeDay(DateTime.utc(2026, 12, 1, 8, 0)), '2026-12-01');
      // DST switches: 2026-03-08 and 2026-11-01.
      expect(dailyChallengeDay(DateTime.utc(2026, 3, 8, 9, 59)), '2026-03-08');
      expect(dailyChallengeDay(DateTime.utc(2026, 11, 1, 9, 0)), '2026-11-01');
    });

    test('same seed for everyone on a day, numbered from launch', () {
      expect(dailySeed('2026-10-09'), dailySeed('2026-10-09'));
      expect(dailySeed('2026-10-09'), isNot(dailySeed('2026-10-10')));
      expect(dailyNumber('2026-10-01'), 1);
      expect(dailyNumber('2026-10-09'), 9);
    });

    test('one free attempt a day, plus ad attempts; resets each day', () {
      final p = PlayerProfile();
      rollDaily(p, '2026-10-09');
      expect(dailyAttemptsLeft(p), dailyFreeAttempts);
      p.dailyAttempts = 1;
      p.dailyBest = 50;
      expect(dailyAttemptsLeft(p), 0);
      p.dailyExtraAttempts = 1;
      expect(dailyAttemptsLeft(p), 1);
      rollDaily(p, '2026-10-09');
      expect(p.dailyBest, 50, reason: 'same day keeps state');
      rollDaily(p, '2026-10-10');
      expect(dailyAttemptsLeft(p), dailyFreeAttempts);
      expect(p.dailyBest, 0);
    });
  });

  group('duel codes', () {
    test('round-trip, forgiving about case and separators', () {
      for (final (seed, score) in [
        (0, 0),
        (1, 1),
        (123456789, 4321),
        (0x7FFFFFFF, 0xFFFFF),
      ]) {
        final code = DuelCode.encode(seed, score);
        expect(code, matches(RegExp(r'^HL-[0-9A-Z]{12}$')));
        expect(DuelCode.decode(code), (seed, score));
        expect(DuelCode.decode(code.toLowerCase()), (seed, score));
        final spaced = code.replaceAllMapped(
          RegExp('(.{4})'),
          (m) => '${m[1]} ',
        );
        expect(DuelCode.decode(spaced), (seed, score));
      }
    });

    test('rejects garbage and most typos', () {
      expect(DuelCode.decode(''), isNull);
      expect(DuelCode.decode('hello world'), isNull);
      expect(DuelCode.decode('HL-123'), isNull);
      final code = DuelCode.encode(987654, 321);
      var rejected = 0;
      for (var i = 3; i < code.length; i++) {
        final ch = code[i] == '5' ? '6' : '5';
        final typo = code.replaceRange(i, i + 1, ch);
        if (DuelCode.decode(typo) == null) rejected++;
      }
      expect(rejected, greaterThanOrEqualTo(10));
    });
  });

  group('cloud save merge', () {
    test('keeps the further-along progress and unions what was earned', () {
      final local = PlayerProfile()
        ..xp = 100
        ..coins = 10
        ..bestScore = 500
        ..ownedBalls.add('planet')
        ..achievements.add('first_lock')
        ..levelStars = {'L1': 3, 'L2': 1}
        ..stats = {Stat.runs: 5, Stat.perfects: 100};
      final cloud = PlayerProfile()
        ..xp = 400
        ..coins = 70
        ..bestScore = 200
        ..ownedThemes.add('neon')
        ..achievements.add('boss_1')
        ..levelStars = {'L2': 2, 'L3': 1}
        ..stats = {Stat.runs: 9, Stat.perfects: 50};
      local.mergeFrom(cloud);
      expect(local.xp, 400);
      expect(local.coins, 70);
      expect(local.bestScore, 500);
      expect(local.ownedBalls, contains('planet'));
      expect(local.ownedThemes, contains('neon'));
      expect(local.achievements, {'first_lock', 'boss_1'});
      expect(local.levelStars, {'L1': 3, 'L2': 2, 'L3': 1});
      expect(local.stat(Stat.runs), 9);
      expect(local.stat(Stat.perfects), 100);
    });

    test('survives a JSON round-trip', () {
      final p = PlayerProfile()
        ..xp = 1234
        ..tokens = 3
        ..levelStars = {'L1': 2}
        ..levelGoals = {'L1': 5}
        ..chapterRewards = {'C1'}
        ..stats = {Stat.duelsWon: 4}
        ..dailyDay = '2026-10-09'
        ..starterPack = true;
      ensureMissions(p);
      final q = PlayerProfile.fromJson(p.toJson());
      expect(q.toJson(), p.toJson());
    });
  });

  group('levels', () {
    /// A perfect player who also goes for gold zones when there is one.
    void tapBestZone(GameEngine e) {
      waitUntilPlaying(e);
      final r = e.round!;
      final goals = r.spec.steps[r.step].goals;
      final gold = [
        for (final g in goals)
          if (r.spec.zones[g].isBonus && !r.consumed.contains(g))
            r.spec.zones[g],
      ];
      final target = gold.isNotEmpty ? gold.first : r.currentPrimary;
      advance(e, timeUntil(e, target.center) * 0.5);
      e.tap(e.time + timeUntil(e, target.center));
    }

    test('24 levels in 8 chapters, unlocked one by one', () {
      expect(levels, hasLength(24));
      expect(levels.map((l) => l.chapter).toSet(), hasLength(8));
      expect(levels.map((l) => l.id).toSet(), hasLength(24));
      expect(levelUnlocked(levels, {}, 0), isTrue);
      expect(levelUnlocked(levels, {}, 1), isFalse);
      expect(levelUnlocked(levels, {'L1': 1}, 1), isTrue);
    });

    test('chapters open at a star count and pay out once', () {
      final chapters = chaptersOf(levels);
      expect(chapters, hasLength(8));
      expect(chapters.first.unlockStars, 0);
      for (var i = 1; i < chapters.length; i++) {
        expect(
          chapters[i].unlockStars,
          greaterThan(chapters[i - 1].unlockStars),
        );
        // Reachable with stars from the chapters before it.
        expect(chapters[i].unlockStars, lessThanOrEqualTo(i * 9));
      }
      // Chapter 1 cleared with one star each: chapter 2 still needs stars.
      final stars = {'L1': 1, 'L2': 1, 'L3': 1};
      final ch2 = chapters[1].levels.first.index;
      expect(levelUnlocked(levels, stars, ch2), isFalse);
      stars['L1'] = 3;
      expect(levelUnlocked(levels, stars, ch2), isTrue);

      final p = PlayerProfile()..levelStars = Map.of(stars);
      final first = claimChapterRewards(p, levels);
      expect(first.map((r) => r.$1.id), ['C1']);
      expect(p.coins, chapters.first.reward.coins);
      expect(claimChapterRewards(p, levels), isEmpty, reason: 'once only');
      p.levelStars.addAll({'L2': 3, 'L3': 3});
      final bonus = claimChapterRewards(p, levels).single;
      expect(bonus.$2, chapterStarBonus);
      // Item rewards land in the collection.
      p.levelStars.addAll({'L4': 1, 'L5': 1, 'L6': 1});
      claimChapterRewards(p, levels);
      expect(p.ownedBalls, contains(chapters[1].reward.ball));
    });

    test('star goals: each one is its own star and they add up', () {
      final goals = [StarGoal.parse('perfects:5'), StarGoal.parse('streak:4')];
      expect(goals.map((g) => '$g'), ['perfects:5', 'streak:4']);
      expect(StarGoal.parse('shield').type, GoalType.shield);
      expect(() => StarGoal.parse('nope:1'), throwsFormatException);

      RunSummary done({int perfects = 0, int streak = 0}) => RunSummary(
        score: 0,
        level: 10,
        perfects: perfects,
        bestPerfectStreak: streak,
        coinsEarned: 0,
        newCoins: 0,
        duration: 1,
        stageName: '',
        world: 0,
        continuesUsed: 0,
        seed: 1,
        mode: RunMode.level,
        completed: true,
        starGoals: goals,
      );
      expect(done().stars, 1);
      expect(done(perfects: 5).goalsMet, 0x3);
      expect(done(streak: 4).goalsMet, 0x5);
      expect(done(perfects: 9, streak: 9).stars, 3);

      // Stars stay earned across runs: goal A one time, goal B the next.
      final p = PlayerProfile();
      expect(recordLevelGoals(p, 'L1', done(perfects: 5).goalsMet), 2);
      expect(recordLevelGoals(p, 'L1', done(streak: 4).goalsMet), 3);
      expect(recordLevelGoals(p, 'L1', done().goalsMet), 3);
      // Old saves (a star count only) keep their stars.
      final old = PlayerProfile()..levelStars = {'L2': 2};
      expect(levelGoalsOf(old, 'L2'), 0x3);
      expect(recordLevelGoals(old, 'L2', 0x5), 3);
    });

    test('every level generates only fair rounds', () {
      for (final l in levels) {
        final c = l.configFrom(config);
        for (var seed = 0; seed < 8; seed++) {
          final gen = RoundGenerator(c, l.seed + seed);
          var dir = 1;
          int? prev;
          var pointer = 0.0;
          for (var level = 0; level <= l.targets; level++) {
            final spec = gen.next(
              level: level,
              pointerLocal: pointer,
              currentDir: dir,
              previousColor: prev,
              isFirst: level == 0,
            );
            expect(
              RoundGenerator.validate(c, spec, pointer, isFirst: level == 0),
              isEmpty,
              reason: '${l.id} seed $seed level $level',
            );
            dir = spec.pointerDir;
            prev = spec.targetColor;
            pointer = wrapAngle(pointer + 1.3);
          }
        }
      }
    });

    test('a perfect player earns 3 stars on every level, and each lesson '
        'actually shows up', () {
      for (final l in levels) {
        final events = <GameEvent>[];
        final e = GameEngine(config)..onEvent = events.add;
        e.startRun(
          best: 0,
          seed: l.seed,
          mode: RunMode.level,
          config: l.configFrom(config),
          targetRounds: l.targets,
          starGoals: l.goals,
        );
        final seen = <String>{};
        var guard = 0;
        while (e.phase != GamePhase.gameOver && guard++ < 400) {
          tapBestZone(e);
          final spec = e.round?.spec;
          if (spec == null) continue;
          if (spec.kind == RoundKind.inverted) seen.add('inverted');
          if (spec.kind == RoundKind.split) seen.add('split');
          if (spec.kind == RoundKind.boss) seen.add('boss');
          if (spec.ghost) seen.add('ghost');
          if (spec.pulseAmplitude > 0) seen.add('pulse');
          if (spec.ringSpeed != 0) seen.add('rotate');
        }
        expect(e.phase, GamePhase.gameOver, reason: l.id);
        expect(e.completed, isTrue, reason: l.id);
        expect(e.level, l.targets, reason: l.id);
        final done = events.whereType<LevelCompleteEvent>().single.summary;
        expect(done.stars, 3, reason: l.id);
        expect(events.whereType<RunFinishedEvent>(), hasLength(1));
        expect(events.whereType<MissEvent>(), isEmpty, reason: l.id);
        // A chapter's lesson is the first thing it teaches.
        final stage = l.overrides['stages'][0] as Map<String, dynamic>;
        for (final k in ['inverted', 'split', 'ghost', 'pulse', 'rotate']) {
          if ((stage[k] as num) >= 1) {
            expect(seen, contains(k), reason: '${l.id} teaches $k');
          }
        }
        if (l.overrides['boss']['every'] > 0) {
          expect(seen, contains('boss'), reason: l.id);
        }
      }
    });
  });

  group('next goals', () {
    test('the closest goals come first; unapplied runs are projected', () {
      final p = PlayerProfile()
        ..missions = [
          Mission(MissionType.perfects, 50, 60, progress: 40).toJson(),
          Mission(MissionType.runs, 10, 60, progress: 1).toJson(),
          Mission(MissionType.bosses, 1, 60).toJson(),
        ];
      final s = run(score: 90, level: 17, perfects: 8, hits: 17);
      final goals = nextGoals(
        p,
        s,
        config: config,
        best: 100,
        applied: false,
        max: 10,
      );
      for (var i = 1; i < goals.length; i++) {
        expect(goals[i].fraction, lessThanOrEqualTo(goals[i - 1].fraction));
      }
      final texts = goals.map((g) => g.text).toList();
      // 48 / 50 Perfects is closer than 90 / 101 points.
      expect(texts.take(2), [
        'Mission: Hit 50 Perfects',
        '11 more points for a new best',
      ]);
      expect(
        goals.firstWhere((g) => g.text == 'Mission: Hit 50 Perfects').detail,
        '48 / 50',
      );
      expect(texts, contains('3 rounds to Stage 2 · NEON REEF'));
      expect(texts.any((t) => t.startsWith('Player level 2')), isTrue);
      expect(
        nextGoals(p, s, config: config, best: 100, applied: false),
        hasLength(2),
      );
      // Zen and Levels have their own screens.
      expect(
        nextGoals(
          p,
          run(mode: RunMode.zen),
          config: config,
          best: 0,
          applied: true,
        ),
        isEmpty,
      );
    });
  });

  group('modes', () {
    GameEngine engine(List<GameEvent> events) => GameEngine(config)
      ..onEvent = events.add
      ..seen.addAll(intros.keys);

    void miss(GameEngine e) {
      waitUntilPlaying(e);
      final t = e.round!.currentPrimary;
      e.tap(e.time + timeUntil(e, wrapAngle(t.center + tau / 2)));
    }

    test('Zen never ends: a miss just starts a fresh round', () {
      final events = <GameEvent>[];
      final e = engine(events)..startRun(best: 0, mode: RunMode.zen);
      clearRounds(e, 3);
      miss(e);
      expect(events.whereType<ZenMissEvent>(), hasLength(1));
      expect(events.whereType<MissEvent>(), isEmpty);
      expect(e.phase, isNot(GamePhase.dying));
      expect(e.perfectStreak, 0);
      clearRounds(e, 3);
      expect(e.hits, greaterThanOrEqualTo(6));
      expect(events.whereType<RunFinishedEvent>(), isEmpty);
      e.goHome();
      expect(
        events.whereType<RunFinishedEvent>().single.summary.mode,
        RunMode.zen,
      );
    });

    test('Daily and duel runs replay the same seed and never continue', () {
      for (final mode in [RunMode.daily, RunMode.duel]) {
        final e = engine([])
          ..startRun(best: 0, seed: 4242, mode: mode, beatScore: 10);
        final first = e.round!.spec.ballColors.first;
        clearRounds(e, 2);
        miss(e);
        advance(e, 3);
        expect(e.phase, GamePhase.gameOver);
        expect(e.canContinue, isFalse, reason: '$mode');
        e.restart(best: 0);
        expect(e.seed, 4242);
        expect(e.mode, mode);
        expect(e.beatScore, 10);
        expect(e.round!.spec.ballColors.first, first);
      }
    });

    test('Endless can continue; every run is reported exactly once', () {
      final events = <GameEvent>[];
      final e = engine(events)..startRun(best: 0);
      final firstSeed = e.seed;
      clearRounds(e, 2);
      miss(e);
      advance(e, 3);
      expect(e.canContinue, isTrue);
      expect(events.whereType<RunFinishedEvent>(), isEmpty);
      e.restart(best: 0);
      expect(events.whereType<RunFinishedEvent>(), hasLength(1));
      expect(e.seed, isNot(firstSeed), reason: 'endless gets a fresh seed');
      e.finishRun();
      e.finishRun();
      expect(events.whereType<RunFinishedEvent>(), hasLength(2));
    });
  });
}
