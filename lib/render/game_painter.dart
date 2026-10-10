import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/angles.dart';
import '../game/effects.dart';
import '../game/game_engine.dart';
import '../game/hit_judge.dart';
import '../game/round.dart';
import 'ball_skins.dart';
import 'palette.dart';
import 'ring_themes.dart';
import 'text_sprites.dart';

/// Where the ring sits for a given screen size (portrait, notch-safe because
/// the ring is centered well away from the edges).
class RingLayout {
  RingLayout(Size size)
    : center = Offset(size.width / 2, size.height * 0.48),
      radius = math.min(size.width * 0.36, size.height * 0.24);

  final Offset center;
  final double radius;

  Offset at(double angle, double r) =>
      center + Offset(math.sin(angle), -math.cos(angle)) * r;
}

/// Background tint of each stage of a run (index = world % length). Only the
/// background is tinted, so zone colors stay readable.
const worldTints = [
  Color(0x00000000),
  Color(0xFF00D1C1),
  Color(0xFFFF6A3D),
  Color(0xFF4DFFB8),
  Color(0xFFE040FB),
  Color(0xFF3D5AFE),
];

/// Halo color per combo multiplier (index = multiplier - 1).
const comboHeat = [
  Color(0xFFFFFFFF),
  Color(0xFF7FE7FF),
  Color(0xFFFFD54A),
  Color(0xFFFF9F43),
  Color(0xFFFF4D8D),
];

const _ink = Color(0xE6101018);
const _gold = Color(0xFFFFD54A);
const _surgeColor = Color(0xFFFF7A2F);

class GamePainter extends CustomPainter {
  GamePainter({
    required this.engine,
    required this.theme,
    required this.skin,
    required this.palette,
    required this.colorblind,
    required Listenable repaint,
    this.pixelRatio = 2,
  }) : super(repaint: repaint);

  final GameEngine engine;
  final RingTheme theme;
  final BallSkin skin;
  final HuePalette palette;
  final bool colorblind;

  /// Device pixel ratio, so cached text sprites stay crisp.
  final double pixelRatio;

  // Ring-space angle 0 is "up"; Canvas.drawArc's 0 is "right".
  static double _arcStart(double a) => a - math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final fx = engine.effects;
    final layout = RingLayout(size);
    final c = layout.center;
    final r = layout.radius;
    final ringW = r * theme.ringWidth;
    final t = engine.time;

    _paintBackground(canvas, size, layout, fx);

    _paintStars(canvas, size, fx);

    canvas.save();
    if (fx.shake > 0) {
      final s = fx.shake * fx.shake * r * 0.05;
      canvas.translate(math.sin(t * 91) * s, math.cos(t * 77) * s);
    }
    // Camera punch-in on Perfects, and the ring "breathing" on every hit.
    final punch =
        1 +
        0.035 * Curves.easeOut.transform(fx.zoom) +
        0.018 * math.sin(fx.ringPulse * math.pi);
    if (punch != 1) {
      canvas.translate(c.dx, c.dy);
      canvas.scale(punch);
      canvas.translate(-c.dx, -c.dy);
    }

    final round = engine.round;
    final ringAngle = engine.ringAngle();
    final pointerAngle = engine.pointerAngle();
    final dead =
        engine.phase == GamePhase.dying || engine.phase == GamePhase.gameOver;

