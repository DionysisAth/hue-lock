import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/angles.dart';
import '../game/effects.dart';
import '../game/game_engine.dart';
import '../game/round.dart';
import 'ball_skins.dart';
import 'palette.dart';
import 'ring_themes.dart';

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

class GamePainter extends CustomPainter {
  GamePainter({
    required this.engine,
    required this.theme,
    required this.skin,
    required this.palette,
    required this.colorblind,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final GameEngine engine;
  final RingTheme theme;
  final BallSkin skin;
  final HuePalette palette;
  final bool colorblind;

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

    _paintBackground(canvas, size, fx);

    canvas.save();
    if (fx.shake > 0) {
      final s = fx.shake * fx.shake * r * 0.05;
      canvas.translate(math.sin(t * 91) * s, math.cos(t * 77) * s);
    }

    final round = engine.round;
    final ringAngle = engine.ringAngle();
    final pointerAngle = engine.pointerAngle();
    final dead =
        engine.phase == GamePhase.dying || engine.phase == GamePhase.gameOver;

    // Halo + neutral ring.
    if (theme.outerHalo != null) {
      canvas.drawCircle(
        c,
        r + ringW * 1.1,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = theme.outerHalo!.withValues(alpha: 0.35 + 0.4 * fx.glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
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
      for (final z in round.spec.zones) {
        _paintZone(canvas, layout, ringW, z, ringAngle, highlight: false);
      }
      if (dead) {
        final pulse = 0.5 + 0.5 * math.sin(engine.phaseElapsed * 14);
        _paintZone(
          canvas,
          layout,
          ringW,
          round.spec.target,
          ringAngle,
          highlight: true,
          pulse: pulse,
        );
      }
    }

    // Lock flashes (zones that were just hit).
    for (final l in fx.locks) {
      final k = 1 - l.t;
      final w = ringW * (1 + 0.9 * l.t);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..color = Color.lerp(
          palette[l.color],
          Colors.white,
          0.5,
        )!.withValues(alpha: k * 0.9);
      if (theme.glowStrength > 0) {
        paint.maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          4 + 8 * theme.glowStrength * (l.perfect ? 1.5 : 1),
        );
      }
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        _arcStart(l.angle - l.width / 2),
        l.width,
        false,
        paint,
      );
    }

    if (dead && round != null && engine.lastMiss != null) {
      _paintMissGuide(canvas, layout, ringW, round, ringAngle, pointerAngle);
    }

    _paintPointer(canvas, layout, ringW, pointerAngle, dead);
    _paintBall(canvas, layout, round, fx);
    _paintParticles(canvas, layout, fx);
    _paintTexts(canvas, layout, fx);

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
  }

  void _paintBackground(Canvas canvas, Size size, Effects fx) {
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
    // Glow rises with combo and score.
    final glow = fx.glow * theme.glowStrength;
    final round = engine.round;
    if (glow > 0.01 && round != null) {
      final layout = RingLayout(size);
      canvas.drawCircle(
        layout.center,
        layout.radius * 2.6,
        Paint()
          ..shader =
              RadialGradient(
                colors: [
                  palette[round.spec.targetColor].withValues(
                    alpha: 0.28 * glow,
                  ),
                  palette[round.spec.targetColor].withValues(alpha: 0),
                ],
              ).createShader(
                Rect.fromCircle(
                  center: layout.center,
                  radius: layout.radius * 2.6,
                ),
              ),
      );
    }
  }

  void _paintZone(
    Canvas canvas,
    RingLayout layout,
    double ringW,
    Zone z,
    double ringAngle, {
    required bool highlight,
    double pulse = 0,
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

    if (theme.glowStrength > 0) {
      canvas.drawArc(
        rect,
        start,
        z.width,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringW * 1.25
          ..color = color.withValues(alpha: 0.35 * theme.glowStrength)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            3 + 6 * theme.glowStrength,
          ),
      );
    }
    canvas.drawArc(
      rect,
      start,
      z.width,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringW
        ..color = color,
    );
    if (theme.zoneOutline != null) {
      final o = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = theme.zoneOutline!;
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
        const Color(0xE6101018),
      );
    }
    if (z.hasCoin) {
      final p = layout.at(angle, r + ringW * 1.15);
      final cr = ringW * 0.32;
      canvas.drawCircle(p, cr, Paint()..color = const Color(0xFFFFD54A));
      canvas.drawCircle(
        p,
        cr * 0.62,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cr * 0.22
          ..color = const Color(0xFFE0A800),
      );
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
    final target = round.spec.target;
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
  ) {
    final inner = layout.at(angle, layout.radius - ringW * 0.95);
    final outer = layout.at(angle, layout.radius + ringW * 0.95);
    final color = dead ? const Color(0xFFFF4D4D) : theme.pointer;
    if (theme.glowStrength > 0) {
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..strokeWidth = ringW * 0.55
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.45 * theme.glowStrength)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
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
    final colorIndex = round?.spec.targetColor ?? ((t / 1.6).floor() % 4);
    final color = palette[colorIndex];
    if (theme.glowStrength > 0) {
      canvas.drawCircle(
        layout.center,
        br * 1.25,
        Paint()
          ..color = color.withValues(
            alpha: (0.25 + 0.35 * fx.glow) * theme.glowStrength,
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, br * 0.35),
      );
    }
    skin.paint(canvas, layout.center, br, color, t);
    if (colorblind) {
      drawColorSymbol(
        canvas,
        layout.center + Offset(0, br * 0.62),
        br * 0.2,
        colorIndex,
        const Color(0xE6101018),
      );
    }
  }

  void _paintParticles(Canvas canvas, RingLayout layout, Effects fx) {
    final paint = Paint();
    for (final p in fx.particles) {
      paint.color = palette[p.color].withValues(alpha: 1 - p.t);
      canvas.drawCircle(
        layout.center + Offset(p.x, p.y) * layout.radius,
        p.size * layout.radius * (1 - 0.5 * p.t),
        paint,
      );
    }
  }

  void _paintTexts(Canvas canvas, RingLayout layout, Effects fx) {
    var slot = 0;
    for (final text in fx.texts.reversed) {
      final k = Curves.easeOut.transform(text.t);
      final color = text.color < 0 ? theme.text : palette[text.color];
      final tp = TextPainter(
        text: TextSpan(
          text: text.text,
          style: TextStyle(
            color: color.withValues(alpha: 1 - text.t * text.t),
            fontSize: text.big ? 30 : 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            shadows: theme.dark
                ? [Shadow(color: color.withValues(alpha: 0.6), blurRadius: 12)]
                : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Below the ring, drifting upward, so it never covers the score HUD.
      final y = layout.center.dy + layout.radius * 1.45 + slot * 36 - k * 22;
      tp.paint(canvas, Offset(layout.center.dx - tp.width / 2, y));
      slot++;
    }
  }

  @override
  bool shouldRepaint(GamePainter old) =>
      old.theme != theme ||
      old.skin != skin ||
      old.palette != palette ||
      old.colorblind != colorblind ||
      old.engine != engine;
}
