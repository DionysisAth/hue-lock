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

const _ink = Color(0xE6101018);
const _gold = Color(0xFFFFD54A);
const _feverColor = Color(0xFFFF7A2F);

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

    _paintBackground(canvas, size, layout, fx);

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

    // Halo + neutral ring (rainbow-tinted during Fever).
    if (theme.outerHalo != null || engine.fever) {
      final halo = engine.fever
          ? HSVColor.fromAHSV(1, (t * 120) % 360, 0.8, 1).toColor()
          : theme.outerHalo!;
      canvas.drawCircle(
        c,
        r + ringW * 1.1,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = engine.fever ? 3 : 2
          ..color = halo.withValues(alpha: 0.35 + 0.4 * fx.glow)
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
      final spec = round.spec;
      final ghostAlpha = spec.ghost && !dead ? _ghostAlpha(t) : 1.0;
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

    _paintPointer(canvas, layout, ringW, pointerAngle, dead, round);
    _paintBall(canvas, layout, round, fx);
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
    if (fx.shieldFlash > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = palette[1].withValues(alpha: fx.shieldFlash * 0.25),
      );
    }
  }

  double _ghostAlpha(double t) {
    final g = engine.config.ghost;
    final phase = (t % g.period) / g.period;
    // Smooth on/off: visible for visibleFraction of the period.
    const edge = 0.08;
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
    // Glow rises with combo and score; Fever cycles through hues.
    final glow = fx.glow * theme.glowStrength;
    final round = engine.round;
    if (glow > 0.01 && round != null) {
      final color = engine.fever
          ? HSVColor.fromAHSV(1, (engine.time * 90) % 360, 0.85, 1).toColor()
          : palette[round.spec.targetColor];
      canvas.drawCircle(
        layout.center,
        layout.radius * 2.8,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: (engine.fever ? 0.4 : 0.28) * glow),
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
      canvas.drawArc(
        rect,
        start,
        z.width,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringW * 1.25
          ..color = (z.isBonus ? _gold : color).withValues(
            alpha: alpha * (z.isBonus ? 0.6 : 0.35 * theme.glowStrength),
          )
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            3 + 6 * math.max(theme.glowStrength, z.isBonus ? 0.6 : 0),
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
        color: _gold.withValues(alpha: alpha),
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
      rad * 1.35,
      Paint()
        ..color = color.withValues(alpha: 0.35 * alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, rad * 0.5),
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
        ? Color.lerp(theme.pointer, _feverColor, 0.55)!
        : theme.pointer;
    if (theme.glowStrength > 0 || surging) {
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..strokeWidth = ringW * 0.55
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(
            alpha: 0.45 * math.max(theme.glowStrength, surging ? 0.8 : 0),
          )
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
        : engine.fever
        ? _feverColor
        : palette[colors.first];
    if (theme.glowStrength > 0 || engine.fever) {
      canvas.drawCircle(
        c,
        br * (engine.fever ? 1.45 : 1.25),
        Paint()
          ..color = glowColor.withValues(
            alpha:
                (0.25 + 0.35 * fx.glow) *
                math.max(theme.glowStrength, engine.fever ? 0.9 : 0),
          )
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, br * 0.35),
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
      // Boss round in play: a blank ball with "?" and the progress.
      _BallBlank.paint(canvas, c, br, theme.ringNeutral);
      _label(canvas, '?', c, br * 0.9, color: theme.text);
    } else {
      skin.paint(canvas, c, br, palette[colors.first], t);
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
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color ?? theme.text,
          fontSize: size,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
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
      final y =
          layout.center.dy +
          layout.radius * 1.45 +
          (fx.banner != null ? 64 : 0) +
          slot * 36 -
          k * 22;
      tp.paint(canvas, Offset(layout.center.dx - tp.width / 2, y));
      slot++;
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
    final title = TextPainter(
      text: TextSpan(
        text: b.title,
        style: TextStyle(
          color: color.withValues(alpha: a),
          fontSize: 34 * scale,
          fontWeight: FontWeight.w900,
          letterSpacing: 4,
          shadows: theme.dark
              ? [
                  Shadow(
                    color: color.withValues(alpha: 0.7 * a),
                    blurRadius: 18,
                  ),
                ]
              : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Below the ring, so it never covers the HUD or the zones.
    final top = layout.center.dy + layout.radius + ringW * 1.6 + 6;
    title.paint(canvas, Offset(layout.center.dx - title.width / 2, top));
    if (b.subtitle != null) {
      final sub = TextPainter(
        text: TextSpan(
          text: b.subtitle,
          style: TextStyle(
            color: theme.subtleText.withValues(alpha: a),
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      sub.paint(
        canvas,
        Offset(layout.center.dx - sub.width / 2, top + title.height + 2),
      );
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
