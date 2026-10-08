import 'dart:math' as math;
import 'dart:ui';

/// Zone colors. Index = color id used by the game logic.
///
/// Colorblind mode switches to the Okabe-Ito palette and also draws a symbol
/// on every zone and on the ball, so color is never the only cue.
class HuePalette {
  const HuePalette._(this.colors);

  final List<Color> colors;

  static const standard = HuePalette._([
    Color(0xFFFF3D6E), // red
    Color(0xFF2F8BFF), // blue
    Color(0xFFFFC928), // yellow
    Color(0xFF22D58B), // green
  ]);

  static const colorblind = HuePalette._([
    Color(0xFFD55E00), // vermillion
    Color(0xFF0072B2), // blue
    Color(0xFFF0E442), // yellow
    Color(0xFFCC79A7), // reddish purple
  ]);

  static HuePalette of({required bool colorblind}) =>
      colorblind ? HuePalette.colorblind : HuePalette.standard;

  Color operator [](int i) => colors[i % colors.length];
}

enum ColorSymbol { triangle, square, circle, cross }

ColorSymbol symbolFor(int color) =>
    ColorSymbol.values[color % ColorSymbol.values.length];

/// Draws the symbol for [color] centered at [c] with "radius" [r].
void drawColorSymbol(Canvas canvas, Offset c, double r, int color, Color ink) {
  final fill = Paint()
    ..color = ink
    ..isAntiAlias = true;
  final stroke = Paint()
    ..color = ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = r * 0.38
    ..strokeCap = StrokeCap.round;
  switch (symbolFor(color)) {
    case ColorSymbol.triangle:
      final path = Path();
      for (var i = 0; i < 3; i++) {
        final a = -math.pi / 2 + i * 2 * math.pi / 3;
        final p = c + Offset(math.cos(a), math.sin(a)) * r * 1.1;
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path..close(), fill);
    case ColorSymbol.square:
      canvas.drawRect(Rect.fromCircle(center: c, radius: r * 0.78), fill);
    case ColorSymbol.circle:
      canvas.drawCircle(c, r * 0.72, stroke);
    case ColorSymbol.cross:
      canvas.drawLine(c - Offset(r, 0) * 0.9, c + Offset(r, 0) * 0.9, stroke);
      canvas.drawLine(c - Offset(0, r) * 0.9, c + Offset(0, r) * 0.9, stroke);
  }
}
