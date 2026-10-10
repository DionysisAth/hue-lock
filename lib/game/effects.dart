import 'dart:math' as math;

import '../core/seeded_random.dart';

/// Visual-only "juice" state. Positions are in ring units: the ring center is
/// (0, 0) and the ring radius is 1. Uses its own RNG so effects never disturb
/// the deterministic round sequence.
enum ParticleShape { dot, shard, star, confetti }

class Particle {
  Particle(
    this.x,
    this.y,
    this.vx,
    this.vy,
    this.life,
    this.color,
    this.size, {
    this.shape = ParticleShape.dot,
    this.rotation = 0,
    this.spin = 0,
    this.gravity = 0,
    this.drag = 0.04,
  });

  double x, y, vx, vy;
  double age = 0;
  final double life;

  /// Palette index, or -1 for white.
  final int color;
  final double size;
  final ParticleShape shape;
  double rotation;
  final double spin;
  final double gravity;
  final double drag;

  double get t => (age / life).clamp(0.0, 1.0);
}

class FloatingText {
  FloatingText(
    this.text,
    this.color, {
    this.life = 0.7,
    this.big = false,
    this.huge = false,
  });

  final String text;

  /// Palette index, or -1 for the theme text color.
  final int color;
  final double life;
  final bool big;

  /// Streak words ("INSANE!"): biggest, with an elastic pop.
  final bool huge;
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

/// An expanding ring of light (Perfect hits, combo ups).
class Shockwave {
  Shockwave(
    this.x,
    this.y,
    this.color, {
    this.maxRadius = 0.6,
    this.life = 0.45,
    this.width = 0.05,
  });

  /// Center in ring units.
  final double x, y;

  /// Palette index, or -1 for white.
  final int color;
  final double maxRadius;
  final double life;
  final double width;
  double age = 0;

  double get t => (age / life).clamp(0.0, 1.0);
}

/// Big centered announcement ("STAGE 2", "BOSS ROUND").
class Announcement {
  Announcement(this.title, {this.subtitle, this.color = -1, this.life = 1.6});

  final String title;
  final String? subtitle;

  /// Palette index, or -1 for the theme text color.
  final int color;
  final double life;
  double age = 0;

  double get t => (age / life).clamp(0.0, 1.0);
}

class Effects {
  final _rng = SeededRandom(0x5eed);
  final particles = <Particle>[];
  final texts = <FloatingText>[];
  final locks = <LockFlash>[];
  final waves = <Shockwave>[];
  Announcement? banner;

  /// 1 right after a shield absorbs a miss, decays to 0.
  double shieldFlash = 0;

  /// 1 right after a Perfect, decays to 0.
  double perfectFlash = 0;

  /// 1 right after any hit, decays to 0 (ball "lock" pulse).
  double hitPulse = 0;

  /// Ring "breathes" outward on a hit.
  double ringPulse = 0;

  /// Camera punch-in on Perfect hits.
  double zoom = 0;

  /// Screen-edge glow in [edgeColor] on Perfect hits.
  double edgeFlash = 0;
  int edgeColor = 0;

  /// Ball color morph: from [ballFrom] to the new color while > 0.
  double ballMorph = 0;
  int ballFrom = 0;

  /// Screen shake strength, decays to 0.
  double shake = 0;

  /// Smoothed background glow, chases [glowTarget].
  double glow = 0;
  double glowTarget = 0;

  void clear() {
    particles.clear();
    texts.clear();
    locks.clear();
    waves.clear();
    banner = null;
    shieldFlash = 0;
    perfectFlash = 0;
    hitPulse = 0;
    ringPulse = 0;
    zoom = 0;
    edgeFlash = 0;
    ballMorph = 0;
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

  /// The hit zone shatters: shards spread along the arc and fly outward.
  void shatter(double centerAngle, double width, int color, {int count = 18}) {
    for (var i = 0; i < count; i++) {
      final a = centerAngle + _rng.range(-0.5, 0.5) * width;
      final r = _rng.range(0.93, 1.07);
      final px = math.sin(a) * r, py = -math.cos(a) * r;
      final out = _rng.range(0.5, 1.6);
      final side = _rng.range(-0.5, 0.5);
      particles.add(
        Particle(
          px,
          py,
          math.sin(a) * out + math.cos(a) * side,
          -math.cos(a) * out + math.sin(a) * side,
          _rng.range(0.45, 0.8),
          color,
          _rng.range(0.025, 0.05),
          shape: ParticleShape.shard,
          rotation: _rng.range(0, math.pi),
          spin: _rng.range(-14, 14),
          drag: 0.08,
        ),
      );
    }
  }

  /// Little white stars that twinkle out from a point.
  void sparkle(double angle, {int count = 8, double radius = 1}) {
    final px = math.sin(angle) * radius, py = -math.cos(angle) * radius;
    for (var i = 0; i < count; i++) {
      final a = _rng.range(0, math.pi * 2);
      final s = _rng.range(0.3, 0.9);
      particles.add(
        Particle(
          px,
          py,
          math.cos(a) * s,
          math.sin(a) * s,
          _rng.range(0.4, 0.75),
          -1,
          _rng.range(0.025, 0.045),
          shape: ParticleShape.star,
          rotation: _rng.range(0, math.pi),
          spin: _rng.range(-6, 6),
        ),
      );
    }
  }

  /// Celebration rain from the top of the screen (new best, boss cleared).
  void confetti({int count = 70}) {
    for (var i = 0; i < count; i++) {
      particles.add(
        Particle(
          _rng.range(-1.6, 1.6),
          _rng.range(-2.4, -1.6),
          _rng.range(-0.4, 0.4),
          _rng.range(0.2, 0.9),
          _rng.range(1.4, 2.2),
          _rng.nextInt(4),
          _rng.range(0.025, 0.045),
          shape: ParticleShape.confetti,
          rotation: _rng.range(0, math.pi),
          spin: _rng.range(-9, 9),
          gravity: 0.9,
          drag: 0.5,
        ),
      );
    }
  }

  void update(double dt) {
    for (final p in particles) {
      p.age += dt;
      p.vy += p.gravity * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      final k = math.pow(p.drag, dt).toDouble();
      p.vx *= k;
      p.vy *= k;
      p.rotation += p.spin * dt;
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
    for (final w in waves) {
      w.age += dt;
    }
    waves.removeWhere((w) => w.age >= w.life);
    if (banner != null) {
      banner!.age += dt;
      if (banner!.age >= banner!.life) banner = null;
    }
    shieldFlash = math.max(0, shieldFlash - dt * 2.5);
    perfectFlash = math.max(0, perfectFlash - dt * 3.5);
    hitPulse = math.max(0, hitPulse - dt * 5);
    ringPulse = math.max(0, ringPulse - dt * 6);
    zoom = math.max(0, zoom - dt * 5);
    edgeFlash = math.max(0, edgeFlash - dt * 3);
    ballMorph = math.max(0, ballMorph - dt * 6);
    shake = math.max(0, shake - dt * 4);
    glow += (glowTarget - glow) * math.min(1, dt * 4);
  }
}
