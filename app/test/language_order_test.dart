// The order the language picker offers languages in.
//
// The owner: "If we could organise the language list by the language names in
// english that would be great, they do feel a bit random now."
//
// They were in `supportedLocales` order, which is whatever the `.arb` files
// generated in — alphabetical by two-letter TAG. So the sequence a reader sees
// was decided by codes they never see, and any resemblance to an order was
// coincidence.
//
// Sorting by the names shown is not the answer either: those names are each in
// their own language, so the alphabet changes from row to row and the result
// still reads as no order at all. One language's names give one consistent
// sequence, and English is the language this project is written in.

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';

void main() {
  test('the picker is ordered by the English name of each language', () {
    final names =
        kOnoteLocalesInOrder.map(englishLanguageNameOf).toList();
    final sorted = [...names]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    expect(names, sorted);
  });

  test('every language Openote ships is in the list exactly once', () {
    // Sorting must not lose or duplicate a language — a picker missing the
    // reader's own language is worse than one in a strange order.
    expect(kOnoteLocalesInOrder.toSet().length, kOnoteLocalesInOrder.length);
    expect(kOnoteLocalesInOrder.toSet(), kOnoteLocales.toSet());
  });

  test('every language has an English name to sort by', () {
    // The fallback is the language tag, which would sort somewhere arbitrary
    // and read as a bug rather than as a missing entry.
    for (final loc in kOnoteLocales) {
      expect(englishLanguageNameOf(loc), isNot(loc.toLanguageTag()),
          reason: 'add ${loc.languageCode} to kLanguageNamesInEnglish');
    }
  });

  test('each language is still shown in its own name', () {
    // Sorting by English must not change what is DISPLAYED: somebody looking
    // for their language looks for "Deutsch", not "German".
    expect(languageNameOf(const Locale('de')), 'Deutsch');
    expect(languageNameOf(const Locale('zh')), '中文');
  });
}
