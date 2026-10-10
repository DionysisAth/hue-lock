import 'dart:ui';

/// A ring theme. Every theme must keep zones clearly readable: zone colors
/// come from the palette, never from the theme.
class RingTheme {
  const RingTheme({
    required this.id,
    required this.name,
    required this.price,
    required this.bgTop,
    required this.bgBottom,
    required this.ringNeutral,
    required this.pointer,
    required this.text,
    required this.subtleText,
    required this.glowStrength,
    required this.ringWidth,
    this.zoneOutline,
    this.outerHalo,
    this.dark = true,
  });

  final String id;
  final String name;
  final int price;
  final Color bgTop;
  final Color bgBottom;
  final Color ringNeutral;
  final Color pointer;
  final Color text;
  final Color subtleText;

  /// 0..1, how much zones and combos glow.
  final double glowStrength;

  /// Ring thickness as a fraction of the ring radius.
  final double ringWidth;

  /// Outline drawn around zones (light themes need it for contrast).
  final Color? zoneOutline;

  /// Thin decorative ring outside the main ring.
  final Color? outerHalo;
  final bool dark;
}

const ringThemes = <RingTheme>[
  RingTheme(
    id: 'classic',
    name: 'Minimal',
    price: 0,
    bgTop: Color(0xFF1A1B33),
    bgBottom: Color(0xFF0B0C18),
    ringNeutral: Color(0xFF353857),
    pointer: Color(0xFFFFFFFF),
    text: Color(0xFFFFFFFF),
    subtleText: Color(0xFF9A9CC0),
    glowStrength: 0.55,
    ringWidth: 0.15,
  ),
  RingTheme(
    id: 'neon',
    name: 'Neon',
    price: 400,
    bgTop: Color(0xFF12002B),
    bgBottom: Color(0xFF020008),
    ringNeutral: Color(0xFF2B2445),
    pointer: Color(0xFFE6FFFF),
    text: Color(0xFFE6FFFF),
    subtleText: Color(0xFFB08CFF),
    glowStrength: 1.0,
    ringWidth: 0.12,
    outerHalo: Color(0xFF00F0FF),
  ),
  RingTheme(
    id: 'candy',
    name: 'Candy',
    price: 600,
    bgTop: Color(0xFFFFEEF5),
    bgBottom: Color(0xFFE6EEFF),
    ringNeutral: Color(0xFFD8CFE3),
    pointer: Color(0xFF34264A),
    text: Color(0xFF34264A),
    subtleText: Color(0xFF7D6C96),
    glowStrength: 0.3,
    ringWidth: 0.19,
    zoneOutline: Color(0x6634264A),
    dark: false,
  ),
  // Levels map chapter rewards (price -2: not sold).
  RingTheme(
    id: 'sunset',
    name: 'Sunset',
    price: -2,
    bgTop: Color(0xFF3A1240),
    bgBottom: Color(0xFF120618),
    ringNeutral: Color(0xFF4A2A52),
    pointer: Color(0xFFFFF1D6),
    text: Color(0xFFFFF1D6),
    subtleText: Color(0xFFFFA97A),
    glowStrength: 0.8,
    ringWidth: 0.14,
    outerHalo: Color(0xFFFF8A4C),
  ),
  RingTheme(
    id: 'ocean',
    name: 'Deep Sea',
    price: -2,
    bgTop: Color(0xFF06324A),
    bgBottom: Color(0xFF020F1A),
    ringNeutral: Color(0xFF1C4560),
    pointer: Color(0xFFE0FBFF),
    text: Color(0xFFE0FBFF),
    subtleText: Color(0xFF7FC8E0),
    glowStrength: 0.75,
    ringWidth: 0.16,
    outerHalo: Color(0xFF3DE0FF),
  ),
];

RingTheme ringThemeById(String id) =>
    ringThemes.firstWhere((t) => t.id == id, orElse: () => ringThemes.first);
