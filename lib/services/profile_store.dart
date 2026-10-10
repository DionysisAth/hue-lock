import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything that persists between sessions.
class PlayerProfile {
  PlayerProfile();

  int bestScore = 0;
  int coins = 0;
  int totalRuns = 0;
  int runsSinceInterstitial = 0;
  Set<String> ownedBalls = {'classic'};
  Set<String> ownedThemes = {'classic'};
  String ball = 'classic';
  String theme = 'classic';
  bool sound = true;
  double volume = 0.8;
  bool music = true;
  double musicVolume = 0.6;
  bool haptics = true;
  bool colorblind = false;
  bool adsRemoved = false;

  /// Mechanics already explained to this player (see `intros`).
  Set<String> seenIntros = {};

  // Progression.
  int xp = 0;

  /// Player levels whose rewards were already given.
  int rewardedLevel = 1;
  List<Map<String, dynamic>> missions = [];
  int missionSerial = 0;
  Set<String> achievements = {};

  /// Lifetime counters (runs, perfects, bosses, ...), see `Stat`.
  Map<String, int> stats = {};

  // Daily login reward.
  String lastRewardDay = '';
  int rewardStreak = 0;

  // Daily Challenge (day key is the Play Games leaderboard day).
  String dailyDay = '';
  int dailyAttempts = 0;
  int dailyExtraAttempts = 0;
  int dailyBest = 0;

  /// Levels mode: stars per level id (count of [levelGoals] bits).
  Map<String, int> levelStars = {};

  /// Levels mode: star goals met per level id (bit 0 = cleared).
  Map<String, int> levelGoals = {};

  /// Chapter rewards already given ("C2", and "C2*" for all its stars).
  Set<String> chapterRewards = {};

  /// Continue tokens (from rewards and packs).
  int tokens = 0;
  bool starterPack = false;
  bool dailyReminder = false;

  /// Last local change (milliseconds); used to merge with a cloud save.
  int updatedAt = 0;

  Map<String, dynamic> toJson() => {
    'bestScore': bestScore,
    'coins': coins,
    'totalRuns': totalRuns,
    'runsSinceInterstitial': runsSinceInterstitial,
    'ownedBalls': ownedBalls.toList(),
    'ownedThemes': ownedThemes.toList(),
    'ball': ball,
    'theme': theme,
    'sound': sound,
    'volume': volume,
    'music': music,
    'musicVolume': musicVolume,
    'haptics': haptics,
    'colorblind': colorblind,
    'adsRemoved': adsRemoved,
    'seenIntros': seenIntros.toList(),
    'xp': xp,
    'rewardedLevel': rewardedLevel,
    'missions': missions,
    'missionSerial': missionSerial,
    'achievements': achievements.toList(),
    'stats': stats,
    'lastRewardDay': lastRewardDay,
    'rewardStreak': rewardStreak,
    'dailyDay': dailyDay,
    'dailyAttempts': dailyAttempts,
    'dailyExtraAttempts': dailyExtraAttempts,
    'dailyBest': dailyBest,
    'levelStars': levelStars,
    'levelGoals': levelGoals,
    'chapterRewards': chapterRewards.toList(),
    'tokens': tokens,
    'starterPack': starterPack,
    'dailyReminder': dailyReminder,
    'updatedAt': updatedAt,
  };

  int stat(String key) => stats[key] ?? 0;
  void addStat(String key, int by) => stats[key] = stat(key) + by;
  void maxStat(String key, int value) {
    if (value > stat(key)) stats[key] = value;
  }

  /// Combines a cloud save with this one without losing progress on either
  /// device: the further-along save wins for counters, owned things are
  /// unioned and records keep their best.
  void mergeFrom(PlayerProfile other) {
    final otherAhead = other.xp > xp;
    if (otherAhead) {
      xp = other.xp;
      rewardedLevel = other.rewardedLevel;
      coins = other.coins;
      tokens = other.tokens;
      missions = other.missions;
      missionSerial = other.missionSerial;
      lastRewardDay = other.lastRewardDay;
      rewardStreak = other.rewardStreak;
    }
    bestScore = bestScore > other.bestScore ? bestScore : other.bestScore;
    totalRuns = totalRuns > other.totalRuns ? totalRuns : other.totalRuns;
    ownedBalls.addAll(other.ownedBalls);
    ownedThemes.addAll(other.ownedThemes);
    achievements.addAll(other.achievements);
    seenIntros.addAll(other.seenIntros);
    adsRemoved = adsRemoved || other.adsRemoved;
    starterPack = starterPack || other.starterPack;
    other.stats.forEach((k, v) {
      if (v > stat(k)) stats[k] = v;
    });
    other.levelStars.forEach((k, v) {
      if (v > (levelStars[k] ?? 0)) levelStars[k] = v;
    });
    other.levelGoals.forEach((k, v) {
      final merged = (levelGoals[k] ?? 0) | v;
      levelGoals[k] = merged;
      final stars = merged.toRadixString(2).replaceAll('0', '').length;
      if (stars > (levelStars[k] ?? 0)) levelStars[k] = stars;
    });
    chapterRewards.addAll(other.chapterRewards);
    if (other.dailyDay == dailyDay && other.dailyBest > dailyBest) {
      dailyBest = other.dailyBest;
    }
  }

