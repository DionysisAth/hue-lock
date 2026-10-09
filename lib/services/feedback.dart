import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum Sfx { hit, fail, coin, newBest, ui, fever, powerUp, shield, stage, boss }

/// Sound effects. Pools are preloaded at startup so a tap never waits on
/// file I/O. Consecutive Perfects play a rising scale.
class AudioService {
  AudioService({this.enabled = true});

  /// False in tests / unsupported platforms: every call becomes a no-op.
  final bool enabled;

  static const perfectNotes = 8;
  final _pools = <String, _SfxPool>{};
  bool muted = false;
  double volume = 0.8;

  static const _files = {
    'hit': 'audio/hit.wav',
    'fail': 'audio/fail.wav',
    'coin': 'audio/coin.wav',
    'newBest': 'audio/new_best.wav',
    'ui': 'audio/ui.wav',
    'fever': 'audio/fever.wav',
    'powerUp': 'audio/power_up.wav',
    'shield': 'audio/shield.wav',
    'stage': 'audio/stage.wav',
    'boss': 'audio/boss.wav',
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
          _pools[e.key] = await _SfxPool.load(e.value, voices: 3);
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
    _pools[key]?.play(volume).catchError((Object e) {
      debugPrint('Sfx $key failed: $e');
    });
  }
}

/// A few preloaded players per sound, used round-robin so overlapping hits
/// never cut each other off.
///
/// audioplayers' own AudioPool gives every player a per-frame position
/// updater; in low-latency mode the "completed" event never arrives, so those
/// updaters would poll the platform every frame forever. We never need the
/// playback position, so it is switched off.
class _SfxPool {
  _SfxPool(this._players);

  final List<AudioPlayer> _players;
  int _next = 0;

  static Future<_SfxPool> load(String asset, {required int voices}) async {
    final players = <AudioPlayer>[];
    for (var i = 0; i < voices; i++) {
      final p = AudioPlayer()..positionUpdater = null;
      await p.setPlayerMode(PlayerMode.lowLatency);
      await p.setReleaseMode(ReleaseMode.stop);
      await p.setSource(AssetSource(asset));
      players.add(p);
    }
    return _SfxPool(players);
  }

  Future<void> play(double volume) async {
    final p = _players[_next];
    _next = (_next + 1) % _players.length;
    await p.stop();
    await p.setVolume(volume);
    await p.resume();
  }
}

/// Adaptive background music: four stacked intensities of the same loop
/// (see tool/generate_music.py). Changing intensity crossfades to the other
/// track at the same position; [cut] silences it at once (on death).
class MusicService {
  MusicService({this.enabled = true});

  /// False in tests / unsupported platforms: every call becomes a no-op.
  final bool enabled;
  static const levels = 4;

  bool muted = false;
  double _volume = 0.6;
  double _tempo = 1;
  int _intensity = 0;
  int _generation = 0;
  bool _suspended = false;
  final _players = <AudioPlayer>[];
  int _active = 0;
  Timer? _fade;

  int get intensity => _intensity;

  set volume(double v) {
    _volume = v;
    if (_players.isNotEmpty && _fade == null) {
      _players[_active].setVolume(_effectiveVolume).ignore();
    }
  }

  double get _effectiveVolume => muted ? 0 : _volume;

  Future<void> init() async {
    if (!enabled) return;
    try {
      for (var i = 0; i < 2; i++) {
        // No position polling: we only read the position when switching.
        final p = AudioPlayer()..positionUpdater = null;
        await p.setReleaseMode(ReleaseMode.loop);
        _players.add(p);
      }
      final want = _intensity;
      _intensity = 0;
      if (want > 0) await setIntensity(want);
    } catch (e) {
      debugPrint('Music unavailable: $e');
    }
  }

  /// 0 = silent, 1..[levels] = quiet pad .. full Fever mix.
  Future<void> setIntensity(int level) async {
    level = level.clamp(0, levels);
    if (level == _intensity) return;
    _intensity = level;
    if (!enabled || _players.isEmpty) return;
    final gen = ++_generation;
    try {
      if (level == 0) {
        _fade?.cancel();
        _fade = null;
        for (final p in _players) {
          await p.pause();
        }
        return;
      }
      final from = _players[_active];
      final to = _players[1 - _active];
      final playing = from.state == PlayerState.playing;
      final position = playing ? await from.getCurrentPosition() : null;
      await to.setSource(AssetSource('audio/music_$level.wav'));
      await to.setPlaybackRate(_tempo);
      await to.setVolume(playing ? 0 : _effectiveVolume);
      if (position != null) await to.seek(position);
      if (gen != _generation) return;
      if (_suspended) return;
      await to.resume();
      _active = 1 - _active;
      if (playing) _crossfade(from, to, gen);
    } catch (e) {
      debugPrint('Music switch failed: $e');
    }
  }

  void _crossfade(AudioPlayer from, AudioPlayer to, int gen) {
    _fade?.cancel();
    var step = 0;
    const steps = 8;
    _fade = Timer.periodic(const Duration(milliseconds: 35), (timer) {
      if (gen != _generation) {
        timer.cancel();
        return;
      }
      step++;
      final k = step / steps;
      to.setVolume(_effectiveVolume * k).ignore();
      from.setVolume(_effectiveVolume * (1 - k)).ignore();
      if (step >= steps) {
        timer.cancel();
        _fade = null;
        from.pause().ignore();
      }
    });
  }

  /// Silences the music immediately (the run just ended).
  Future<void> cut() => setIntensity(0);

  /// Tempo rises a little with every stage.
  Future<void> setTempo(double rate) async {
    _tempo = rate;
    if (!enabled || _players.isEmpty || _intensity == 0) return;
    try {
      await _players[_active].setPlaybackRate(rate);
    } catch (e) {
      debugPrint('Music tempo failed: $e');
    }
  }

  /// App went to the background / came back.
  Future<void> suspend() async {
    _suspended = true;
    for (final p in _players) {
      await p.pause();
    }
  }

  Future<void> resume() async {
    _suspended = false;
    if (_intensity > 0 && _players.isNotEmpty) {
      await _players[_active].setVolume(_effectiveVolume);
      await _players[_active].resume();
    }
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
