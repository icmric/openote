/// The app's translation surface, in one import.
///
/// Everything user-facing should read its words from [L], reached as
/// `L.of(context)`. The English text itself lives in `app_en.arb` beside this
/// file and is the source of truth; `flutter gen-l10n` turns it into
/// `gen/app_localizations.dart`, which is checked in.
///
/// **This is a migration in progress, not a finished job.** Most of the app
/// still holds its words as Dart string literals; the surfaces converted so
/// far are listed in `docs/planning/v0.24-road-to-1.0.md`, and
/// `test/l10n_test.dart` fails if one of them grows a new hardcoded string.
/// Convert a surface at a time, and add its file to that guard when you do.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'gen/app_localizations.dart';

export 'gen/app_localizations.dart' show L;

/// Pass to `MaterialApp.localizationsDelegates`. The Material, widget and
/// Cupertino delegates are what translate the parts of the UI Flutter itself
/// owns — the text-selection menu, the modal barrier's screen-reader label,
/// the date picker — and leaving them out is why a half-translated app shows
/// an English "Paste" inside a Spanish sentence.
const List<LocalizationsDelegate<Object>> kOnoteLocalizations = [
  L.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// Generated from the `.arb` files present, so adding `app_fr.arb` and
/// regenerating is the whole job of adding French — no list to remember to
/// update, and no locale that is offered but has no strings behind it.
const List<Locale> kOnoteLocales = L.supportedLocales;

/// Pick the language, given what the computer asks for.
///
/// **This exists because Flutter's default answer is wrong for us.**
/// `basicLocaleListResolution` matches the OS's preferred languages properly —
/// exact locale, then script, then language — and that part is exactly what is
/// wanted: a Chinese machine gets Chinese with nothing to set up. But when
/// NOTHING matches it returns `supportedLocales.first`, and that list is
/// generated in alphabetical order of the `.arb` files. The first entry is
/// `de`. So an Icelandic student, whose language Openote does not have, was
/// being handed **German** — a language they very likely do not read, chosen
/// because "de" sorts before "en".
///
/// English is the fallback because English is the template every other
/// translation is made from: it is the one language guaranteed to be complete.
Locale onoteResolveLocale(List<Locale>? preferred, Iterable<Locale> supported) {
  final chosen = basicLocaleListResolution(preferred, supported);
  if (preferred == null || preferred.isEmpty) return const Locale('en');
  // `basicLocaleListResolution` returning the first supported locale is how it
  // says "nothing matched" — there is no other signal. Check the answer
  // against what was actually asked for rather than trusting it.
  final asked = preferred.map((l) => l.languageCode).toSet();
  return asked.contains(chosen.languageCode) ? chosen : const Locale('en');
}

/// What each supported language is called **in that language**.
///
/// Not "Spanish" but "Español": somebody looking for their own language is
/// looking for the word they would write it with, and a list that names them
/// all in English is a list they have to translate in their head first.
///
/// Anything in [kOnoteLocales] with no entry here falls back to its own
/// language tag, so adding an `.arb` never leaves a blank row — but do add the
/// name, because a row reading "sv" helps nobody.
const Map<String, String> kLanguageNames = {
  'en': 'English',
  'de': 'Deutsch',
  'es': 'Español',
  'fr': 'Français',
  'it': 'Italiano',
  'pt': 'Português',
  'zh': '中文',
};

/// The name to show for [locale] in the language picker.
String languageNameOf(Locale locale) =>
    kLanguageNames[locale.toLanguageTag()] ??
    kLanguageNames[locale.languageCode] ??
    locale.toLanguageTag();
