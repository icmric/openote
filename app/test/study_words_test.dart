// The study side's small phrases in every language, and in English exactly
// what `lib/study` says.
//
// `formatDelay`, `formatCountdown` and `formatExamDate` stay in `lib/study`,
// English and widget-free, for the scheduler and its tests. The screens now
// say `delayIn`, `countdownIn` and `shortDateIn`, which read `L`. Two copies of
// the same cut-offs can drift, so this walks both over the same inputs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/gen/app_localizations.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/l10n/study_words.dart';
import 'package:openote/study/flashcards.dart';
import 'package:openote/study/study_stats.dart';

void main() {
  final en = lookupL(const Locale('en'));

  test('in English, the same words as lib/study', () {
    const minute = 60000, hour = 60 * minute, day = 24 * hour;
    for (final ms in [
      -5,
      0,
      1,
      30 * 1000,
      minute,
      9 * minute,
      59 * minute,
      hour,
      5 * hour,
      35 * hour,
      36 * hour,
      3 * day,
      30 * day,
      31 * day,
      200 * day,
      364 * day,
      365 * day,
      900 * day,
      4000 * day,
    ]) {
      expect(delayIn(en, ms), formatDelay(ms), reason: '$ms ms');
    }
    for (var d = -20; d <= 40; d++) {
      expect(countdownIn(en, d), formatCountdown(d), reason: '$d days');
    }
    final today = DateTime(2026, 11, 17);
    for (final d in [
      DateTime(2026, 1, 3),
      DateTime(2026, 8, 12),
      DateTime(2026, 12, 31),
      DateTime(2027, 5, 9),
      DateTime(2025, 2, 28),
    ]) {
      expect(shortDateIn(en, d, today), formatExamDate(d, today));
    }
    for (final g in Grade.values) {
      expect(g.labelIn(en), g.label);
    }
  });

  test('every language has twelve months and its own words', () {
    for (final locale in kOnoteLocales) {
      final l = lookupL(locale);
      expect(l.monthsShort.split(','), hasLength(12), reason: '$locale');
      if (locale.languageCode == 'en') continue;
      expect(countdownIn(l, 1), isNot(formatCountdown(1)), reason: '$locale');
      expect(Grade.again.labelIn(l), isNot('Again'), reason: '$locale');
    }
  });

  test('a German and a Chinese reader', () {
    final de = lookupL(const Locale('de'));
    expect(countdownIn(de, 3), '3 Tage');
    expect(countdownIn(de, -3), 'vor 3 Tagen');
    expect(shortDateIn(de, DateTime(2026, 8, 12), DateTime(2026, 1, 1)),
        '12. Aug.');
    expect(delayIn(de, 10 * 60000), '10 Min.');
    final zh = lookupL(const Locale('zh'));
    expect(shortDateIn(zh, DateTime(2027, 8, 12), DateTime(2026, 1, 1)),
        '2027年8月12日');
  });
}
