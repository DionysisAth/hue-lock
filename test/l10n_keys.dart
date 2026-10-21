import 'dart:io';

import 'package:hue_lock/game/game_engine.dart';
import 'package:hue_lock/game/perks.dart';
import 'package:hue_lock/meta/levels.dart';
import 'package:hue_lock/meta/progression.dart';
import 'package:hue_lock/render/ball_skins.dart';
import 'package:hue_lock/render/ring_themes.dart';
import 'package:hue_lock/ui/how_to_play_screen.dart';

final _call = RegExp(
  r'''\btr\(\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")''',
  multiLine: true,
);

String _unescape(String s) => s.replaceAllMapped(
  RegExp(r'\\(.)'),
  (m) => switch (m[1]!) {
    'n' => '\n',
    't' => '\t',
    final c => c,
  },
);

/// Every text the app translates: `tr('...')` calls in lib/ plus the
/// English names kept as data (levels, achievements, perks, skins, ...).
Set<String> translatableKeys() {
  final keys = <String>{};
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    if (f.path.contains(
      '${Platform.pathSeparator}l10n${Platform.pathSeparator}',
    )) {
      continue;
    }
    for (final m in _call.allMatches(f.readAsStringSync())) {
      keys.add(_unescape(m[1] ?? m[2]!));
    }
  }
  keys
    ..addAll(worldNames)
    ..addAll(streakWords.values)
    ..addAll([
      for (final (t, s) in intros.values) ...[t, s],
    ])
    ..addAll(MissionType.values.map((t) => t.text))
    ..addAll([
      for (final p in Perk.values) ...[p.titleEn, p.descriptionEn],
    ])
    ..addAll(ballSkins.map((b) => b.nameEn))
    ..addAll(ringThemes.map((t) => t.nameEn))
    ..addAll([
      for (final a in achievementDefs) ...[a.titleEn, a.descriptionEn],
    ]);
  final levels = parseLevels(
    File('assets/config/levels.json').readAsStringSync(),
  );
  for (final l in levels) {
    keys
      ..add(l.titleEn)
      ..add(l.teachesEn)
      ..add(l.chapterDef.titleEn);
  }
  for (final (title, items) in HowToPlayScreen.sections) {
    keys.add(title);
    for (final (_, _, name, text) in items) {
      keys
        ..add(name)
        ..add(text);
    }
  }
  return keys;
}

/// Placeholder names in [text] (`{n}`, `{n, plural, ...}`), including the
/// ones inside plural forms.
Set<String> placeholders(String text) {
  final out = <String>{};
  int closing(String s, int open) {
    var depth = 0;
    for (var i = open; i < s.length; i++) {
      if (s[i] == '{') depth++;
      if (s[i] == '}' && --depth == 0) return i;
    }
    throw FormatException('Unbalanced braces', s, open);
  }

  void scan(String s) {
    var i = 0;
    while ((i = s.indexOf('{', i)) >= 0) {
      final end = closing(s, i);
      final body = s.substring(i + 1, end);
      final comma = body.indexOf(',');
      if (comma < 0) {
        out.add(body.trim());
      } else {
        out.add(body.substring(0, comma).trim());
        final rest = body.substring(comma + 1);
        final forms = rest.substring(rest.indexOf(',') + 1);
        var j = 0;
        while ((j = forms.indexOf('{', j)) >= 0) {
          final e = closing(forms, j);
          scan(forms.substring(j + 1, e));
          j = e + 1;
        }
      }
      i = end + 1;
    }
  }

  scan(text);
  return out;
}

/// The plural selectors used in [text] (`one`, `few`, `other`, `=1`, ...).
Set<String> pluralForms(String text) => {
  for (final m in RegExp(
    r'(=\d+|zero|one|two|few|many|other)\s*\{',
  ).allMatches(text))
    m[1]!,
};
