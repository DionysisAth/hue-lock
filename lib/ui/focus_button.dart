import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/game_engine.dart';
import '../l10n/l10n.dart';
import '../render/ring_themes.dart';

const focusColor = Color(0xFF7FE7FF);

/// The Focus button: its ring shows the meter (filled by Perfects); a tap
/// slows time until the meter runs out (or until tapped again). Taps here
/// never count as game taps.
class FocusButton extends StatelessWidget {
  const FocusButton({
    super.key,
    required this.engine,
    required this.frame,
    required this.theme,
  });

  final GameEngine engine;

  /// Ticks every frame, so the meter drains smoothly while Focus is on.
  final Listenable frame;
  final RingTheme theme;

  static const size = 74.0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => engine.toggleFocus(),
      child: Semantics(
        button: true,
        label: tr('Focus: slow time'),
        child: RepaintBoundary(
          child: CustomPaint(
            size: const Size.square(size),
            painter: _FocusPainter(engine, theme, frame),
          ),
        ),
      ),
    );
  }
}

class _FocusPainter extends CustomPainter {
  _FocusPainter(this.engine, this.theme, Listenable frame)
    : super(repaint: frame);

  final GameEngine engine;
  final RingTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 4;
    final level = engine.focus.clamp(0.0, 1.0);
    final ready = level >= engine.config.focus.minToStart;
    final active = engine.focusActive;

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = active
            ? focusColor.withValues(alpha: 0.35)
            : theme.bgTop.withValues(alpha: 0.85),
    );
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, track..color = theme.text.withValues(alpha: 0.15));
    if (level > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        level * 2 * math.pi,
        false,
        track..color = focusColor.withValues(alpha: ready ? 1 : 0.45),
      );
    }
    // Hourglass glyph.
    final g = r * 0.38;
    final glyph = Path()
      ..moveTo(c.dx - g * 0.7, c.dy - g)
      ..lineTo(c.dx + g * 0.7, c.dy - g)
      ..lineTo(c.dx - g * 0.7, c.dy + g)
      ..lineTo(c.dx + g * 0.7, c.dy + g)
      ..close();
    canvas.drawPath(
      glyph,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..color = ready || active
            ? (active ? Colors.white : focusColor)
            : theme.subtleText.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(_FocusPainter old) =>
      old.engine != engine || old.theme != theme;
}
