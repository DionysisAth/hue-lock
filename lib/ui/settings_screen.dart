import 'package:flutter/material.dart';

import '../app.dart';
import '../render/ring_themes.dart';
import '../services/purchase_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s.profile, s.purchases, s.gameServices]),
      builder: (context, _) {
        final p = s.profile.profile;
        final theme = ringThemeById(p.theme);
        final text = TextStyle(color: theme.text, fontWeight: FontWeight.w700);
        final sub = TextStyle(color: theme.subtleText);
        final price = s.purchases.priceOf(Products.removeAds);
        return Scaffold(
          backgroundColor: theme.bgBottom,
          appBar: AppBar(
            backgroundColor: theme.bgTop,
            foregroundColor: theme.text,
            title: const Text(
              'SETTINGS',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              SwitchListTile(
                title: Text('Sound', style: text),
                value: p.sound,
                onChanged: (v) => s.profile.update((p) => p.sound = v),
              ),
              ListTile(
                title: Text('Sound volume', style: text),
                subtitle: Slider(
                  value: p.volume,
                  onChanged: p.sound
                      ? (v) => s.profile.update((p) => p.volume = v)
                      : null,
                ),
              ),
              SwitchListTile(
                title: Text('Music', style: text),
                subtitle: Text('Builds up as your run heats up', style: sub),
                value: p.music,
                onChanged: (v) => s.profile.update((p) => p.music = v),
              ),
              ListTile(
                title: Text('Music volume', style: text),
                subtitle: Slider(
                  value: p.musicVolume,
                  onChanged: p.music
                      ? (v) => s.profile.update((p) => p.musicVolume = v)
                      : null,
                ),
              ),
              SwitchListTile(
                title: Text('Haptics', style: text),
                subtitle: Text('Vibrate on hits', style: sub),
                value: p.haptics,
                onChanged: (v) => s.profile.update((p) => p.haptics = v),
              ),
              SwitchListTile(
                title: Text('Daily reminder', style: text),
                subtitle: Text(
                  'A notification when a new Daily Challenge is live',
                  style: sub,
                ),
                value: p.dailyReminder,
                onChanged: s.reminders.enabled
                    ? (v) async {
                        final on = await s.reminders.setDailyReminder(v);
                        s.profile.update((p) => p.dailyReminder = on);
                      }
                    : null,
              ),
              if (s.gameServices.enabled)
                ListTile(
                  leading: Icon(
                    Icons.sports_esports_rounded,
                    color: theme.text,
                  ),
                  title: Text(
                    s.gameServices.signedIn
                        ? 'Signed in as ${s.gameServices.playerName ?? 'player'}'
                        : 'Sign in to save progress online',
                    style: text,
                  ),
                  subtitle: Text(
                    'Leaderboards, achievements and cloud save',
                    style: sub,
                  ),
                  onTap: s.gameServices.signedIn
                      ? null
                      : () => s.gameServices.signIn(),
                ),
              SwitchListTile(
                title: Text('Colorblind mode', style: text),
                subtitle: Text(
                  'Colorblind-safe colors plus a symbol on every color',
                  style: sub,
                ),
                value: p.colorblind,
                onChanged: (v) => s.profile.update((p) => p.colorblind = v),
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.block_rounded, color: theme.text),
                title: Text(
                  p.adsRemoved ? 'Ads removed - thank you!' : 'Remove ads',
                  style: text,
                ),
                subtitle: Text(
                  p.adsRemoved
                      ? 'Optional reward videos stay available'
                      : 'No more interstitial ads${price != null ? ' ($price)' : ''}',
                  style: sub,
                ),
                enabled: !p.adsRemoved && s.purchases.storeAvailable,
                onTap: () => s.purchases.buy(Products.removeAds),
              ),
              ListTile(
                leading: Icon(Icons.restore_rounded, color: theme.text),
                title: Text('Restore purchases', style: text),
                enabled: s.purchases.storeAvailable,
                onTap: () => s.purchases.restore(),
              ),
              if (s.purchases.lastError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    s.purchases.lastError!,
                    style: const TextStyle(color: Color(0xFFFF6B6B)),
                  ),
                ),
              if (s.ads.privacyOptionsRequired)
                ListTile(
                  leading: Icon(Icons.privacy_tip_rounded, color: theme.text),
                  title: Text('Privacy options', style: text),
                  onTap: () => s.ads.showPrivacyOptions(),
                ),
              const Divider(),
              ListTile(
                title: Text('Best score', style: text),
                trailing: Text('${p.bestScore}', style: text),
              ),
              ListTile(
                title: Text('Runs played', style: text),
                trailing: Text('${p.totalRuns}', style: text),
              ),
            ],
          ),
        );
      },
    );
  }
}
