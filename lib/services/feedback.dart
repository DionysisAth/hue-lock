import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum Sfx {
  hit,
  fail,
  coin,
  newBest,
  ui,
  powerUp,
  shield,
  stage,
  boss,
  fever,
  comboUp,
  comboLost,
  streak,
}

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
    'powerUp': 'audio/power_up.wav',
    'shield': 'audio/shield.wav',
    'stage': 'audio/stage.wav',
    'boss': 'audio/boss.wav',
    'fever': 'audio/fever.wav',
    'comboUp': 'audio/combo_up.wav',
    'comboLost': 'audio/combo_lost.wav',
    'streak': 'audio/streak.wav',
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
  _SfxPool(this._players) : _volumes = List.filled(_players.length, -1);

  final List<AudioPlayer> _players;

  /// Last volume sent to each player. Every platform call runs on the same
  /// thread as the UI on Android, so unchanged volumes are not re-sent.
  final List<double> _volumes;
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
    final i = _next;
    final p = _players[i];
    _next = (_next + 1) % _players.length;
    await p.stop();
    if (_volumes[i] != volume) {
      _volumes[i] = volume;
      await p.setVolume(volume);
    }
    await p.resume();
  }
}

/// Adaptive background music: four stacked intensities of the same loop
/// (see tool/generate_music.py). Each intensity has its own player, loaded
/// once at startup, so a change is a seek and a short crossfade rather than
/// a file load: every platform call runs on the UI thread on Android.
/// Changes are spaced at least [minGap] apart so a flickering combo can't
/// thrash the players; [cut] silences at once (on death).
class MusicService {
  MusicService({this.enabled = true});

  /// False in tests / unsupported platforms: every call becomes a no-op.
  final bool enabled;
  static const levels = 4;
  static const minGap = Duration(milliseconds: 1500);

  bool _muted = false;
  double _volume = 0.6;
  double _tempo = 1;

  /// The intensity playing now, and the one asked for (they differ while a
  /// change waits for [minGap]).
  int _intensity = 0;
  int _wanted = 0;
  int _generation = 0;
  bool _suspended = false;

  /// Player i plays intensity i + 1.
  final _players = <AudioPlayer>[];
  final _rates = <double>[];
  Timer? _fade;
  Timer? _pending;
  final _sinceSwitch = Stopwatch();

  int get intensity => _wanted;

  bool get muted => _muted;

  /// Settings are re-applied on every profile save; only real changes reach
  /// the player.
  set muted(bool m) {
    if (m == _muted) return;
    _muted = m;
    _applyVolume();
  }

  set volume(double v) {
    if (v == _volume) return;
    _volume = v;
    _applyVolume();
  }

  void _applyVolume() {
    if (_intensity > 0 && _players.isNotEmpty && _fade == null) {
      _players[_intensity - 1].setVolume(_effectiveVolume).ignore();
    }
  }

  double get _effectiveVolume => _muted ? 0 : _volume;

  Future<void> init() async {
    if (!enabled) return;
    try {
      for (var i = 1; i <= levels; i++) {
        // No position polling: we only read the position when switching.
        final p = AudioPlayer()..positionUpdater = null;
        await p.setReleaseMode(ReleaseMode.loop);
        await p.setSource(AssetSource('audio/music_$i.wav'));
        _players.add(p);
        _rates.add(1);
      }
      if (_wanted > 0) await _apply(_wanted);
    } catch (e) {
      debugPrint('Music unavailable: $e');
      _players.clear();
    }
  }

  /// 0 = silent, 1..[levels] = quiet pad .. full Fever mix.
  Future<void> setIntensity(int level) async {
    level = level.clamp(0, levels);
    _wanted = level;
    if (!enabled || _players.isEmpty) return;
    if (level == _intensity) {
      _pending?.cancel();
      _pending = null;
      return;
    }
    final wait = minGap - _sinceSwitch.elapsed;
    if (level > 0 && _intensity > 0 && wait > Duration.zero) {
      _pending ??= Timer(wait, () {
        _pending = null;
        setIntensity(_wanted);
      });
      return;
    }
    _pending?.cancel();
    _pending = null;
    await _apply(level);
  }

  Future<void> _apply(int level) async {
    final gen = ++_generation;
    final old = _intensity;
    _intensity = level;
    _sinceSwitch
      ..reset()
      ..start();
    try {
      if (level == 0) {
        _fade?.cancel();
        _fade = null;
        for (final p in _players) {
          if (p.state == PlayerState.playing) await p.pause();
        }
        return;
      }
      final to = _players[level - 1];
      final from = old > 0 ? _players[old - 1] : null;
      final playing = from != null && from.state == PlayerState.playing;
      final position = playing ? await from.getCurrentPosition() : null;
      if (_rates[level - 1] != _tempo) {
        _rates[level - 1] = _tempo;
        await to.setPlaybackRate(_tempo);
      }
      await to.setVolume(playing ? 0 : _effectiveVolume);
      if (position != null) await to.seek(position);
      if (gen != _generation || _suspended) return;
      await to.resume();
      if (playing) _crossfade(from, to, gen);
    } catch (e) {
      debugPrint('Music switch failed: $e');
    }
  }

  void _crossfade(AudioPlayer from, AudioPlayer to, int gen) {
    _fade?.cancel();
    var step = 0;
    const steps = 6;
    _fade = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (gen != _generation) {
        timer.cancel();
        // A newer switch took over: make sure this one isn't left playing.
        if (_intensity == 0 || from != _players[_intensity - 1]) {
          from.pause().ignore();
        }
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
    final i = _intensity - 1;
    if (_rates[i] == rate) return;
    _rates[i] = rate;
    try {
      await _players[i].setPlaybackRate(rate);
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
      final p = _players[_intensity - 1];
      await p.setVolume(_effectiveVolume);
      await p.resume();
    }
  }
}

/// Vibration feedback, toggleable in settings.
class HapticsService {
  bool enabled = true;

  void hit() => _run(HapticFeedback.lightImpact);

  /// A Perfect is a double "tick-tock": medium, then a light echo.
  void perfect() {
    _run(HapticFeedback.mediumImpact);
    if (enabled) {
      Future<void>.delayed(
        const Duration(milliseconds: 55),
        HapticFeedback.lightImpact,
      );
    }
  }

  void celebrate() {
    _run(HapticFeedback.heavyImpact);
    if (enabled) {
      Future<void>.delayed(
        const Duration(milliseconds: 90),
        HapticFeedback.mediumImpact,
      );
    }
  }

  void fail() => _run(HapticFeedback.heavyImpact);
  void tick() => _run(HapticFeedback.selectionClick);

  void _run(Future<void> Function() f) {
    if (enabled) f();
  }
}
