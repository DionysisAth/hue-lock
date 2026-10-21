import 'package:flutter/material.dart';

import '../game/game_engine.dart';
import '../l10n/l10n.dart';
import '../render/palette.dart';
import '../render/ring_themes.dart';
import 'widgets.dart';

/// Small round pause button for the top-left corner during a run.
class PauseButton extends StatelessWidget {
  const PauseButton({super.key, required this.theme, required this.onPressed});

  final RingTheme theme;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tr('Pause'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.bgTop.withValues(alpha: 0.7),
              border: Border.all(
                color: theme.text.withValues(alpha: 0.25),
                width: 1.5,
              ),
            ),
            child: Icon(Icons.pause_rounded, color: theme.text, size: 24),
          ),
        ),
      ),
    );
  }
}

/// The pause menu: the run stands still behind it until RESUME; QUIT ends
/// the run and goes home (coins and progress so far are kept).
class PauseOverlay extends StatelessWidget {
  const PauseOverlay({
    super.key,
    required this.engine,
    required this.theme,
    required this.onResume,
    required this.onQuit,
  });

  final GameEngine engine;
  final RingTheme theme;
  final VoidCallback onResume;
  final VoidCallback onQuit;

  String get _quitNote => switch (engine.mode) {
    RunMode.zen => tr('Your Zen session ends.'),
    RunMode.level => tr('The level ends without stars.'),
    RunMode.daily => tr('This attempt ends with your score so far.'),
    _ => tr('The run ends with your score so far.'),
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Swallow taps so nothing reaches the game behind.
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: ColoredBox(
        color: theme.bgBottom.withValues(alpha: 0.82),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.pause_circle_filled_rounded,
                  size: 56,
                  color: theme.text.withValues(alpha: 0.9),
                ),
                const SizedBox(height: 10),
                Text(
                  tr('PAUSED'),
                  style: TextStyle(
                    color: theme.text,
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                  ),
                ),
                const SizedBox(height: 28),
                PillButton(
                  label: tr('RESUME'),
                  icon: Icons.play_arrow_rounded,
                  theme: theme,
                  color: HuePalette.standard[3],
                  onPressed: onResume,
                ),
                const SizedBox(height: 12),
                PillButton(
                  label: engine.mode == RunMode.zen
                      ? tr('END ZEN')
                      : tr('QUIT'),
                  icon: Icons.home_rounded,
                  theme: theme,
                  filled: false,
                  onPressed: onQuit,
                ),
                const SizedBox(height: 12),
                Text(
                  _quitNote,
                  style: TextStyle(
                    color: theme.subtleText,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
