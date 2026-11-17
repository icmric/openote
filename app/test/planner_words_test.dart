// The planner's dates and times in every language, and in English exactly
// what the agenda's own helpers say.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/gen/app_localizations.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/l10n/planner_words.dart';
import 'package:openote/planner/agenda.dart';
import 'package:openote/ui/planner_format.dart';

void main() {
  final en = lookupL(const Locale('en'));
  final now = DateTime(2026, 11, 17, 10, 15);

  DatedItem at(DateTime when, {bool allDay = true}) => DatedItem(
      id: 'x', kind: DatedKind.task, title: 't', when: when, allDay: allDay);

  test('in English, the same words as the agenda', () {
    for (var d = -30; d <= 40; d++) {
      final day = DateTime(2026, 11, 17 + d);
      for (final allDay in [true, false]) {
        final when =
            allDay ? day : DateTime(day.year, day.month, day.day, 16, 30);
        final it = at(when, allDay: allDay);
        expect(relativeWhenIn(en, it, now), relativeWhen(it, now),
            reason: '$d days, allDay $allDay');
        expect(plannerWhenIn(en, it, now), plannerWhen(it, now),
            reason: '$d days, allDay $allDay');
      }
      expect(dayFullIn(en, day), formatDayFull(day));
    }
    for (final t in [
      DateTime(2026, 1, 1, 0, 0),
      DateTime(2026, 1, 1, 9, 0),
      DateTime(2026, 1, 1, 12, 5),
      DateTime(2026, 1, 1, 16, 30),
    ]) {
      expect(clockIn(en, t), formatClock(t));
    }
    for (final b in AgendaBucket.values) {
      expect(b.titleIn(en), b.title);
    }
    expect(monthYearIn(en, 8, 2026), '${monthName(8)} 2026');
  });

  test('every language has seven days and its own words', () {
    for (final locale in kOnoteLocales) {
      final l = lookupL(locale);
      expect(l.weekdaysShort.split(','), hasLength(7), reason: '$locale');
      expect(weekdayInitialsIn(l), hasLength(7), reason: '$locale');
      if (locale.languageCode == 'en') continue;
      expect(AgendaBucket.overdue.titleIn(l), isNot('Overdue'),
          reason: '$locale');
      expect(relativeWhenIn(l, at(DateTime(2026, 11, 20)), now),
          isNot('in 3 days'),
          reason: '$locale');
    }
  });

  test('a German reader gets 24-hour times and German dates', () {
    final de = lookupL(const Locale('de'));
    expect(clockIn(de, DateTime(2026, 1, 1, 16, 30)), '16:30');
    expect(dayFullIn(de, DateTime(2026, 8, 6)), 'Do., 6. Aug.');
    expect(relativeWhenIn(de, at(DateTime(2026, 11, 20)), now), 'in 3 Tagen');
  });
}
