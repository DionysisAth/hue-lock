import 'dart:math' as math;
import 'dart:ui';

/// A cosmetic ball skin. The ball always shows the target color as its main
/// fill; skins only add decoration on top, so readability never suffers.
class BallSkin {
  const BallSkin(this.id, this.name, this.price, this._paint);

  final String id;
  final String name;
  final int price;
  final void Function(Canvas canvas, Offset c, double r, Color color, double t)
  _paint;

  /// Paints the ball at [c] with radius [r]; [t] is time in seconds for idle
  /// animation.
  void paint(Canvas canvas, Offset c, double r, Color color, double t) =>
      _paint(canvas, c, r, color, t);
}

const ballSkins = <BallSkin>[
  BallSkin('classic', 'Classic', 0, _classic),
  BallSkin('planet', 'Planet', 150, _planet),
  BallSkin('eyeball', 'Eyeball', 200, _eyeball),
  BallSkin('donut', 'Donut', 250, _donut),
  BallSkin('disco', 'Disco', 300, _disco),
  BallSkin('smiley', 'Smiley', 350, _smiley),
  BallSkin('moon', 'Moon', 400, _moon),
  BallSkin('gem', 'Gem', 500, _gem),
  // Starter Pack exclusive (price < 0: not sold for coins).
  BallSkin('crown', 'Crown', -1, _crown),
  // Levels map chapter rewards.
  BallSkin('bullseye', 'Bullseye', levelsReward, _bullseye),
  BallSkin('swirl', 'Swirl', levelsReward, _swirl),
  BallSkin('star', 'Superstar', levelsReward, _star),
];

/// Price of items only given as Levels chapter rewards.
const levelsReward = -2;

BallSkin ballSkinById(String id) =>
    ballSkins.firstWhere((s) => s.id == id, orElse: () => ballSkins.first);

Paint _fill(Color c) => Paint()
  ..color = c
  ..isAntiAlias = true;

Color _shade(Color c, double amount) =>
    Color.lerp(c, const Color(0xFF000000), amount)!;

Color _tint(Color c, double amount) =>
    Color.lerp(c, const Color(0xFFFFFFFF), amount)!;

void _shadedBall(Canvas canvas, Offset c, double r, Color color) {
  final rect = Rect.fromCircle(center: c, radius: r);
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = Gradient.radial(
        c + Offset(-r * 0.35, -r * 0.4),
        r * 1.5,
        [_tint(color, 0.25), color, _shade(color, 0.3)],
        [0, 0.55, 1],
      ),
  );
  canvas.drawOval(
    Rect.fromCenter(
      center: rect.center + Offset(-r * 0.33, -r * 0.42),
      width: r * 0.55,
      height: r * 0.32,
    ),
    _fill(const Color(0x55FFFFFF)),
  );
}

void _classic(Canvas canvas, Offset c, double r, Color color, double t) =>
    _shadedBall(canvas, c, r, color);

void _planet(Canvas canvas, Offset c, double r, Color color, double t) {
  final ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = r * 0.14
    ..color = _tint(color, 0.55)
    ..isAntiAlias = true;
  final oval = Rect.fromCenter(center: c, width: r * 2.9, height: r * 0.9);
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.rotate(-0.35);
  canvas.translate(-c.dx, -c.dy);
  // Back half of the ring, ball, then front half.
  canvas.drawArc(oval, math.pi, math.pi, false, ring);
  canvas.restore();
  _shadedBall(canvas, c, r, color);
  final band = Paint()
    ..color = _shade(color, 0.18)
    ..style = PaintingStyle.stroke
    ..strokeWidth = r * 0.12;
  canvas.save();
  canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
  canvas.drawLine(c + Offset(-r, r * 0.25), c + Offset(r, -r * 0.1), band);
  canvas.restore();
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.rotate(-0.35);
  canvas.translate(-c.dx, -c.dy);
  canvas.drawArc(oval, 0, math.pi, false, ring);
  canvas.restore();
}

void _eyeball(Canvas canvas, Offset c, double r, Color color, double t) {
  canvas.drawCircle(c, r, _fill(const Color(0xFFF6F2EE)));
  final look = Offset(
    math.sin(t * 0.9) * r * 0.18,
    math.cos(t * 0.7) * r * 0.1,
  );
  canvas.drawCircle(c + look, r * 0.62, _fill(color));
  canvas.drawCircle(
    c + look,
    r * 0.62,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.06
      ..color = _shade(color, 0.35),
  );
  canvas.drawCircle(c + look * 1.15, r * 0.26, _fill(const Color(0xFF111111)));
  canvas.drawCircle(
    c + look + Offset(-r * 0.2, -r * 0.22),
    r * 0.11,
    _fill(const Color(0xDDFFFFFF)),
  );
}

