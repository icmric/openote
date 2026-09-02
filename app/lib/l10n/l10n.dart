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
