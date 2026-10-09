import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart' as gs;

import '../services/profile_store.dart';

/// Google Play Games (Android) and Game Center (iOS): free leaderboards,
/// achievements and cloud save, no server of our own.
///
/// Disabled until the game is set up in Play Console / App Store Connect.
/// To enable:
/// 1. Android: put the Play Games project id in
///    android/app/src/main/res/values/games-ids.xml.
/// 2. iOS: enable the Game Center capability in Xcode.
/// 3. Fill in the ids below and set [configured] to true.
abstract final class GameServiceIds {
  static const configured = false;

  static const endlessLeaderboard = (android: '', ios: 'hue_lock_endless');
  static const dailyLeaderboard = (android: '', ios: 'hue_lock_daily');

  /// Achievement id per local achievement id (see achievementDefs).
  static const achievements = <String, ({String android, String ios})>{};
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

  Future<void> submitEndless(int score) => _submit(
    GameServiceIds.endlessLeaderboard.android,
    GameServiceIds.endlessLeaderboard.ios,
    score,
  );

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
