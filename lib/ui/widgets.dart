import 'package:flutter/material.dart';

import '../render/ring_themes.dart';

const coinColor = Color(0xFFFFD54A);

/// Rounded game-style button.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.theme,
    this.icon,
    this.color,
    this.filled = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final RingTheme theme;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final base = color ?? theme.text;
    final fg = filled
        ? (ThemeData.estimateBrightnessForColor(base) == Brightness.dark
              ? Colors.white
              : const Color(0xFF15122A))
        : base;
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: filled ? base : Colors.transparent,
        shape: StadiumBorder(
          side: filled ? BorderSide.none : BorderSide(color: base, width: 2),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: fg),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CoinIcon extends StatelessWidget {
  const CoinIcon({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: coinColor,
        border: Border.all(color: const Color(0xFFE0A800), width: size * 0.14),
      ),
    );
  }
}

class CoinCount extends StatelessWidget {
  const CoinCount({
    super.key,
    required this.coins,
    required this.color,
    this.size = 18,
    this.prefix = '',
  });

  final int coins;
  final Color color;
  final double size;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CoinIcon(size: size),
        SizedBox(width: size * 0.35),
        Text(
          '$prefix$coins',
          style: TextStyle(
            color: color,
            fontSize: size,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
