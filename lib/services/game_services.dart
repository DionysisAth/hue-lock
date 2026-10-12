import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart' as gs;

import '../services/profile_store.dart';

/// Google Play Games (Android) and Game Center (iOS): free leaderboards,
/// achievements and cloud save, no server of our own.
///
/// Android: Play Games project 884760255621 (games-ids.xml); the ids below
/// were created with the Play Games Services Publishing API. iOS: enable
/// the Game Center capability in Xcode and create the same ids (the `ios`
/// values) in App Store Connect.
abstract final class GameServiceIds {
  static const configured = true;

  /// Endless best. Play Games and Game Center also keep daily and weekly
  /// views of every leaderboard, which the weekly rank uses.
  static const endlessLeaderboard = (
    android: 'CgkIhbnI_t8ZEAIQAQ',
    ios: 'hue_lock_endless',
  );
  static const dailyLeaderboard = (
    android: 'CgkIhbnI_t8ZEAIQAg',
    ios: 'hue_lock_daily',
  );

  /// Rush mode (one minute).
  static const rushLeaderboard = (
    android: 'CgkIhbnI_t8ZEAIQAw',
    ios: 'hue_lock_rush',
  );

  /// Total stars on the Levels map.
  static const starsLeaderboard = (
    android: 'CgkIhbnI_t8ZEAIQBA',
    ios: 'hue_lock_stars',
  );

  /// Achievement id per local achievement id (see achievementDefs).
  static const achievements = <String, ({String android, String ios})>{
    'first_lock': (android: 'CgkIhbnI_t8ZEAIQBQ', ios: 'hue_lock_first_lock'),
    'score_50': (android: 'CgkIhbnI_t8ZEAIQBg', ios: 'hue_lock_score_50'),
    'score_250': (android: 'CgkIhbnI_t8ZEAIQBw', ios: 'hue_lock_score_250'),
    'score_1000': (android: 'CgkIhbnI_t8ZEAIQCA', ios: 'hue_lock_score_1000'),
    'streak_10': (android: 'CgkIhbnI_t8ZEAIQCQ', ios: 'hue_lock_streak_10'),
    'streak_25': (android: 'CgkIhbnI_t8ZEAIQCg', ios: 'hue_lock_streak_25'),
    'fever_1': (android: 'CgkIhbnI_t8ZEAIQCw', ios: 'hue_lock_fever_1'),
    'combo_5': (android: 'CgkIhbnI_t8ZEAIQDA', ios: 'hue_lock_combo_5'),
    'boss_1': (android: 'CgkIhbnI_t8ZEAIQDQ', ios: 'hue_lock_boss_1'),
    'boss_10': (android: 'CgkIhbnI_t8ZEAIQDg', ios: 'hue_lock_boss_10'),
    'stage_3': (android: 'CgkIhbnI_t8ZEAIQDw', ios: 'hue_lock_stage_3'),
    'stage_6': (android: 'CgkIhbnI_t8ZEAIQEA', ios: 'hue_lock_stage_6'),
    'not_50': (android: 'CgkIhbnI_t8ZEAIQEQ', ios: 'hue_lock_not_50'),
    'greedy_25': (android: 'CgkIhbnI_t8ZEAIQEg', ios: 'hue_lock_greedy_25'),
    'runs_100': (android: 'CgkIhbnI_t8ZEAIQEw', ios: 'hue_lock_runs_100'),
    'daily_7': (android: 'CgkIhbnI_t8ZEAIQFA', ios: 'hue_lock_daily_7'),
    'duel_win': (android: 'CgkIhbnI_t8ZEAIQFQ', ios: 'hue_lock_duel_win'),
    'levels_all': (android: 'CgkIhbnI_t8ZEAIQFg', ios: 'hue_lock_levels_all'),
    'level_10': (android: 'CgkIhbnI_t8ZEAIQFw', ios: 'hue_lock_level_10'),
  };
}

/// Where the player stands on a leaderboard this week, and the player just
/// above (the one to beat next).
class RankInfo {
  const RankInfo({
    required this.rank,
    required this.score,
    this.rivalName,
    this.rivalScore,
  });

  final int rank;
  final int score;
  final String? rivalName;
  final int? rivalScore;
}

class GameServices extends ChangeNotifier {
  GameServices({bool? enabled})
    : enabled =
          enabled ??
          (GameServiceIds.configured &&
              !kIsWeb &&
              (Platform.isAndroid || Platform.isIOS));

  final bool enabled;
  bool signedIn = false;
  String? playerName;

  /// This week's Endless rank (null until loaded, or when unranked).
  RankInfo? weeklyRank;

  /// Last successful cloud save.
  DateTime? lastCloudSave;

