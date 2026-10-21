import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../config/links.dart';
import '../l10n/l10n.dart';
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
            title: Text(
              tr('SETTINGS'),
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 3),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              ListTile(
                leading: Icon(Icons.language_rounded, color: theme.text),
                title: Text(tr('Language'), style: text),
                subtitle: Text(
                  p.language.isEmpty
                      ? '${tr('Phone language')} · ${L10n.languages[L10n.lang]}'
                      : L10n.languages[L10n.lang]!,
                  style: sub,
                ),
                onTap: () async {
                  final code = await showLanguagePicker(
                    context,
                    current: p.language,
                    theme: theme,
                  );
                  if (code != null) {
                    s.profile.update((p) => p.language = code);
                  }
                },
              ),
              SwitchListTile(
                title: Text(tr('Sound'), style: text),
                value: p.sound,
                onChanged: (v) => s.profile.update((p) => p.sound = v),
              ),
              ListTile(
                title: Text(tr('Sound volume'), style: text),
                subtitle: Slider(
                  value: p.volume,
                  onChanged: p.sound
                      ? (v) => s.profile.update((p) => p.volume = v)
                      : null,
                ),
              ),
              SwitchListTile(
                title: Text(tr('Music'), style: text),
                subtitle: Text(
                  tr('Builds up as your run heats up'),
                  style: sub,
                ),
                value: p.music,
                onChanged: (v) => s.profile.update((p) => p.music = v),
              ),
              ListTile(
                title: Text(tr('Music volume'), style: text),
                subtitle: Slider(
                  value: p.musicVolume,
                  onChanged: p.music
                      ? (v) => s.profile.update((p) => p.musicVolume = v)
                      : null,
                ),
              ),
              SwitchListTile(
                title: Text(tr('Haptics'), style: text),
                subtitle: Text(tr('Vibrate on hits'), style: sub),
                value: p.haptics,
                onChanged: (v) => s.profile.update((p) => p.haptics = v),
              ),
              SwitchListTile(
                title: Text(tr('Daily reminder'), style: text),
                subtitle: Text(
                  tr('A notification when a new Daily Challenge is live'),
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
                        ? tr('Signed in as {name}', {
                            'name': s.gameServices.playerName ?? tr('player'),
                          })
                        : tr('Sign in to save progress online'),
                    style: text,
                  ),
                  subtitle: Text(
                    s.gameServices.lastCloudSave != null
                        ? tr(
                            'Progress saved to the cloud at {time}. Tap to sync now.',
                            {
                              'time': TimeOfDay.fromDateTime(
                                s.gameServices.lastCloudSave!,
                              ).format(context),
                            },
                          )
                        : tr('Leaderboards, achievements and cloud save'),
                    style: sub,
                  ),
                  onTap: s.syncCloud,
                ),
              SwitchListTile(
                title: Text(tr('Colorblind mode'), style: text),
                subtitle: Text(
                  tr('Colorblind-safe colors plus a symbol on every color'),
                  style: sub,
                ),
                value: p.colorblind,
                onChanged: (v) => s.profile.update((p) => p.colorblind = v),
              ),
              SwitchListTile(
                title: Text(tr('Focus button on the left'), style: text),
                subtitle: Text(
                  tr('For playing with your left thumb'),
                  style: sub,
                ),
                value: p.focusLeft,
                onChanged: (v) => s.profile.update((p) => p.focusLeft = v),
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.block_rounded, color: theme.text),
                title: Text(
                  p.adsRemoved
                      ? tr('Ads removed - thank you!')
                      : tr('Remove ads'),
                  style: text,
                ),
                subtitle: Text(
                  p.adsRemoved
                      ? tr('Optional reward videos stay available')
                      : [
                          tr('No more interstitial ads'),
                          if (price != null) '($price)',
                        ].join(' '),
                  style: sub,
                ),
                enabled: !p.adsRemoved && s.purchases.storeAvailable,
                onTap: () => s.purchases.buy(Products.removeAds),
              ),
              ListTile(
                leading: Icon(Icons.restore_rounded, color: theme.text),
                title: Text(tr('Restore purchases'), style: text),
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
                  title: Text(tr('Privacy options'), style: text),
                  onTap: () => s.ads.showPrivacyOptions(),
                ),
              ListTile(
                leading: Icon(Icons.policy_rounded, color: theme.text),
                title: Text(tr('Privacy policy'), style: text),
                trailing: Icon(Icons.open_in_new_rounded, color: theme.text),
                onTap: () => launchUrl(
                  Uri.parse(Links.privacyPolicy),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              ListTile(
                leading: Icon(Icons.mail_outline_rounded, color: theme.text),
                title: Text(tr('Contact us'), style: text),
                subtitle: Text(
                  Links.contactEmail,
                  style: TextStyle(color: theme.subtleText),
                ),
                onTap: () => launchUrl(
                  Uri(
                    scheme: 'mailto',
                    path: Links.contactEmail,
                    query: 'subject=Hue%20Lock',
                  ),
                ),
              ),
              const Divider(),
              ListTile(
                title: Text(tr('Best score'), style: text),
                trailing: Text('${p.bestScore}', style: text),
              ),
              ListTile(
                title: Text(tr('Runs played'), style: text),
                trailing: Text('${p.totalRuns}', style: text),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Lets the player pick the app language; '' = the phone's language.
/// Returns the chosen code, or null if dismissed.
Future<String?> showLanguagePicker(
  BuildContext context, {
  required String current,
  required RingTheme theme,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      backgroundColor: theme.bgTop,
      title: Text(
        tr('Language'),
        style: TextStyle(color: theme.text, fontWeight: FontWeight.w900),
      ),
      children: [
        for (final (code, name) in [
          ('', tr('Phone language')),
          ...L10n.languages.entries.map((e) => (e.key, e.value)),
        ])
          ListTile(
            title: Text(name, style: TextStyle(color: theme.text)),
            trailing: code == current
                ? Icon(Icons.check_rounded, color: theme.text)
                : null,
            onTap: () => Navigator.of(context).pop(code),
          ),
      ],
    ),
  );
}
