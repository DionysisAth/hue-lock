import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_lock/l10n/l10n.dart';
import 'package:hue_lock/l10n/translations.dart';

import 'l10n_keys.dart';

void main() {
  final keys = translatableKeys();
  final en = translations['en']!;

  tearDown(L10n.reset);

  test('catalog for translators', () {
    // build/l10n/catalog.json: every key with its English text.
    final out = File('build/l10n/catalog.json')..createSync(recursive: true);
    final sorted = keys.toList()..sort();
    out.writeAsStringSync(
      const JsonEncoder.withIndent('  ')
          .convert({for (final k in sorted) k: en[k] ?? k}),
    );
    expect(keys.length, greaterThan(300));
  });

  test('English plural forms belong to real keys', () {
    for (final k in en.keys) {
      expect(keys, contains(k));
      expect(placeholders(en[k]!), placeholders(k), reason: k);
    }
  });

  for (final lang in L10n.languages.keys.where((l) => l != 'en')) {
    test('$lang has every text, with the same placeholders', () {
      final table = translations[lang]!;
      final missing = keys.where((k) => !table.containsKey(k)).toList();
      final stale = table.keys.where((k) => !keys.contains(k)).toList();
      expect(missing, isEmpty, reason: '$lang is missing these');
      expect(stale, isEmpty, reason: '$lang has texts the app no longer uses');
      for (final k in keys) {
        final t = table[k]!;
        expect(placeholders(t), placeholders(k), reason: '$lang: $k');
        expect(t.trim(), isNotEmpty, reason: '$lang: $k');
        if (pluralForms(t).isNotEmpty) {
          expect(pluralForms(t), contains('other'), reason: '$lang: $k');
        }
      }
    });

    test('$lang formats every text cleanly', () {
      L10n.use(lang);
      for (final k in keys) {
        final args = {for (final p in placeholders(k)) p: 7};
        for (final n in [0, 1, 2, 5, 11, 22]) {
          if (args.containsKey('n')) args['n'] = n;
          final s = tr(k, args);
          expect(s, isNot(contains('{')), reason: '$lang: $k -> $s');
          expect(s, isNot(contains('}')), reason: '$lang: $k -> $s');
        }
      }
    });
  }

  test('plural rules', () {
    String f(String lang, int n) {
      L10n.use(lang);
      return L10n.pluralCategory(lang, n);
    }

    expect(f('en', 1), 'one');
    expect(f('en', 0), 'other');
    expect(f('fr', 0), 'one');
    expect(f('ru', 21), 'one');
    expect(f('ru', 3), 'few');
    expect(f('ru', 12), 'many');
    expect(f('pl', 22), 'few');
    expect(f('pl', 5), 'many');
    expect(f('ja', 1), 'other');
  });

  test('formatting', () {
    L10n.use('en');
    expect(tr('Hit {n} gold zones', {'n': 1}), 'Hit a gold zone');
    expect(tr('Hit {n} gold zones', {'n': 3}), 'Hit 3 gold zones');
    expect(tr('BEST {n}', {'n': 12}), 'BEST 12');
    expect(tr('not a key'), 'not a key');
    expect(
      tr('{n} points to pass {name} (#{rank})', {
        'n': 1,
        'name': 'Ana',
        'rank': 4,
      }),
      '1 point to pass Ana (#4)',
    );
    expect(
      tr('{hits} hits · {perfects} Perfects', {'hits': 1, 'perfects': 3}),
      '1 hit · 3 Perfects',
    );
    if (L10n.languages.containsKey('el')) {
      L10n.use('el');
      expect(L10n.upper('Άλμα ή όχι'), 'ΑΛΜΑ Η ΟΧΙ');
    }
    if (L10n.languages.containsKey('tr')) {
      L10n.use('tr');
      expect(L10n.upper('istif'), 'İSTİF');
    }
  });

  test('the phone language is picked when supported', () {
    for (final code in L10n.languages.keys) {
      expect(L10n.pick([Locale(code, 'XX')]), code);
      expect(L10n.pick([const Locale('sv'), Locale(code)]), code);
    }
    expect(L10n.pick(const [Locale('sv')]), 'en');
    expect(L10n.pick(null), 'en');
  });
}
