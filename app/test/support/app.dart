// One place to build the `MaterialApp` a widget test mounts.
//
// It exists because of translation: `L.of(context)` throws where the
// localisation delegates were never installed, so a test that builds a bare
// `MaterialApp(home: …)` fails the moment the surface under it starts reading
// its words from the .arb rather than from a Dart literal. Rather than adding
// two more lines to forty test files as each surface converts — and finding
// out one at a time which ones were missed — every test mounts through here
// and gets the same delegates the real app installs.
import 'package:flutter/material.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/theme/onote_theme.dart';

/// The app shell a widget test mounts, with the real theme and the real
/// localisation delegates. [locale] forces a language; left null, the test
/// runs in the harness default (English).
Widget testApp(Widget home,
        {Brightness brightness = Brightness.light, Locale? locale}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: onoteTheme(brightness),
      locale: locale,
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      localeListResolutionCallback: onoteResolveLocale,
      home: home,
    );