void _donut(Canvas canvas, Offset c, double r, Color color, double t) {
  canvas.drawCircle(c, r, _fill(const Color(0xFFD9A066)));
  final icing = Path()
    ..addOval(Rect.fromCircle(center: c, radius: r * 0.9))
    ..addOval(Rect.fromCircle(center: c, radius: r * 0.3))
    ..fillType = PathFillType.evenOdd;
  canvas.drawPath(icing, _fill(color));
  canvas.drawCircle(c, r * 0.3, _fill(const Color(0xFFB8804A)));
  canvas.drawCircle(c, r * 0.22, _fill(const Color(0x33000000)));
  const sprinkles = [
    Color(0xFFFFFFFF),
    Color(0xFFFFE066),
    Color(0xFF7CF7FF),
    Color(0xFFFF8FD1),
  ];
  final p = Paint()
    ..strokeWidth = r * 0.07
    ..strokeCap = StrokeCap.round;
  for (var i = 0; i < 12; i++) {
    final a = i * 2.39996;
    final d = r * (0.45 + 0.35 * ((i * 37) % 10) / 10);
    final o = c + Offset(math.cos(a), math.sin(a)) * d;
    final dir = Offset(math.cos(a * 3), math.sin(a * 3)) * r * 0.07;
    p.color = sprinkles[i % sprinkles.length];
    canvas.drawLine(o - dir, o + dir, p);
  }
}

void _disco(Canvas canvas, Offset c, double r, Color color, double t) {
  _shadedBall(canvas, c, r, color);
  canvas.save();
  canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
  final grid = Paint()
    ..color = _shade(color, 0.45)
    ..strokeWidth = r * 0.035;
  const rows = 7;
  for (var i = 1; i < rows; i++) {
    final y = c.dy - r + 2 * r * i / rows;
    canvas.drawLine(Offset(c.dx - r, y), Offset(c.dx + r, y), grid);
  }
  final spin = (t * 0.6) % 1.0;
  for (var i = 0; i < 9; i++) {
    final u = ((i + spin) / 9) * math.pi;
    final x = c.dx - r * math.cos(u);
    canvas.drawLine(Offset(x, c.dy - r), Offset(x, c.dy + r), grid);
  }
  // Sparkles.
  for (var i = 0; i < 4; i++) {
    final phase = (t * 1.3 + i * 0.27) % 1.0;
    final a = i * 1.7 + 0.4;
    final o = c + Offset(math.cos(a), math.sin(a)) * r * 0.55;
    final s = r * 0.16 * math.sin(phase * math.pi);
    final sp = Paint()
      ..color = const Color(0xEEFFFFFF)
      ..strokeWidth = r * 0.04
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(o - Offset(s, 0), o + Offset(s, 0), sp);
    canvas.drawLine(o - Offset(0, s), o + Offset(0, s), sp);
  }
  canvas.restore();
}

void _smiley(Canvas canvas, Offset c, double r, Color color, double t) {
  _shadedBall(canvas, c, r, color);
  final ink = _fill(const Color(0xFF1B1530));
  final blink = (t % 3.2) < 0.12;
  if (blink) {
    final p = Paint()
      ..color = const Color(0xFF1B1530)
      ..strokeWidth = r * 0.08
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      c + Offset(-r * 0.42, -r * 0.2),
      c + Offset(-r * 0.18, -r * 0.2),
      p,
    );
    canvas.drawLine(
      c + Offset(r * 0.18, -r * 0.2),
      c + Offset(r * 0.42, -r * 0.2),
      p,
    );
  } else {
    canvas.drawOval(
      Rect.fromCenter(
        center: c + Offset(-r * 0.3, -r * 0.2),
        width: r * 0.18,
        height: r * 0.3,
      ),
      ink,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: c + Offset(r * 0.3, -r * 0.2),
        width: r * 0.18,
        height: r * 0.3,
      ),
      ink,
    );
  }
  canvas.drawArc(
    Rect.fromCircle(center: c + Offset(0, r * 0.05), radius: r * 0.5),
    0.35,
    math.pi - 0.7,
    false,
    Paint()
      ..color = const Color(0xFF1B1530)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.09
      ..strokeCap = StrokeCap.round,
  );
}

void _moon(Canvas canvas, Offset c, double r, Color color, double t) {
  _shadedBall(canvas, c, r, color);
  final crater = _fill(_shade(color, 0.22));
  final rim = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = r * 0.04
    ..color = _tint(color, 0.3);
  const craters = [
    (0.35, -0.3, 0.2),
    (-0.4, 0.15, 0.16),
    (0.1, 0.45, 0.13),
    (-0.15, -0.5, 0.09),
    (0.55, 0.25, 0.08),
  ];
  for (final (x, y, s) in craters) {
    final o = c + Offset(x, y) * r;
    canvas.drawCircle(o, s * r, crater);
    canvas.drawCircle(o + Offset(-s, -s) * r * 0.15, s * r, rim);
  }
}