  static const _saveName = 'hue_lock_profile';

  Future<void> signIn() async {
    if (!enabled) return;
    try {
      await gs.GamesServices.signIn();
      signedIn = await gs.GamesServices.isSignedIn;
      playerName = signedIn ? await gs.GamesServices.getPlayerName() : null;
    } catch (e) {
      debugPrint('Game services sign-in failed: $e');
      signedIn = false;
    }
    notifyListeners();
  }

  Future<void> submitEndless(int score) async {
    await _submit(
      GameServiceIds.endlessLeaderboard.android,
      GameServiceIds.endlessLeaderboard.ios,
      score,
    );
    await refreshRank();
  }

  Future<void> submitRush(int score) => _submit(
    GameServiceIds.rushLeaderboard.android,
    GameServiceIds.rushLeaderboard.ios,
    score,
  );

  Future<void> submitStars(int stars) => _submit(
    GameServiceIds.starsLeaderboard.android,
    GameServiceIds.starsLeaderboard.ios,
    stars,
  );

  /// Loads this week's Endless rank and the player just above. Network
  /// work happens on the platform side; this is only called between runs.
  Future<void> refreshRank() async {
    if (!signedIn) return;
    const board = GameServiceIds.endlessLeaderboard;
    try {
      final me = await gs.Leaderboards.getPlayerScoreObject(
        androidLeaderboardID: board.android,
        iOSLeaderboardID: board.ios,
        scope: gs.PlayerScope.global,
        timeScope: gs.TimeScope.week,
      );
      if (me == null || me.rank <= 0) return;
      String? rivalName;
      int? rivalScore;
      if (me.rank > 1) {
        final around = await gs.Leaderboards.loadLeaderboardScores(
          androidLeaderboardID: board.android,
          iOSLeaderboardID: board.ios,
          playerCentered: true,
          scope: gs.PlayerScope.global,
          timeScope: gs.TimeScope.week,
          maxResults: 5,
        );
        for (final s in around ?? const <gs.LeaderboardScoreData>[]) {
          if (s.rank == me.rank - 1) {
            rivalName = s.scoreHolder.displayName;
            rivalScore = s.rawScore;
          }
        }
      }
      weeklyRank = RankInfo(
        rank: me.rank,
        score: me.rawScore,
        rivalName: rivalName,
        rivalScore: rivalScore,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Rank lookup failed: $e');
    }
  }

  /// Play Games / Game Center daily leaderboards reset every day, so the
  /// Daily Challenge board only ever compares the same day's seed.
  Future<void> submitDaily(int score) => _submit(
    GameServiceIds.dailyLeaderboard.android,
    GameServiceIds.dailyLeaderboard.ios,
    score,
  );

  Future<void> _submit(String android, String ios, int score) async {
    if (!signedIn || score <= 0) return;
    try {
      await gs.GamesServices.submitScore(
        score: gs.Score(
          androidLeaderboardID: android,
          iOSLeaderboardID: ios,
          value: score,
        ),
      );
    } catch (e) {
      debugPrint('Submit score failed: $e');
    }
  }

  Future<void> unlock(String localId) async {
    final ids = GameServiceIds.achievements[localId];
    if (!signedIn || ids == null) return;
    try {
      await gs.GamesServices.unlock(
        achievement: gs.Achievement(
          androidID: ids.android,
          iOSID: ids.ios,
          percentComplete: 100,
        ),
      );
    } catch (e) {
      debugPrint('Unlock failed: $e');
    }
  }

  Future<void> showLeaderboards() async {
    if (!signedIn) return;
    try {
      await gs.GamesServices.showLeaderboards();
    } catch (e) {
      debugPrint('Show leaderboards failed: $e');
    }
  }

  Future<void> showAchievements() async {
    if (!signedIn) return;
    try {
      await gs.GamesServices.showAchievements();
    } catch (e) {
      debugPrint('Show achievements failed: $e');
    }
  }

  /// Cloud save (Play Games Saved Games / iCloud through Game Center).
  Future<void> saveProfile(PlayerProfile p) async {
    if (!signedIn) return;
    try {
      await gs.GamesServices.saveGame(
        data: jsonEncode(p.toJson()),
        name: _saveName,
      );
      lastCloudSave = DateTime.now();
      notifyListeners();
    } catch (e) {
      debugPrint('Cloud save failed: $e');
    }
  }

  Future<PlayerProfile?> loadProfile() async {
    if (!signedIn) return null;
    try {
      final data = await gs.GamesServices.loadGame(name: _saveName);
      if (data == null || data.isEmpty) return null;
      return PlayerProfile.fromJson(jsonDecode(data) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Cloud load failed: $e');
      return null;
    }
  }
}
