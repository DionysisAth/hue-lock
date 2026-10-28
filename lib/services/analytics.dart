import 'dart:convert';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Analytics sink: on-device aggregates ([LocalAnalytics]), plus Firebase
/// Analytics on Android ([FirebaseEventsAnalytics]).
abstract class Analytics {
  void log(String event, [Map<String, Object?> params = const {}]);
}

class NoAnalytics implements Analytics {
  @override
  void log(String event, [Map<String, Object?> params = const {}]) {}
}

/// Local aggregates that answer the MVP's key questions (design doc 15/17):
/// runs per session, where players die (score distribution), continue usage,
/// ads watched and purchases.
class LocalAnalytics implements Analytics {
  LocalAnalytics(this._prefs) : data = _read(_prefs) {
    _bump('sessions');
  }

  static const _key = 'hue_lock.analytics.v1';
  final SharedPreferences _prefs;
  final Map<String, dynamic> data;

  static Future<LocalAnalytics> load() async =>
      LocalAnalytics(await SharedPreferences.getInstance());

  static Map<String, dynamic> _read(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_key);
      if (raw != null) return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {}
    return {};
  }

  void _bump(String counter, [String? bucket]) {
    final counters = (data['counters'] ??= <String, dynamic>{}) as Map;
    final key = bucket == null ? counter : '$counter:$bucket';
    counters[key] = ((counters[key] as num?) ?? 0) + 1;
  }

  @override
  void log(String event, [Map<String, Object?> params = const {}]) {
    if (kDebugMode) debugPrint('[analytics] $event $params');
    _bump('event', event);
    // Runs per session = event:run_start / sessions.
    if (event == 'run_end') {
      final score = (params['score'] as int?) ?? 0;
      // Score distribution in buckets of 10: where do players die?
      _bump('death_score', '${score ~/ 10 * 10}');
      _bump('death_stage', '${params['stage']}');
      if (params['near_miss'] == true) _bump('near_miss');
    }
    _prefs.setString(_key, jsonEncode(data));
  }
}

/// Sends every event to Firebase Analytics as well as to [inner].
class FirebaseEventsAnalytics implements Analytics {
  FirebaseEventsAnalytics(this.inner, this._firebase);

  final Analytics inner;
  final FirebaseAnalytics _firebase;

  /// Our names that clash with events Firebase reserves or reads specially.
  static const _renamed = {'purchase': 'store_purchase'};

  @override
  void log(String event, [Map<String, Object?> params = const {}]) {
    inner.log(event, params);
    final name = _renamed[event] ?? event;
    // Firebase takes strings and numbers only (strings up to 100 chars).
    final clean = <String, Object>{
      for (final e in params.entries)
        if (e.value case final num v)
          e.key: v
        else if (e.value case final bool v)
          e.key: v ? 1 : 0
        else if (e.value != null)
          e.key: '${e.value}'.length > 100
              ? '${e.value}'.substring(0, 100)
              : '${e.value}',
    };
    _firebase.logEvent(name: name, parameters: clean).catchError((Object e) {
      debugPrint('Firebase event failed: $e');
    });
  }
}