    // Halo + neutral ring: it heats up with the combo (x2 cyan .. x5
    // pink). A wide faint stroke under a thin bright one stands in for a
    // blur (no offscreen pass).
    final heat = engine.multiplier.clamp(1, comboHeat.length);
    if (theme.outerHalo != null || heat >= 2) {
      final halo = heat >= 2 ? comboHeat[heat - 1] : theme.outerHalo!;
      final width = heat >= 2 ? 1.5 + 0.5 * heat : 2.0;
      final a = math.min(1.0, 0.35 + 0.4 * fx.glow + 0.08 * (heat - 1));
      final haloPaint = Paint()..style = PaintingStyle.stroke;
      canvas.drawCircle(
        c,
        r + ringW * 1.1,
        haloPaint
          ..strokeWidth = width * 4
          ..color = halo.withValues(alpha: a * 0.16),
      );
      canvas.drawCircle(
        c,
        r + ringW * 1.1,
        haloPaint
          ..strokeWidth = width
          ..color = halo.withValues(alpha: a),
      );
    }
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringW
        ..color = theme.ringNeutral,
    );

    // Zones.
    if (round != null) {
      final spec = round.spec;
      final ghostAlpha = spec.ghost && !dead
          ? _ghostAlpha(math.max(0, t - round.startTime))
          : 1.0;
      for (var i = 0; i < spec.zones.length; i++) {
        if (round.consumed.contains(i)) continue;
        _paintZone(
          canvas,
          layout,
          ringW,
          spec.zones[i],
          ringAngle,
          alpha: ghostAlpha,
        );
      }
      if (!dead) {
        _paintSweetSpots(canvas, layout, ringW, round, ringAngle, ghostAlpha);
      }
      if (dead) {
        final pulse = 0.5 + 0.5 * math.sin(engine.phaseElapsed * 14);
        _paintZone(
          canvas,
          layout,
          ringW,
          round.currentPrimary,
          ringAngle,
          highlight: true,
          pulse: pulse,
        );
      }
    }

    // Lock flashes (zones that were just hit). The glow is a wider, fainter
    // stroke rather than a blur, which would cost an offscreen pass on
    // every frame of every flash.
    final ringRect = Rect.fromCircle(center: c, radius: r);
    for (final l in fx.locks) {
      final k = 1 - l.t;
      final w = ringW * (1 + 0.9 * l.t);
      final color = Color.lerp(palette[l.color], Colors.white, 0.5)!;
      final start = _arcStart(l.angle - l.width / 2);
      if (theme.glowStrength > 0) {
        // Two soft halos with round ends stand in for a blur.
        final spread = theme.glowStrength * (l.perfect ? 1.5 : 1);
        final glow = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        for (final (grow, a) in [(0.9, 0.16), (0.45, 0.22)]) {
          canvas.drawArc(
            ringRect,
            start,
            l.width,
            false,
            glow
              ..strokeWidth = w * (1 + grow * spread)
              ..color = color.withValues(alpha: k * a),
          );
        }
      }
      canvas.drawArc(
        ringRect,
        start,
        l.width,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..color = color.withValues(alpha: k * 0.9),
      );
    }

    if (dead && round != null && engine.lastMiss != null) {
      _paintMissGuide(canvas, layout, ringW, round, ringAngle, pointerAngle);
    }

    if (!dead) _paintTrail(canvas, layout, ringW, pointerAngle, round);
    _paintPointer(canvas, layout, ringW, pointerAngle, dead, round);
    _paintBall(canvas, layout, round, fx);
    _paintWaves(canvas, layout, fx);
    _paintParticles(canvas, layout, fx);
    _paintTexts(canvas, layout, fx);
    _paintBanner(canvas, layout, ringW, fx);

    canvas.restore();

    if (fx.perfectFlash > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = Colors.white.withValues(
            alpha: fx.perfectFlash * 0.12 * (theme.dark ? 1 : 0.6),
          ),
      );
    }
    if (fx.edgeFlash > 0) {
      final rect = Offset.zero & size;
      final color = palette[fx.edgeColor];
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            radius: 1.05,
            colors: [
              color.withValues(alpha: 0),
              color.withValues(alpha: 0.38 * fx.edgeFlash),
            ],
            stops: const [0.72, 1],
          ).createShader(rect),
      );
    }
    if (fx.shieldFlash > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = palette[1].withValues(alpha: fx.shieldFlash * 0.25),
      );
    }
  }

  double _ghostAlpha(double t) {
    final g = engine.config.ghost;
    // Smooth on/off: visible for visibleFraction of the period, starting
    // fully visible when the round starts.
    const edge = 0.08;
    final phase = ((t % g.period) / g.period + edge) % 1.0;
    final v = g.visibleFraction;
    double a;
    if (phase < edge) {
      a = phase / edge;
    } else if (phase < v) {
      a = 1;
    } else if (phase < v + edge) {
      a = 1 - (phase - v) / edge;
    } else {
      a = 0;
    }
    return 0.07 + 0.93 * a;
  }

  void _paintBackground(
    Canvas canvas,
    Size size,
    RingLayout layout,
    Effects fx,
  ) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [theme.bgTop, theme.bgBottom],
        ).createShader(rect),
    );
    final glowRect = Rect.fromCircle(
      center: layout.center,
      radius: layout.radius * 2.8,
    );
    // Stage tint.
    final tint = worldTints[engine.world % worldTints.length];
    if (engine.phase != GamePhase.home && tint.a > 0) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0, -0.1),
            radius: 1.1,
            colors: [
              tint.withValues(alpha: theme.dark ? 0.22 : 0.14),
              tint.withValues(alpha: theme.dark ? 0.05 : 0.03),
            ],
          ).createShader(rect),
      );
    }
    // Glow rises with combo and score.
    final glow = fx.glow * theme.glowStrength;
    final round = engine.round;
    if (glow > 0.01 && round != null) {
      final color = palette[round.spec.targetColor];
      canvas.drawCircle(
        layout.center,
        layout.radius * 2.8,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.28 * glow),
              color.withValues(alpha: 0),
            ],
          ).createShader(glowRect),
      );
    }
  }

  void _paintZone(
    Canvas canvas,
    RingLayout layout,
    double ringW,
    Zone z,
    double ringAngle, {
    bool highlight = false,
    double pulse = 0,
    double alpha = 1,
  }) {
    final c = layout.center;
    final r = layout.radius;
    final angle = ringAngle + z.center;
    final rect = Rect.fromCircle(center: c, radius: r);
    final color = palette[z.color];
    final start = _arcStart(angle - z.halfWidth);

    if (highlight) {
      canvas.drawArc(
        rect,
        start,
        z.width,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringW * (1.5 + 0.4 * pulse)
          ..color = color.withValues(alpha: 0.35 + 0.35 * pulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      return;
    }

    if (theme.glowStrength > 0 || z.isBonus) {
      // Soft glow as two wider, fainter strokes: a blur here would cost an
      // offscreen pass per zone on every frame.
      final glowColor = z.isBonus ? _gold : color;
      final strength = z.isBonus ? 0.6 : 0.35 * theme.glowStrength;
      final spread = math.max(theme.glowStrength, z.isBonus ? 0.6 : 0);
      final glow = Paint()..style = PaintingStyle.stroke;
      for (final (grow, k) in [(0.7, 0.35), (0.35, 0.55)]) {
        canvas.drawArc(
          rect,
          start,
          z.width,
          false,
          glow
            ..strokeWidth = ringW * (1 + grow * spread)
            ..color = glowColor.withValues(alpha: alpha * strength * k),
        );
      }
    }
    canvas.drawArc(
      rect,
      start,
      z.width,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringW
        ..color = color.withValues(alpha: alpha),
    );
    final outline = z.isBonus ? _gold : theme.zoneOutline;
    if (outline != null) {
      final o = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = z.isBonus ? 2.5 : 1.5
        ..color = outline.withValues(alpha: outline.a * alpha);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r + ringW / 2),
        start,
        z.width,
        false,
        o,
      );
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - ringW / 2),
        start,
        z.width,
        false,
        o,
      );
    }
    if (colorblind) {
      drawColorSymbol(
        canvas,
        layout.at(angle, r),
        ringW * 0.28,
        z.color,
        _ink.withValues(alpha: 0.9 * alpha),
      );
    }
    final badge = layout.at(angle, r + ringW * 1.2);
    if (z.hasCoin) {
      final cr = ringW * 0.32;
      canvas.drawCircle(badge, cr, Paint()..color = _gold);
      canvas.drawCircle(
        badge,
        cr * 0.62,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cr * 0.22
          ..color = const Color(0xFFE0A800),
      );
    }
    if (z.powerUp != null) {
      _paintPowerUpBadge(canvas, badge, ringW * 0.55, z.powerUp!, alpha);
    }
    if (z.isBonus) {
      _label(
        canvas,
        '+${engine.config.bonusZone.points}',
        badge,
        ringW * 0.62,
        color: _gold,
        opacity: alpha,
      );
    }
  }

  void _paintPowerUpBadge(
    Canvas canvas,
    Offset p,
    double rad,
    PowerUp type,
    double alpha,
  ) {
    final color = switch (type) {
      PowerUp.shield => HuePalette.standard[1],
      PowerUp.slow => HuePalette.standard[3],
      PowerUp.wide => HuePalette.standard[2],
    };
    canvas.drawCircle(
      p,
      rad * 1.6,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.4 * alpha),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: p, radius: rad * 1.6)),
    );
    canvas.drawCircle(p, rad, Paint()..color = color.withValues(alpha: alpha));
    final ink = Paint()
      ..color = Colors.white.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = rad * 0.18
      ..strokeCap = StrokeCap.round;
    final s = rad * 0.5;
    switch (type) {
      case PowerUp.shield:
        final path = Path()
          ..moveTo(p.dx, p.dy - s)
          ..lineTo(p.dx + s * 0.85, p.dy - s * 0.6)
          ..quadraticBezierTo(p.dx + s * 0.8, p.dy + s * 0.5, p.dx, p.dy + s)
          ..quadraticBezierTo(
            p.dx - s * 0.8,
            p.dy + s * 0.5,
            p.dx - s * 0.85,
            p.dy - s * 0.6,
          )
          ..close();
        canvas.drawPath(path, ink);
      case PowerUp.slow:
        final path = Path()
          ..moveTo(p.dx - s * 0.7, p.dy - s)
          ..lineTo(p.dx + s * 0.7, p.dy - s)
          ..lineTo(p.dx - s * 0.7, p.dy + s)
          ..lineTo(p.dx + s * 0.7, p.dy + s)
          ..close();
        canvas.drawPath(path, ink);
      case PowerUp.wide:
        canvas.drawLine(p - Offset(s, 0), p + Offset(s, 0), ink);
        for (final d in [-1.0, 1.0]) {
          final tip = p + Offset(s * d, 0);
          canvas.drawLine(tip, tip + Offset(-d * s * 0.45, -s * 0.45), ink);
          canvas.drawLine(tip, tip + Offset(-d * s * 0.45, s * 0.45), ink);
        }
    }
  }

  void _paintMissGuide(
    Canvas canvas,
    RingLayout layout,
    double ringW,
    ActiveRound round,
    double ringAngle,
    double pointerAngle,
  ) {
    final target = round.currentPrimary;
    final targetAngle = ringAngle + target.center;
    // Arc from where the pointer stopped to the nearest edge of the target.
    final diff = angleDiff(targetAngle, pointerAngle);
    final toEdge = diff - diff.sign * target.halfWidth;
    final guideR = layout.radius + ringW * 1.45;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = theme.text.withValues(alpha: 0.8);
    final rect = Rect.fromCircle(center: layout.center, radius: guideR);
    canvas.drawArc(rect, _arcStart(pointerAngle), toEdge, false, paint);
    final tip = pointerAngle + toEdge;
    final tipP = layout.at(tip, guideR);
    final tangent = Offset(math.cos(tip), math.sin(tip)) * toEdge.sign;
    final normal = Offset(-tangent.dy, tangent.dx);
    final head = Path()
      ..moveTo(tipP.dx, tipP.dy)
      ..lineTo(
        (tipP - tangent * 9 + normal * 5).dx,
        (tipP - tangent * 9 + normal * 5).dy,
      )
      ..moveTo(tipP.dx, tipP.dy)
      ..lineTo(
        (tipP - tangent * 9 - normal * 5).dx,
        (tipP - tangent * 9 - normal * 5).dy,
      );
    canvas.drawPath(head, paint);
  }

  void _paintPointer(
    Canvas canvas,
    RingLayout layout,
    double ringW,
    double angle,
    bool dead,
    ActiveRound? round,
  ) {
    final inner = layout.at(angle, layout.radius - ringW * 0.95);
    final outer = layout.at(angle, layout.radius + ringW * 0.95);
    // Surge rounds get a hot pointer so the speed swings read as intended.
    final surging = round != null && round.spec.pulseAmplitude > 0;
    final color = dead
        ? const Color(0xFFFF4D4D)
        : surging
        ? Color.lerp(theme.pointer, _surgeColor, 0.55)!
        : theme.pointer;
    if (theme.glowStrength > 0 || surging) {
      final a = 0.45 * math.max(theme.glowStrength, surging ? 0.8 : 0);
      final glow = Paint()..strokeCap = StrokeCap.round;
      for (final (w, k) in [(0.85, 0.3), (0.55, 0.6)]) {
        canvas.drawLine(
          inner,
          outer,
          glow
            ..strokeWidth = ringW * w
            ..color = color.withValues(alpha: a * k),
        );
      }
    }
    canvas.drawLine(
      inner,
      outer,
      Paint()
        ..strokeWidth = ringW * 0.3
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  void _paintBall(
    Canvas canvas,
    RingLayout layout,
    ActiveRound? round,
    Effects fx,
  ) {
    final t = engine.time;
    final pulse = fx.hitPulse;
    // "Lock" snap: a quick squash that springs back.
    final scale = 1 + 0.16 * math.sin(pulse * math.pi) * pulse;
    final br = layout.radius * 0.3 * scale;
    final c = layout.center;
    final spec = round?.spec;
    final kind = spec?.kind ?? RoundKind.normal;

    // Which color(s) the ball shows right now.
    final List<int> colors;
    if (spec == null) {
      colors = [(t / 1.6).floor() % 4];
    } else if (kind == RoundKind.split && round!.step == 0) {
      colors = spec.ballColors;
    } else if (kind == RoundKind.split) {
      colors = [spec.ballColors[1]];
    } else if (kind == RoundKind.boss) {
      final i = engine.bossPreviewIndex;
      colors = i >= 0 ? [spec.ballColors[i]] : const [];
    } else {
      colors = [spec.ballColors.first];
    }

    final glowColor = colors.isEmpty
        ? theme.ringNeutral
        : palette[colors.first];
    if (theme.glowStrength > 0) {
      // A radial gradient instead of a blurred circle: same soft glow,
      // no offscreen blur pass every frame.
      final a = (0.25 + 0.35 * fx.glow) * theme.glowStrength;
      final glowR = br * 1.6;
      canvas.drawCircle(
        c,
        glowR,
        Paint()
          ..shader = RadialGradient(
            colors: [
              glowColor.withValues(alpha: a),
              glowColor.withValues(alpha: a),
              glowColor.withValues(alpha: 0),
            ],
            stops: const [0, 0.55, 1],
          ).createShader(Rect.fromCircle(center: c, radius: glowR)),
      );
    }

    if (colors.length == 2) {
      // Split ball: left half first color, right half second.
      for (var h = 0; h < 2; h++) {
        canvas.save();
        canvas.clipRect(
          Rect.fromLTRB(
            h == 0 ? c.dx - br * 2 : c.dx,
            c.dy - br * 2,
            h == 0 ? c.dx : c.dx + br * 2,
            c.dy + br * 2,
          ),
        );
        skin.paint(canvas, c, br, palette[colors[h]], t);
        canvas.restore();
      }
      canvas.drawLine(
        c - Offset(0, br),
        c + Offset(0, br),
        Paint()
          ..color = _ink
          ..strokeWidth = br * 0.08,
      );
      _label(canvas, '1', c + Offset(-br * 0.45, br * 1.35), br * 0.32);
      _label(canvas, '2', c + Offset(br * 0.45, br * 1.35), br * 0.32);
    } else if (colors.isEmpty) {
      // Boss round: blank between colors; "?" once it is your turn.
      _BallBlank.paint(canvas, c, br, theme.ringNeutral);
      if (!engine.bossPreview) {
        _label(canvas, '?', c, br * 0.9, color: theme.text);
      }
    } else {
      // Morph from the previous color, so each new round "pours" in.
      final to = palette[colors.first];
      final color = fx.ballMorph > 0 && kind != RoundKind.split
          ? Color.lerp(
              palette[fx.ballFrom],
              to,
              Curves.easeOut.transform(1 - fx.ballMorph),
            )!
          : to;
      skin.paint(canvas, c, br, color, t);
    }

    if (kind == RoundKind.inverted && spec != null) {
      // "NOT" round: the ball's color is forbidden.
      final x = Paint()
        ..color = Colors.white
        ..strokeWidth = br * 0.16
        ..strokeCap = StrokeCap.round;
      final shadow = Paint()
        ..color = _ink
        ..strokeWidth = br * 0.28
        ..strokeCap = StrokeCap.round;
      for (final p in [shadow, x]) {
        canvas.drawLine(
          c + Offset(-br, -br) * 0.62,
          c + Offset(br, br) * 0.62,
          p,
        );
        canvas.drawLine(
          c + Offset(br, -br) * 0.62,
          c + Offset(-br, br) * 0.62,
          p,
        );
      }
      _label(canvas, 'NOT', c + Offset(0, br * 1.42), br * 0.36);
    }

    if (colorblind && colors.length == 1) {
      drawColorSymbol(
        canvas,
        c + Offset(0, br * 0.62),
        br * 0.2,
        colors.first,
        _ink,
      );
    }

    if (spec != null && kind == RoundKind.boss) {
      _paintBossProgress(canvas, c, br, round!);
    } else if (spec != null) {
      _paintLockPips(canvas, c, br);
    }
    if (round != null && !engine.bossPreview) _paintFuse(canvas, c, br);
    if (engine.shield) {
      canvas.drawCircle(
        c,
        br * 1.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = br * 0.06
          ..color = palette[1].withValues(
            alpha: 0.5 + 0.3 * math.sin(engine.time * 5),
          ),
      );
    }
  }

  /// Fuse: a ring around the ball that burns down until the pointer has
  /// passed the target.
  void _paintFuse(Canvas canvas, Offset c, double br) {
    final f = engine.fuse;
    if (f >= 1 && engine.phase == GamePhase.home) return;
    final rect = Rect.fromCircle(center: c, radius: br * 1.28);
    canvas.drawCircle(
      c,
      br * 1.28,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = br * 0.07
        ..color = theme.text.withValues(alpha: 0.1),
    );
    final hot = f < 0.3;
    final color = hot
        ? Color.lerp(const Color(0xFFFF4D4D), _gold, f / 0.3)!
        : theme.text.withValues(alpha: 0.75);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * f,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = br * 0.07
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  /// Lock set progress: one pip per lock in the set, filled when cleared.
  void _paintLockPips(Canvas canvas, Offset c, double br) {
    final n = engine.setSize;
    if (n <= 1) return;
    const gap = 0.32;
    final y = c.dy - br * 1.62;
    for (var i = 0; i < n; i++) {
      final x = c.dx + (i - (n - 1) / 2) * br * gap;
      final done = i < engine.setDone;
      canvas.drawCircle(
        Offset(x, y),
        br * 0.085,
        Paint()..color = done ? theme.text : theme.text.withValues(alpha: 0.18),
      );
    }
  }

  void _paintBossProgress(Canvas canvas, Offset c, double br, ActiveRound r) {
    final seq = r.spec.ballColors;
    const gap = 0.36;
    final y = c.dy - br * 1.62;
    final preview = engine.bossPreview;
    for (var i = 0; i < seq.length; i++) {
      final x = c.dx + (i - (seq.length - 1) / 2) * br * gap;
      final done = i < r.step;
      final showing = preview && i == engine.bossPreviewIndex;
      final p = Offset(x, y);
      if (done || showing) {
        canvas.drawCircle(p, br * 0.11, Paint()..color = palette[seq[i]]);
      } else {
        canvas.drawCircle(
          p,
          br * 0.1,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = br * 0.035
            ..color = theme.text.withValues(alpha: 0.5),
        );
      }
    }
  }

  void _label(
    Canvas canvas,
    String text,
    Offset center,
    double size, {
    Color? color,
    double opacity = 1,
  }) {
    // Sizes that follow the ball's squash would change every frame; render
    // at a whole font size and scale the cached sprite instead.
    final base = math.max(1.0, size.ceilToDouble());
    final sprite = TextSprites.get(
      text,
      color: color ?? theme.text,
      fontSize: base,
      letterSpacing: 1,
      pixelRatio: pixelRatio,
    );
    sprite.paint(
      canvas,
      center - Offset(0, sprite.textHeight * size / base / 2),
      scale: size / base,
      opacity: opacity,
    );
  }

  /// Every particle in one draw call: shards, stars, confetti and dots are
  /// all emitted as colored triangles. (Dozens of separate paths per frame
  /// is what a Perfect used to cost.)
  void _paintParticles(Canvas canvas, RingLayout layout, Effects fx) {
    if (fx.particles.isEmpty) return;
    final pos = <double>[];
    final colors = <int>[];
    late int color;
    void tri(double x0, double y0, double x1, double y1, double x2, double y2) {
      pos.addAll([x0, y0, x1, y1, x2, y2]);
      colors.addAll([color, color, color]);
    }

    for (final p in fx.particles) {
      final base = p.color < 0 ? Colors.white : palette[p.color];
      final fade = p.shape == ParticleShape.confetti
          ? (1 - math.max(0, p.t - 0.7) / 0.3)
          : 1 - p.t;
      final alpha = fade.clamp(0.0, 1.0);
      if (alpha <= 0) continue;
      color = base.withValues(alpha: alpha).toARGB32();
      final c = layout.center + Offset(p.x, p.y) * layout.radius;
      final size = p.size * layout.radius;
      final cos = math.cos(p.rotation);
      final sin = math.sin(p.rotation);
      // Local (x, y) rotated by the particle's rotation, then placed.
      double px(double x, double y) => c.dx + x * cos - y * sin;
      double py(double x, double y) => c.dy + x * sin + y * cos;
      switch (p.shape) {
        case ParticleShape.dot:
          final r = size * (1 - 0.5 * p.t);
          const n = 8;
          for (var i = 0; i < n; i++) {
            final a0 = i * 2 * math.pi / n;
            final a1 = (i + 1) * 2 * math.pi / n;
            tri(
              c.dx,
              c.dy,
              c.dx + math.cos(a0) * r,
              c.dy + math.sin(a0) * r,
              c.dx + math.cos(a1) * r,
              c.dy + math.sin(a1) * r,
            );
          }
        case ParticleShape.shard:
          final s = size * (1 - 0.4 * p.t);
          tri(
            px(-s, -s * 0.35),
            py(-s, -s * 0.35),
            px(s, 0),
            py(s, 0),
            px(-s * 0.6, s * 0.45),
            py(-s * 0.6, s * 0.45),
          );
        case ParticleShape.star:
          final s = size * math.sin(p.t * math.pi);
          for (var i = 0; i < 8; i++) {
            final a0 = i * math.pi / 4;
            final a1 = (i + 1) * math.pi / 4;
            final r0 = i.isEven ? s : s * 0.28;
            final r1 = i.isEven ? s * 0.28 : s;
            final x0 = math.cos(a0) * r0, y0 = math.sin(a0) * r0;
            final x1 = math.cos(a1) * r1, y1 = math.sin(a1) * r1;
            tri(c.dx, c.dy, px(x0, y0), py(x0, y0), px(x1, y1), py(x1, y1));
          }
        case ParticleShape.confetti:
          // Flip in 3D: squash one axis with the spin.
          final hw = size * 0.7;
          final hh =
              size * 0.4 * (math.cos(p.rotation * 1.7).abs() * 0.8 + 0.2);
          final ax = px(-hw, -hh), ay = py(-hw, -hh);
          final bx = px(hw, -hh), by = py(hw, -hh);
          final cx = px(hw, hh), cy = py(hw, hh);
          final dx = px(-hw, hh), dy = py(-hw, hh);
          tri(ax, ay, bx, by, cx, cy);
          tri(ax, ay, cx, cy, dx, dy);
      }
    }
    if (pos.isEmpty) return;
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.fromList(pos),
      colors: Int32List.fromList(colors),
    );
    canvas.drawVertices(vertices, BlendMode.dst, Paint());
    vertices.dispose();
  }

  void _paintWaves(Canvas canvas, RingLayout layout, Effects fx) {
    for (final w in fx.waves) {
      final k = Curves.easeOutCubic.transform(w.t);
      final color = w.color < 0 ? Colors.white : palette[w.color];
      canvas.drawCircle(
        layout.center + Offset(w.x, w.y) * layout.radius,
        w.maxRadius * layout.radius * k,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w.width * layout.radius * (1 - w.t) + 0.5
          ..color = color.withValues(alpha: (1 - w.t) * 0.85),
      );
    }
  }

  /// The Perfect window inside every zone: a bright band to aim for. Drawn
  /// on all zones alike (decoys and wrong colors too) so it never gives the
  /// answer away.
  void _paintSweetSpots(
    Canvas canvas,
    RingLayout layout,
    double ringW,
    ActiveRound round,
    double ringAngle,
    double alpha,
  ) {
    final spec = round.spec;
    final timing = engine.config.timing;
    final speed = spec.relativeSpeed.abs();
    final scale = engine.perks.perfectScale;
    final rect = Rect.fromCircle(center: layout.center, radius: layout.radius);
    final pulse = 0.75 + 0.25 * math.sin(engine.time * 6);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringW * 0.38
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.45 * pulse * alpha);
    for (var i = 0; i < spec.zones.length; i++) {
      if (round.consumed.contains(i)) continue;
      final z = spec.zones[i];
      final half = perfectHalfWidth(z, timing, speed, scale);
      final center = ringAngle + z.center;
      canvas.drawArc(rect, _arcStart(center - half), half * 2, false, paint);
    }
  }

  /// A short fading streak behind the pointer.
  void _paintTrail(
    Canvas canvas,
    RingLayout layout,
    double ringW,
    double angle,
    ActiveRound? round,
  ) {
    final dir = round?.spec.pointerDir ?? 1;
    final speed = round == null || engine.phase != GamePhase.playing
        ? 0.0
        : round.relativeSpeedAt(engine.time);
    // The trail grows and takes the halo's color as the combo builds.
    final heat = engine.multiplier.clamp(1, comboHeat.length);
    final length = math.min(
      0.6 + 0.08 * heat,
      speed * 0.09 * (0.8 + 0.2 * heat),
    );
    if (length < 0.02) return;
    const segments = 7;
    final rect = Rect.fromCircle(center: layout.center, radius: layout.radius);
    final tint = heat >= 2
        ? Color.lerp(theme.pointer, comboHeat[heat - 1], 0.6)!
        : theme.pointer;
    final paint = Paint()..style = PaintingStyle.stroke;
    for (var i = 0; i < segments; i++) {
      final a0 = angle - dir * length * i / segments;
      final a1 = angle - dir * length * (i + 1) / segments;
      final color = tint;
      canvas.drawArc(
        rect,
        _arcStart(math.min(a0, a1)),
        (a1 - a0).abs(),
        false,
        paint
          ..strokeWidth = ringW * (0.9 - i * 0.09)
          ..color = color.withValues(
            alpha: (0.32 + 0.04 * (heat - 1)) * (1 - i / segments),
          ),
      );
    }
  }

  /// Slow drifting dust in the background; it speeds up with the combo.
  void _paintStars(Canvas canvas, Size size, Effects fx) {
    const count = 46;
    final speed = 12 + 60 * fx.glow;
    final drift = engine.time * speed;
    final paint = Paint();
    final base = theme.dark ? Colors.white : theme.text;
    for (var i = 0; i < count; i++) {
      // Deterministic pseudo-random placement per star.
      final hx = ((i * 73856093) % 1000) / 1000;
      final hy = ((i * 19349663) % 1000) / 1000;
      final hs = ((i * 83492791) % 1000) / 1000;
      final x = hx * size.width;
      final y =
          size.height - ((hy * size.height + drift * (0.4 + hs)) % size.height);
      paint.color = base.withValues(
        alpha: (theme.dark ? 0.08 : 0.05) + 0.12 * hs * (0.5 + fx.glow),
      );
      canvas.drawCircle(Offset(x, y), 0.8 + 1.6 * hs, paint);
    }
  }

  void _paintTexts(Canvas canvas, RingLayout layout, Effects fx) {
    // Below the ring, drifting upward, so it never covers the score HUD.
    // Stacked by each text's own height, so a big streak word never
    // overlaps the line under it.
    var y =
        layout.center.dy + layout.radius * 1.45 + (fx.banner != null ? 64 : 0);
    for (final text in fx.texts.reversed) {
      final k = Curves.easeOut.transform(text.t);
      final color = text.color < 0 ? theme.text : palette[text.color];
      final pop = text.huge
          ? Curves.elasticOut.transform((text.age / 0.45).clamp(0.0, 1.0))
          : 1.0;
      final sprite = TextSprites.get(
        text.text,
        color: color,
        fontSize: text.huge ? 44 : (text.big ? 30 : 20),
        glow: theme.dark ? 12 : 0,
        pixelRatio: pixelRatio,
      );
      sprite.paint(
        canvas,
        Offset(layout.center.dx, y - k * 22),
        scale: pop,
        opacity: 1 - text.t * text.t,
      );
      y += sprite.textHeight * (text.huge ? 1.05 : 0.95);
    }
  }

  /// Big announcement between the score and the ring.
  void _paintBanner(
    Canvas canvas,
    RingLayout layout,
    double ringW,
    Effects fx,
  ) {
    final b = fx.banner;
    if (b == null) return;
    final inT = (b.age / 0.18).clamp(0.0, 1.0);
    final outT = ((b.life - b.age) / 0.3).clamp(0.0, 1.0);
    final a = math.min(inT, outT);
    final scale = 0.8 + 0.2 * Curves.easeOutBack.transform(inT);
    final color = b.color < 0 ? theme.text : palette[b.color];
    final title = TextSprites.get(
      b.title,
      color: color,
      fontSize: 34,
      letterSpacing: 4,
      glow: theme.dark ? 18 : 0,
      glowAlpha: 0.7,
      pixelRatio: pixelRatio,
    );
    // Below the ring, so it never covers the HUD or the zones.
    final top = layout.center.dy + layout.radius + ringW * 1.6 + 6;
    title.paint(
      canvas,
      Offset(layout.center.dx, top),
      scale: scale,
      opacity: a,
    );
    if (b.subtitle != null) {
      final sub = TextSprites.get(
        b.subtitle!,
        color: theme.subtleText,
        fontSize: 15,
        weight: FontWeight.w800,
        letterSpacing: 3,
        pixelRatio: pixelRatio,
      );
      sub.paint(
        canvas,
        Offset(layout.center.dx, top + title.textHeight + 2),
        opacity: a,
      );
    }
  }

  @override
  bool shouldRepaint(GamePainter old) =>
      old.theme != theme ||
      old.skin != skin ||
      old.palette != palette ||
      old.colorblind != colorblind ||
      old.pixelRatio != pixelRatio ||
      old.engine != engine;
}

/// Neutral ball for boss rounds (the sequence must be remembered).
class _BallBlank {
  static void paint(Canvas canvas, Offset c, double r, Color base) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [Color.lerp(base, Colors.white, 0.25)!, base],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }
}
