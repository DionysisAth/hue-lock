import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// A piece of effect text rasterized once to an image.
///
/// Laying out and drawing glowing text every frame (with a fade, a pop or a
/// growing font size) costs a paragraph layout, a blur pass and new glyph
/// atlas entries on every frame. A sprite is drawn as a plain image instead:
/// fading and scaling it is free.
class TextSprite {
  TextSprite._(this.image, this.size, this.pixelRatio, this.pad);

  final ui.Image image;

  /// Logical size of [image], including [pad] on every side for the glow.
  final Size size;
  final double pixelRatio;
  final double pad;

  /// Logical size of the text itself.
  double get textWidth => size.width - pad * 2;
  double get textHeight => size.height - pad * 2;

  /// Draws the text with its top center at [topCenter] (the top stays put
  /// when [scale] grows it, like a bigger font would), at [opacity].
  void paint(
    Canvas canvas,
    Offset topCenter, {
    double scale = 1,
    double opacity = 1,
  }) {
    if (opacity <= 0 || scale <= 0) return;
    final center = topCenter + Offset(0, textHeight * scale / 2);
    final w = size.width * scale;
    final h = size.height * scale;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromCenter(center: center, width: w, height: h),
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0))
        ..filterQuality = FilterQuality.medium,
    );
  }
}

/// Small LRU cache of [TextSprite]s ("PERFECT x3", streak words, banners).
abstract final class TextSprites {
  static const _capacity = 64;

  /// Font for canvas text; null = the platform default (what the app uses).
  /// The screenshot tool sets it, since tests have no platform font.
  static String? fontFamily;
  static final _cache = <String, TextSprite>{}; // insertion-ordered

  static TextSprite get(
    String text, {
    required Color color,
    required double fontSize,
    double letterSpacing = 2,
    FontWeight weight = FontWeight.w900,
    double glow = 0,
    double glowAlpha = 0.6,
    double pixelRatio = 2,
  }) {
    final key = [
      text,
      color.toARGB32(),
      fontSize,
      letterSpacing,
      weight.value,
      glow,
      glowAlpha,
      pixelRatio,
    ].join('|');
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit; // most recently used
      return hit;
    }
    final sprite = _render(
      text,
      TextStyle(
        fontFamily: fontFamily,
        color: color,
        fontSize: fontSize,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        shadows: glow > 0
            ? [
                Shadow(
                  color: color.withValues(alpha: glowAlpha),
                  blurRadius: glow,
                ),
              ]
            : null,
      ),
      pad: glow * 1.5 + 2,
      pixelRatio: pixelRatio,
    );
    _cache[key] = sprite;
    while (_cache.length > _capacity) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest)!.image.dispose();
    }
    return sprite;
  }

  static TextSprite _render(
    String text,
    TextStyle style, {
    required double pad,
    required double pixelRatio,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final size = Size(tp.width + pad * 2, tp.height + pad * 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    tp.paint(canvas, Offset(pad, pad));
    tp.dispose();
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      math.max(1, (size.width * pixelRatio).ceil()),
      math.max(1, (size.height * pixelRatio).ceil()),
    );
    picture.dispose();
    return TextSprite._(image, size, pixelRatio, pad);
  }

  /// Frees every cached image (tests, theme changes).
  static void clear() {
    for (final s in _cache.values) {
      s.image.dispose();
    }
    _cache.clear();
  }
}
