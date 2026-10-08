import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum Sfx { hit, fail, coin, newBest, ui }

/// Sound effects. Pools are preloaded at startup so a tap never waits on
/// file I/O. Consecutive Perfects play a rising scale.
class AudioService {
  AudioService({this.enabled = true});

  /// False in tests / unsupported platforms: every call becomes a no-op.
  final bool enabled;

  static const perfectNotes = 8;
  final _pools = <String, AudioPool>{};
  bool muted = false;
  double volume = 0.8;

  static const _files = {
    'hit': 'audio/hit.wav',
    'fail': 'audio/fail.wav',
    'coin': 'audio/coin.wav',
    'newBest': 'audio/new_best.wav',
    'ui': 'audio/ui.wav',
  };

  Future<void> init() async {
    if (!enabled) return;
    try {
      // Mix with the player's own music instead of stopping it.
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
            .build(),
      );
      final entries = <String, String>{
        ..._files,
        for (var i = 0; i < perfectNotes; i++)
          'perfect$i': 'audio/perfect_$i.wav',
      };
      await Future.wait(
        entries.entries.map((e) async {
          _pools[e.key] = await AudioPool.createFromAsset(
            path: e.value,
            maxPlayers: 3,
            playerMode: PlayerMode.lowLatency,
          );
        }),
      );
    } catch (e) {
      debugPrint('Audio unavailable: $e');
    }
  }

  void play(Sfx sfx) => _play(sfx.name);

  /// [streak] = consecutive Perfects so far (1 = first).
  void playPerfect(int streak) =>
      _play('perfect${math.min(perfectNotes - 1, math.max(0, streak - 1))}');

  void _play(String key) {
    if (!enabled || muted || volume <= 0) return;
    final pool = _pools[key];
    if (pool == null) return;
    pool.start(volume: volume).catchError((Object e) {
      debugPrint('Sfx $key failed: $e');
      return () async {};
    });
  }
}

/// Vibration feedback, toggleable in settings.
class HapticsService {
  bool enabled = true;

  void hit() => _run(HapticFeedback.lightImpact);
  void perfect() => _run(HapticFeedback.mediumImpact);
  void fail() => _run(HapticFeedback.heavyImpact);
  void tick() => _run(HapticFeedback.selectionClick);

  void _run(Future<void> Function() f) {
    if (enabled) f();
  }
}
