import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../meta/progression.dart';
import '../render/ball_skins.dart';
import '../render/palette.dart';
import '../render/ring_themes.dart';
import '../services/feedback.dart';
import 'hud.dart';
import 'mode_dialogs.dart';
import 'widgets.dart';

/// Player level, daily reward, missions, achievements and lifetime stats.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    return ListenableBuilder(
      listenable: s.profile,
      builder: (context, _) {
        final p = s.profile.profile;
        final theme = ringThemeById(p.theme);
        final level = levelForXp(p.xp);
        final (into, size) = levelProgress(p.xp);
        final now = DateTime.now();
        final rewardReady = canClaimDailyReward(p, now);
        final missions = missionsOf(p);
        final next = rewardForLevel(level + 1);
        TextStyle body([double size = 15]) => TextStyle(
          color: theme.text,
          fontSize: size,
          fontWeight: FontWeight.w700,
        );

        Widget card(Widget child) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.text.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
          ),
          child: child,
        );

        return Scaffold(
          backgroundColor: theme.bgBottom,
          appBar: AppBar(
            backgroundColor: theme.bgTop,
            foregroundColor: theme.text,
            title: Text(
              tr('PROGRESS'),
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3),
            ),
            actions: [
              if (s.gameServices.signedIn)
                IconButton(
                  tooltip: tr('Achievements'),
                  onPressed: s.gameServices.showAchievements,
                  icon: const Icon(Icons.military_tech_rounded),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('PLAYER LEVEL {n}', {'n': level}), style: body(18)),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: size == 0 ? 0 : into / size,
                        minHeight: 8,
                        color: HuePalette.standard[3],
                        backgroundColor: theme.text.withValues(alpha: 0.12),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr('{into} / {size} XP · next: {reward}', {
                        'into': into,
                        'size': size,
                        'reward': _rewardText(next),
                      }),
                      style: hudLabel(theme, size: 12),
                    ),
                  ],
                ),
              ),
              card(
                Row(
                  children: [
                    Icon(
                      Icons.card_giftcard_rounded,
                      color: HuePalette.standard[2],
                      size: 30,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('DAILY REWARD'), style: body()),
                          Text(
                            rewardReady
                                ? tr('Day {n} of 7 is ready', {
                                    'n': nextDailyReward(p, now).day,
                                  })
                                : tr('Streak: {n} days. Come back tomorrow', {
                                    'n': p.rewardStreak,
                                  }),
                            style: hudLabel(theme, size: 12),
                          ),
                        ],
                      ),
                    ),
                    if (rewardReady)
                      PillButton(
                        label: tr('CLAIM'),
                        theme: theme,
                        color: HuePalette.standard[2],
                        onPressed: () async {
                          DailyReward? reward;
                          s.profile.update(
                            (p) => reward = claimDailyReward(p, DateTime.now()),
                          );
                          if (reward == null) return;
                          s.audio.play(Sfx.coin);
                          await showDailyRewardDialog(
                            context,
                            theme: theme,
                            reward: reward!,
                          );
                        },
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
                child: Text(tr('MISSIONS'), style: hudLabel(theme, size: 13)),
              ),
              for (var i = 0; i < missions.length; i++)
                card(
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(missions[i].title, style: body()),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value:
                                    (missions[i].progress / missions[i].target)
                                        .clamp(0.0, 1.0),
                                minHeight: 6,
                                color: HuePalette.standard[1],
                                backgroundColor: theme.text.withValues(
                                  alpha: 0.12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${missions[i].progress.clamp(0, missions[i].target)} / ${missions[i].target}',
                              style: hudLabel(theme, size: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      missions[i].done
                          ? PillButton(
                              label: '+${missions[i].coins}',
                              icon: Icons.monetization_on_rounded,
                              theme: theme,
                              color: coinColor,
                              onPressed: () {
                                Mission? m;
                                s.profile.update((p) {
                                  m = claimMission(p, i);
                                  if (m != null) p.xp += m!.xp;
                                });
                                if (m != null) s.audio.play(Sfx.coin);
                              },
                            )
                          : CoinCount(
                              coins: missions[i].coins,
                              color: theme.subtleText,
                              size: 15,
                            ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
                child: Text(
                  tr('ACHIEVEMENTS {n} / {total}', {
                    'n': p.achievements.length,
                    'total': achievementDefs.length,
                  }),
                  style: hudLabel(theme, size: 13),
                ),
              ),
              for (final a in achievementDefs)
                Opacity(
                  opacity: p.achievements.contains(a.id) ? 1 : 0.45,
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      p.achievements.contains(a.id)
                          ? Icons.emoji_events_rounded
                          : Icons.lock_outline_rounded,
                      color: p.achievements.contains(a.id)
                          ? coinColor
                          : theme.subtleText,
                    ),
                    title: Text(a.title, style: body(14)),
                    subtitle: Text(
                      a.description,
                      style: TextStyle(color: theme.subtleText),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
                child: Text(tr('STATS'), style: hudLabel(theme, size: 13)),
              ),
              card(
                Column(
                  children: [
                    for (final (label, value) in [
                      (tr('Best score'), p.bestScore),
                      (tr('Runs played'), p.stat(Stat.runs)),
                      (tr('Rounds cleared'), p.stat(Stat.rounds)),
                      (tr('Perfects'), p.stat(Stat.perfects)),
                      (tr('Best Perfect streak'), p.stat(Stat.bestStreak)),
                      (tr('Bosses beaten'), p.stat(Stat.bosses)),
                      (tr('Fevers'), p.stat(Stat.fevers)),
                      (tr('Best combo'), p.stat(Stat.bestCombo)),
                      (tr('Furthest stage'), p.stat(Stat.bestStage)),
                      (tr('Duels won'), p.stat(Stat.duelsWon)),
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(color: theme.subtleText),
                              ),
                            ),
                            Text('$value', style: body(14)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _rewardText(LevelReward r) {
    final parts = <String>[
      if (r.coins > 0) tr('{n} coins', {'n': r.coins}),
      if (r.tokens > 0) tr('{n} tokens', {'n': r.tokens}),
      if (r.ball != null)
        tr('{name} ball', {'name': ballSkinById(r.ball!).name}),
      if (r.theme != null)
        tr('{name} ring', {'name': ringThemeById(r.theme!).name}),
    ];
    return parts.join(' + ');
  }
}
