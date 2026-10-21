import 'translations/de.dart';
import 'translations/el.dart';
import 'translations/en.dart';
import 'translations/es.dart';
import 'translations/fr.dart';
import 'translations/hi.dart';
import 'translations/id.dart';
import 'translations/it.dart';
import 'translations/ja.dart';
import 'translations/ko.dart';
import 'translations/nl.dart';
import 'translations/pl.dart';
import 'translations/pt.dart';
import 'translations/ru.dart';
import 'translations/tr.dart';
import 'translations/zh.dart';

/// Every language's text, keyed by the English text. English itself only
/// lists plural forms; anything missing falls back to the English key.
const translations = <String, Map<String, String>>{
  'en': textEn,
  'el': textEl,
  'es': textEs,
  'pt': textPt,
  'fr': textFr,
  'de': textDe,
  'it': textIt,
  'nl': textNl,
  'pl': textPl,
  'tr': textTr,
  'ru': textRu,
  'id': textId,
  'hi': textHi,
  'ja': textJa,
  'ko': textKo,
  'zh': textZh,
};