void _gem(Canvas canvas, Offset c, double r, Color color, double t) {
  const sides = 8;
  final outer = <Offset>[];
  final inner = <Offset>[];
  for (var i = 0; i < sides; i++) {
    final a = -math.pi / 2 + i * 2 * math.pi / sides + math.pi / sides;
    outer.add(c + Offset(math.cos(a), math.sin(a)) * r * 1.05);
    inner.add(c + Offset(math.cos(a), math.sin(a)) * r * 0.55);
  }
  canvas.drawPath(Path()..addPolygon(outer, true), _fill(color));
  for (var i = 0; i < sides; i++) {
    final shade = (i % 4) / 4 * 0.35 - 0.1;
    final facet = Path()
      ..addPolygon([
        outer[i],
        outer[(i + 1) % sides],
        inner[(i + 1) % sides],
        inner[i],
      ], true);
    canvas.drawPath(
      facet,
      _fill(shade > 0 ? _shade(color, shade) : _tint(color, -shade * 2)),
    );
  }
  canvas.drawPath(Path()..addPolygon(inner, true), _fill(_tint(color, 0.18)));
  final shine = (t * 0.5) % 1.0;
  final sp = c + Offset(-r * 0.25 + shine * r * 0.5, -r * 0.25);
  canvas.drawCircle(sp, r * 0.08, _fill(const Color(0xCCFFFFFF)));
}

void _crown(Canvas canvas, Offset c, double r, Color color, double t) {
  _shadedBall(canvas, c, r, color);
  // A little gold crown on top, with a glint.
  const gold = Color(0xFFFFD54A);
  final base = c.dy - r * 0.55;
  final w = r * 0.9;
  final crown = Path()
    ..moveTo(c.dx - w / 2, base)
    ..lineTo(c.dx - w / 2, base - r * 0.42)
    ..lineTo(c.dx - w / 4, base - r * 0.2)
    ..lineTo(c.dx, base - r * 0.5)
    ..lineTo(c.dx + w / 4, base - r * 0.2)
    ..lineTo(c.dx + w / 2, base - r * 0.42)
    ..lineTo(c.dx + w / 2, base)
    ..close();
  canvas.drawPath(crown, _fill(gold));
  canvas.drawPath(
    crown,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.05
      ..color = const Color(0xFFB8860B),
  );
  for (final dx in [-w / 2, 0.0, w / 2]) {
    final tip = Offset(c.dx + dx, base - (dx == 0 ? r * 0.5 : r * 0.42));
    canvas.drawCircle(tip, r * 0.07, _fill(color));
  }
  final glint = (t * 0.7) % 1.0;
  canvas.drawCircle(
    Offset(c.dx - w / 2 + w * glint, base - r * 0.15),
    r * 0.05,
    _fill(const Color(0xDDFFFFFF)),
  );
}

void _bullseye(Canvas canvas, Offset c, double r, Color color, double t) {
  _shadedBall(canvas, c, r, color);
  final ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = r * 0.13
    ..color = const Color(0xEEFFFFFF);
  canvas.drawCircle(c, r * 0.68, ring);
  canvas.drawCircle(c, r * 0.3, ring);
  canvas.drawCircle(c, r * 0.1, _fill(const Color(0xEEFFFFFF)));
}

void _swirl(Canvas canvas, Offset c, double r, Color color, double t) {
  _shadedBall(canvas, c, r, color);
  // A slowly turning spiral, built once per frame from a few arcs.
  final p = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = r * 0.11
    ..strokeCap = StrokeCap.round
    ..color = _tint(color, 0.6);
  final spin = t * 1.4;
  for (var i = 0; i < 4; i++) {
    final rr = r * (0.2 + 0.18 * i);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: rr),
      spin + i * 1.3,
      math.pi * 0.9,
      false,
      p,
    );
  }
}

void _star(Canvas canvas, Offset c, double r, Color color, double t) {
  _shadedBall(canvas, c, r, color);
  final pulse = 1 + 0.06 * math.sin(t * 4);
  final points = <Offset>[];
  for (var i = 0; i < 10; i++) {
    final a = -math.pi / 2 + i * math.pi / 5;
    final d = r * (i.isEven ? 0.62 : 0.27) * pulse;
    points.add(c + Offset(math.cos(a), math.sin(a)) * d);
  }
  final star = Path()..addPolygon(points, true);
  canvas.drawPath(star, _fill(const Color(0xFFFFE680)));
  canvas.drawPath(
    star,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.05
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFB8860B),
  );
}
