import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../meta/progression.dart';
import '../render/palette.dart';
import '../render/ring_themes.dart';
import 'widgets.dart';

enum DailyChoice { play, watchAd, leaderboard }

/// Daily Challenge: everyone gets the same run today.
Future<DailyChoice?> showDailyDialog(
  BuildContext context, {
  required RingTheme theme,
  required String day,
  required int attemptsLeft,
  required int best,
  required bool adReady,
  required bool leaderboards,
}) {
  return showDialog<DailyChoice>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: theme.bgTop,
      title: Text(
        'DAILY CHALLENGE #${dailyNumber(day)}',
        style: TextStyle(color: theme.text, fontWeight: FontWeight.w900),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Everyone plays the same run today. No continues.',
            style: TextStyle(color: theme.text, height: 1.35),
          ),
          const SizedBox(height: 12),
          Text(
            'Today\'s best: $best',
            style: TextStyle(color: theme.text, fontWeight: FontWeight.w800),
          ),
          Text(
            attemptsLeft > 0
                ? '$attemptsLeft attempt${attemptsLeft == 1 ? '' : 's'} left'
                : 'No attempts left today',
            style: TextStyle(color: theme.subtleText),
          ),
        ],
      ),
      actions: [
        if (leaderboards)
          IconButton(
            tooltip: 'Leaderboard',
            onPressed: () => Navigator.pop(context, DailyChoice.leaderboard),
            icon: const Icon(Icons.leaderboard_rounded),
          ),
        if (attemptsLeft <= 0)
          FilledButton.icon(
            onPressed: adReady
                ? () => Navigator.pop(context, DailyChoice.watchAd)
                : null,
            icon: const Icon(Icons.play_circle_fill_rounded),
            label: const Text('ONE MORE TRY'),
          )
        else
          FilledButton(
            onPressed: () => Navigator.pop(context, DailyChoice.play),
            child: const Text('PLAY'),
          ),
      ],
    ),
  );
}

/// Enter a friend's duel code. Returns (seed, score to beat).
Future<(int, int)?> showDuelDialog(
  BuildContext context, {
  required RingTheme theme,
}) {
  final controller = TextEditingController();
  String? error;
  return showDialog<(int, int)>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        void submit() {
          final decoded = DuelCode.decode(controller.text);
          if (decoded == null) {
            setState(() => error = 'That code doesn\'t look right');
            return;
          }
          Navigator.pop(context, decoded);
        }

        return AlertDialog(
          backgroundColor: theme.bgTop,
          title: Text(
            'FRIEND DUEL',
            style: TextStyle(color: theme.text, fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the code a friend sent you. You play exactly their '
                'run and have to beat their score.\n\nTo challenge someone, '
                'finish a run and tap CHALLENGE A FRIEND.',
                style: TextStyle(color: theme.text, height: 1.35),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9-]')),
                ],
                style: TextStyle(
                  color: theme.text,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
                decoration: InputDecoration(
                  hintText: 'HL-XXXXXXXXXXXX',
                  errorText: error,
                ),
                onSubmitted: (_) => submit(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final data = await Clipboard.getData('text/plain');
                final text = data?.text ?? '';
                final match = RegExp(r'HL-?[0-9A-Za-z]{12}').firstMatch(text);
                if (match != null) controller.text = match.group(0)!;
              },
              child: const Text('Paste'),
            ),
            FilledButton(onPressed: submit, child: const Text('PLAY')),
          ],
        );
      },
    ),
  );
}

/// Daily login reward with the 7-day streak track.
Future<void> showDailyRewardDialog(
  BuildContext context, {
  required RingTheme theme,
  required DailyReward reward,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: theme.bgTop,
      title: Text(
        'DAILY REWARD',
        style: TextStyle(color: theme.text, fontWeight: FontWeight.w900),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final r in dailyRewards)
                Container(
                  margin: const EdgeInsets.all(2),
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: r.day <= reward.day
                        ? HuePalette.standard[3]
                        : theme.text.withValues(alpha: 0.12),
                  ),
                  child: Text(
                    '${r.day}',
                    style: TextStyle(
                      color: r.day <= reward.day ? Colors.black : theme.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Day ${reward.day} streak!',
            style: TextStyle(color: theme.text, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CoinCount(coins: reward.coins, color: theme.text, prefix: '+'),
              if (reward.tokens > 0) ...[
                const SizedBox(width: 14),
                Icon(
                  Icons.confirmation_number_rounded,
                  color: HuePalette.standard[3],
                ),
                Text(
                  ' +${reward.tokens}',
                  style: TextStyle(
                    color: theme.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Come back tomorrow to keep the streak.',
            style: TextStyle(color: theme.subtleText),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('COLLECT'),
        ),
      ],
    ),
  );
}
