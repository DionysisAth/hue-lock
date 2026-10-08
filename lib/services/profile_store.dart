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
  bool haptics = true;
  bool colorblind = false;
  bool adsRemoved = false;

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
    'haptics': haptics,
    'colorblind': colorblind,
    'adsRemoved': adsRemoved,
  };

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
      ..haptics = get('haptics', true)
      ..colorblind = get('colorblind', false)
      ..adsRemoved = get('adsRemoved', false);
  }
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
    notifyListeners();
    _prefs?.setString(_key, jsonEncode(profile.toJson()));
  }
}