  factory PlayerProfile.fromJson(Map<String, dynamic> j) {
    T get<T>(String k, T fallback) => j[k] is T ? j[k] as T : fallback;
    Set<String> set(String k) => {
      'classic',
      ...((j[k] as List?) ?? const []).whereType<String>(),
    };
    return PlayerProfile()
      ..bestScore = get('bestScore', 0)
      ..coins = get('coins', 0)
      ..totalRuns = get('totalRuns', 0)
      ..runsSinceInterstitial = get('runsSinceInterstitial', 0)
      ..ownedBalls = set('ownedBalls')
      ..ownedThemes = set('ownedThemes')
      ..ball = get('ball', 'classic')
      ..theme = get('theme', 'classic')
      ..sound = get('sound', true)
      ..volume = (j['volume'] as num?)?.toDouble() ?? 0.8
      ..music = get('music', true)
      ..musicVolume = (j['musicVolume'] as num?)?.toDouble() ?? 0.6
      ..haptics = get('haptics', true)
      ..colorblind = get('colorblind', false)
      ..adsRemoved = get('adsRemoved', false)
      ..seenIntros = {
        ...((j['seenIntros'] as List?) ?? const []).whereType<String>(),
      }
      ..xp = get('xp', 0)
      ..rewardedLevel = get('rewardedLevel', 1)
      ..missions = [
        for (final m in (j['missions'] as List?) ?? const [])
          if (m is Map) Map<String, dynamic>.from(m),
      ]
      ..missionSerial = get('missionSerial', 0)
      ..achievements = {
        ...((j['achievements'] as List?) ?? const []).whereType<String>(),
      }
      ..stats = _intMap(j['stats'])
      ..lastRewardDay = get('lastRewardDay', '')
      ..rewardStreak = get('rewardStreak', 0)
      ..dailyDay = get('dailyDay', '')
      ..dailyAttempts = get('dailyAttempts', 0)
      ..dailyExtraAttempts = get('dailyExtraAttempts', 0)
      ..dailyBest = get('dailyBest', 0)
      ..levelStars = _intMap(j['levelStars'])
      ..levelGoals = _intMap(j['levelGoals'])
      ..chapterRewards = {
        ...((j['chapterRewards'] as List?) ?? const []).whereType<String>(),
      }
      ..tokens = get('tokens', 0)
      ..starterPack = get('starterPack', false)
      ..dailyReminder = get('dailyReminder', false)
      ..updatedAt = get('updatedAt', 0);
  }

  static Map<String, int> _intMap(Object? raw) => {
    if (raw is Map)
      for (final e in raw.entries)
        if (e.key is String && e.value is num)
          e.key as String: (e.value as num).toInt(),
  };
}

/// Local save. Cloud save can be layered on top by syncing [PlayerProfile]
/// JSON (design doc 14.3).
class ProfileStore extends ChangeNotifier {
  ProfileStore(SharedPreferences prefs)
    : _prefs = prefs,
      profile = _read(prefs);

  /// In-memory store for tests.
  ProfileStore.memory([PlayerProfile? profile])
    : _prefs = null,
      profile = profile ?? PlayerProfile();

  static const _key = 'hue_lock.profile.v1';

  final SharedPreferences? _prefs;
  final PlayerProfile profile;

  static Future<ProfileStore> load() async =>
      ProfileStore(await SharedPreferences.getInstance());

  static PlayerProfile _read(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null) return PlayerProfile();
    try {
      return PlayerProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Corrupt save, starting fresh: $e');
      return PlayerProfile();
    }
  }

  /// Applies [change], notifies listeners and persists.
  void update(void Function(PlayerProfile p) change) {
    change(profile);
    profile.updatedAt = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    _prefs?.setString(_key, jsonEncode(profile.toJson()));
  }
}
