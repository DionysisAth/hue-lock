import 'dart:math' as math;

import '../core/seeded_random.dart';

/// Visual-only "juice" state. Positions are in ring units: the ring center is
/// (0, 0) and the ring radius is 1. Uses its own RNG so effects never disturb
/// the deterministic round sequence.
class Particle {
  Particle(this.x, this.y, this.vx, this.vy, this.life, this.color, this.size);

  double x, y, vx, vy;
  double age = 0;
  final double life;
  final int color;
  final double size;

  double get t => (age / life).clamp(0.0, 1.0);
}

class FloatingText {
  FloatingText(this.text, this.color, {this.life = 0.7, this.big = false});

  final String text;

  /// Palette index, or -1 for the theme text color.
  final int color;
  final double life;
  final bool big;
  double age = 0;

  double get t => (age / life).clamp(0.0, 1.0);
}

/// A zone that just got locked; drawn as a bright arc that fades out.
class LockFlash {
  LockFlash(this.angle, this.width, this.color, {this.perfect = false});

  final double angle;
  final double width;
  final int color;
  final bool perfect;
  double age = 0;
  static const life = 0.35;

  double get t => (age / life).clamp(0.0, 1.0);
}

class Effects {
  final _rng = SeededRandom(0x5eed);
  final particles = <Particle>[];
  final texts = <FloatingText>[];
  final locks = <LockFlash>[];

  /// 1 right after a Perfect, decays to 0.
  double perfectFlash = 0;

  /// 1 right after any hit, decays to 0 (ball "lock" pulse).
  double hitPulse = 0;

  /// Screen shake strength, decays to 0.
  double shake = 0;

  /// Smoothed background glow, chases [glowTarget].
  double glow = 0;
  double glowTarget = 0;

  void clear() {
    particles.clear();
    texts.clear();
    locks.clear();
    perfectFlash = 0;
    hitPulse = 0;
    shake = 0;
  }

  void burst(double angle, int color, {int count = 14, double power = 1}) {
    final px = math.sin(angle), py = -math.cos(angle);
    for (var i = 0; i < count; i++) {
      final a = _rng.range(0, math.pi * 2);
      final s = _rng.range(0.25, 1.1) * power;
      particles.add(
        Particle(
          px,
          py,
          math.cos(a) * s,
          math.sin(a) * s,
          _rng.range(0.35, 0.7),
          color,
          _rng.range(0.012, 0.03),
        ),
      );
    }
  }

  void update(double dt) {
    for (final p in particles) {
      p.age += dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= math.pow(0.04, dt).toDouble();
      p.vy *= math.pow(0.04, dt).toDouble();
    }
    particles.removeWhere((p) => p.age >= p.life);
    for (final t in texts) {
      t.age += dt;
    }
    texts.removeWhere((t) => t.age >= t.life);
    for (final l in locks) {
      l.age += dt;
    }
    locks.removeWhere((l) => l.age >= LockFlash.life);
    perfectFlash = math.max(0, perfectFlash - dt * 3.5);
    hitPulse = math.max(0, hitPulse - dt * 5);
    shake = math.max(0, shake - dt * 4);
    glow += (glowTarget - glow) * math.min(1, dt * 4);
  }
}
