import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';

import 'translations.dart';

/// Translates [key] (the English text) into the app language, filling in
/// [args]. Keys may use `{name}` placeholders and ICU plurals:
/// `{n, plural, one{# round} other{# rounds}}`. Text with no translation
/// falls back to English.
String tr(String key, [Map<String, Object?> args = const {}]) =>
    L10n.translate(key, args);

/// The app language: picked from the phone's languages at startup, or set
/// in Settings.
abstract final class L10n {
  /// Languages the app is being translated into, with their own names.
  static const _names = <String, String>{
    'en': 'English',
    'el': 'Ελληνικά',
    'es': 'Español',
    'pt': 'Português',
    'fr': 'Français',
    'de': 'Deutsch',
    'it': 'Italiano',
    'nl': 'Nederlands',
    'pl': 'Polski',
    'tr': 'Türkçe',
    'ru': 'Русский',
    'id': 'Bahasa Indonesia',
    'hi': 'हिन्दी',
    'ja': '日本語',
    'ko': '한국어',
    'zh': '简体中文',
  };

  /// Supported languages (those with translations), by code, with their
  /// own names.
  static final languages = <String, String>{
    for (final e in _names.entries)
      if (e.key == 'en' || (translations[e.key]?.isNotEmpty ?? false))
        e.key: e.value,
  };

  static List<Locale> get locales => [
    for (final code in languages.keys) Locale(code),
  ];

  static String _lang = 'en';
  static Map<String, String> _table = translations['en']!;

  /// The current language code.
  static String get lang => _lang;

  /// Bumps when the language changes, so the app can rebuild.
  static final changes = ValueNotifier<String>('en');

  /// The first of [system] (the phone's languages, in order of preference)
  /// that the app supports; English if none.
  static String pick(Iterable<Locale>? system) {
    for (final l in system ?? const <Locale>[]) {
      if (languages.containsKey(l.languageCode)) return l.languageCode;
    }
    return 'en';
  }

  /// Switches the app to [code] (unknown codes mean English).
  static void use(String code) {
    if (!languages.containsKey(code)) code = 'en';
    _lang = code;
    _table = {...translations['en']!, ...?translations[code]};
    changes.value = code;
  }

  @visibleForTesting
  static void reset() => use('en');

  static String translate(String key, Map<String, Object?> args) {
    final text = _table[key] ?? key;
    if (args.isEmpty && !text.contains('{')) return text;
    return _format(text, args);
  }

  /// Upper case that suits the language: no accents in Greek capitals and
  /// a dotted capital İ in Turkish.
  static String upper(String s) {
    switch (_lang) {
      case 'el':
        const plain = {
          'ά': 'α',
          'έ': 'ε',
          'ή': 'η',
          'ί': 'ι',
          'ό': 'ο',
          'ύ': 'υ',
          'ώ': 'ω',
          'ΐ': 'ϊ',
          'ΰ': 'ϋ',
          'Ά': 'Α',
          'Έ': 'Ε',
          'Ή': 'Η',
          'Ί': 'Ι',
          'Ό': 'Ο',
          'Ύ': 'Υ',
          'Ώ': 'Ω',
        };
        s = s.split('').map((c) => plain[c] ?? c).join();
      case 'tr':
        s = s.replaceAll('i', 'İ');
    }
    return s.toUpperCase();
  }

  // --- Formatting -----------------------------------------------------------

  static String _format(String text, Map<String, Object?> args) {
    final out = StringBuffer();
    var i = 0;
    while (i < text.length) {
      final c = text[i];
      if (c != '{') {
        out.write(c);
        i++;
        continue;
      }
      final end = _closing(text, i);
      if (end < 0) {
        out.write(text.substring(i));
        break;
      }
      out.write(_placeholder(text.substring(i + 1, end), args));
      i = end + 1;
    }
    return out.toString();
  }

  /// Index of the `}` matching the `{` at [open], or -1.
  static int _closing(String text, int open) {
    var depth = 0;
    for (var i = open; i < text.length; i++) {
      if (text[i] == '{') depth++;
      if (text[i] == '}' && --depth == 0) return i;
    }
    return -1;
  }

  static String _placeholder(String body, Map<String, Object?> args) {
    final comma = body.indexOf(',');
    if (comma < 0) {
      final name = body.trim();
      return args.containsKey(name) ? '${args[name]}' : '{$body}';
    }
    final name = body.substring(0, comma).trim();
    final rest = body.substring(comma + 1).trimLeft();
    if (!rest.startsWith('plural')) return '{$body}';
    final value = args[name];
    final n = value is num ? value : num.tryParse('$value') ?? 0;
    final forms = _forms(rest.substring(rest.indexOf(',') + 1));
    final form =
        forms['=$n'] ?? forms[pluralCategory(_lang, n)] ?? forms['other'] ?? '';
    return _format(form.replaceAll(RegExp(r'#(?!\{)'), '$n'), args);
  }

  /// `one{...} other{...}` -> {'one': ..., 'other': ...}.
  static Map<String, String> _forms(String s) {
    final forms = <String, String>{};
    var i = 0;
    while (i < s.length) {
      final open = s.indexOf('{', i);
      if (open < 0) break;
      final end = _closing(s, open);
      if (end < 0) break;
      forms[s.substring(i, open).trim()] = s.substring(open + 1, end);
      i = end + 1;
    }
    return forms;
  }

  /// CLDR plural category of the whole number [n] in [lang].
  @visibleForTesting
  static String pluralCategory(String lang, num n) {
    final i = n.abs().floor();
    final mod10 = i % 10, mod100 = i % 100;
    switch (lang) {
      case 'ja' || 'ko' || 'zh' || 'id':
        return 'other';
      case 'fr' || 'pt' || 'hi':
        return i <= 1 ? 'one' : 'other';
      case 'ru':
        if (mod10 == 1 && mod100 != 11) return 'one';
        if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
          return 'few';
        }
        return 'many';
      case 'pl':
        if (i == 1) return 'one';
        if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
          return 'few';
        }
        return 'many';
      default:
        return i == 1 ? 'one' : 'other';
    }
  }
}
