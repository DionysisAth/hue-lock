import 'package:flutter/material.dart';

import '../app.dart';
import '../meta/progression.dart';
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
            title: const Text(
              'PROGRESS',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3),
            ),
            actions: [
              if (s.gameServices.signedIn)
                IconButton(
                  tooltip: 'Achievements',
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
                    Text('PLAYER LEVEL $level', style: body(18)),
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
                      '$into / $size XP · next: ${_rewardText(next)}',
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
                          Text('DAILY REWARD', style: body()),
                          Text(
                            rewardReady
                                ? 'Day ${nextDailyReward(p, now).day} of 7 is ready'
                                : 'Streak: ${p.rewardStreak} day${p.rewardStreak == 1 ? '' : 's'}. Come back tomorrow',
                            style: hudLabel(theme, size: 12),
                          ),
                        ],
                      ),
                    ),
                    if (rewardReady)
                      PillButton(
                        label: 'CLAIM',
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
                child: Text('MISSIONS', style: hudLabel(theme, size: 13)),
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
                  'ACHIEVEMENTS ${p.achievements.length} / ${achievementDefs.length}',
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
                child: Text('STATS', style: hudLabel(theme, size: 13)),
              ),
              card(
                Column(
                  children: [
                    for (final (label, value) in [
                      ('Best score', p.bestScore),
                      ('Runs played', p.stat(Stat.runs)),
                      ('Rounds cleared', p.stat(Stat.rounds)),
                      ('Perfects', p.stat(Stat.perfects)),
                      ('Best Perfect streak', p.stat(Stat.bestStreak)),
                      ('Bosses beaten', p.stat(Stat.bosses)),
                      ('Fevers', p.stat(Stat.fevers)),
                      ('Best combo', p.stat(Stat.bestCombo)),
                      ('Furthest stage', p.stat(Stat.bestStage)),
                      ('Duels won', p.stat(Stat.duelsWon)),
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
      if (r.coins > 0) '${r.coins} coins',
      if (r.tokens > 0) '${r.tokens} tokens',
      if (r.ball != null) '${r.ball} ball',
      if (r.theme != null) '${r.theme} ring',
    ];
    return parts.join(' + ');
  }
}
