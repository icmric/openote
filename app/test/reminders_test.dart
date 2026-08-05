// Reminders (v0.5 stage 3) — Openote's own scheduler and its catch-up list.
//
// The feature's entire claim is "a reminder is either shown, or still
// showable". These tests pin the ways that claim breaks:
//
//   1. Firing twice. The `fired` flag has to survive a restart, or a student
//      who left a week of reminders behind is greeted by a week of popups they
//      already dealt with.
//   2. Losing one to a closed app. Anything that came due while Openote was not
//      running must come back as a catch-up row, because a desktop app cannot
//      interrupt you when it is not there (v0.5 §1).
//   3. Snoozing into the past. Snooze measured from the reminder's own time
//      re-fires an overdue nudge instantly, so Snooze becomes a button that
//      does nothing however often you press it.
//   4. Crashing on a corrupt settings blob. It lives in the workspace file
//      beside session state; a truncated write must cost you the reminders it
//      ate, not the app.
//   5. Pruning too eagerly. Dismissal is recoverable for the same 30 days as
//      the recycle bin, and an unknown dismissal age must not resolve to
//      "delete it".
//
// "now" is an argument everywhere, so nothing here depends on the day CI runs.
// No SQLite and no widgets: this file runs on a bare checkout.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/planner/reminders.dart';

/// Stands in for workspace settings.
///
/// [restart] is the part that matters: the real settings map is written to a
/// JSON file, so a store built in a later session sees `Map<String, dynamic>`
/// and `List<dynamic>` decoded from text, never the objects that were handed to
/// `writeSetting`. A test that skips that step can pass while the shipped app
/// throws on its second launch.
class FakeSettings {
  final Map<String, Object?> values = {};
  int writes = 0;

  Object? read(String key) => values[key];

  void write(String key, Object? value) {
    writes++;
    values[key] = value;
  }

  /// Round-trip everything through JSON, as closing and reopening the app does.
  void restart() {
    for (final key in values.keys.toList()) {
      values[key] = jsonDecode(jsonEncode(values[key]));
    }
  }

  /// The raw stored blob, for assertions about what actually hit the file.
  List<Object?> get blob => (values[ReminderStore.settingsKey] as List?) ?? [];
}

void main() {
  // A fixed clock: mid-afternoon, so "earlier today" and "later today" both
  // exist.
  final now = DateTime(2026, 8, 5, 15, 30);

  late FakeSettings settings;
  ReminderStore build({void Function()? onChanged}) {
    final s = ReminderStore(
      readSetting: settings.read,
      writeSetting: settings.write,
      onChanged: onChanged,
    );
    s.load();
    return s;
  }

  setUp(() => settings = FakeSettings());

  group('storage', () {
    test('a free-standing reminder with no target survives a restart', () {
      // v0.5 §7 leaves free-standing reminders an open decision; the store
      // allows them, so "call the tutor at 3" must not be silently mangled into
      // a row pointing at a page that does not exist.
      final store = build();
      final added = store.add(text: 'Call the tutor', at: DateTime(2026, 8, 5, 15));

      settings.restart();
      final reopened = build();

      expect(reopened.all, hasLength(1));
      final r = reopened.all.single;
      expect(r.id, added.id);
      expect(r.text, 'Call the tutor');
      expect(r.at, DateTime(2026, 8, 5, 15));
      expect(r.notebookId, isNull);
      expect(r.pageId, isNull);
      expect(r.blockId, isNull);
      expect(r.line, isNull);
      expect(r.fired, isFalse);
      expect(r.dismissed, isFalse);
    });

    test('a reminder anchored to a line keeps every target field', () {
      final store = build();
      store.add(
        text: 'Re-read the proof of 2.7',
        at: DateTime(2026, 8, 5, 16),
        notebookId: 'nb1',
        pageId: 'pg1',
        blockId: 'bk1',
        line: 3,
      );

      settings.restart();
      final r = build().all.single;

      expect(r.notebookId, 'nb1');
      expect(r.pageId, 'pg1');
      expect(r.blockId, 'bk1');
      expect(r.line, 3);
    });

    test('a time set at 4pm is still 4pm after a restart, not an instant', () {
      // Stored as local wall-clock, matching exam dates in study_state: an
      // epoch instant re-read in another timezone becomes a different time of
      // day, and "nudge me at 4pm" means 4pm.
      final store = build();
      store.add(text: 'x', at: DateTime(2026, 12, 25, 16));

      settings.restart();
      final r = build().all.single;

      expect(r.at.hour, 16);
      expect(r.at.isUtc, isFalse);
      expect(r.at, DateTime(2026, 12, 25, 16));
    });

    test('load twice does not duplicate the list', () {
      // Reopening a workspace calls load again; without the clear, every
      // reminder would double each time and fire once per copy.
      final store = build();
      store.add(text: 'x', at: now);

      store.load();
      store.load();

      expect(store.all, hasLength(1));
    });

    test('remove deletes, and an unknown id is a no-op rather than a throw', () {
      final store = build();
      final a = store.add(text: 'a', at: now);
      store.add(text: 'b', at: now);

      store.remove(a.id);
      expect(store.all.map((r) => r.text), ['b']);

      final writesBefore = settings.writes;
      store.remove('no-such-id');
      expect(settings.writes, writesBefore,
          reason: 'a no-op must not rewrite the settings file');
    });

    test('adding on top of an id already in use does not make a twin', () {
      // load() collapses duplicate ids because two rows sharing one make
      // dismiss/remove ambiguous — so add() must not manufacture the state the
      // reader defends against. Left alone, all three assertions below fail in
      // a different direction: remove() deletes every match and takes an
      // untouched reminder with it, byId/dismiss/snooze only ever reach the
      // first, and the second silently vanishes at the next launch.
      final store = build();
      final first = store.add(text: 'first', at: DateTime(2026, 8, 5, 16), id: 'x');
      final second = store.add(text: 'second', at: DateTime(2026, 8, 5, 17), id: 'x');

      expect(second.id, isNot(first.id));
      expect(store.all, hasLength(2));

      store.remove(first.id);
      expect(store.all.map((r) => r.text), ['second'],
          reason: 'removing one reminder must not delete the other');

      settings.restart();
      expect(build().all.map((r) => r.text), ['second'],
          reason: 'a duplicate id would have been dropped on the next load');
    });
  });

  group('corrupt blobs', () {
    test('a blob that is not a list loads nothing instead of throwing', () {
      settings.values[ReminderStore.settingsKey] = 'not a list at all';
      expect(build().all, isEmpty);
    });

    test('unreadable entries are dropped and readable ones survive', () {
      // The promise: a half-written settings file costs you the reminders it
      // ate, never the launch.
      settings.values[ReminderStore.settingsKey] = [
        'a bare string',
        42,
        null,
        {'id': 'no-time', 'text': 'missing at'},
        {'id': 'bad-time', 'text': 'unparseable', 'at': 'yesterday-ish'},
        {'id': 'nan', 'text': 'nan', 'at': double.nan},
        {'id': 'good', 'text': 'kept', 'at': '2026-08-05T16:00:00.000'},
      ];

      final store = build();

      expect(store.all.map((r) => r.id), ['good']);
      expect(store.all.single.at, DateTime(2026, 8, 5, 16));
    });

    test('a reminder with unreadable text is kept, not dropped', () {
      // The time is the irreplaceable part. Dropping the row because the label
      // is garbage throws away the thing the user actually chose.
      settings.values[ReminderStore.settingsKey] = [
        {'id': 'r1', 'text': 99, 'at': '2026-08-05T16:00:00.000'},
      ];

      final r = build().all.single;
      expect(r.text, '');
      expect(r.at, DateTime(2026, 8, 5, 16));
    });

    test('an entry with no id is kept and given one', () {
      settings.values[ReminderStore.settingsKey] = [
        {'text': 'idless', 'at': '2026-08-05T16:00:00.000'},
      ];

      final r = build().all.single;
      expect(r.id, isNotEmpty);
      expect(r.text, 'idless');
    });

    test('duplicate ids collapse to the first', () {
      // Two rows sharing an id make dismiss/remove ambiguous: the user kills
      // one popup and an identical one stays.
      settings.values[ReminderStore.settingsKey] = [
        {'id': 'dup', 'text': 'first', 'at': '2026-08-05T16:00:00.000'},
        {'id': 'dup', 'text': 'second', 'at': '2026-08-05T17:00:00.000'},
      ];

      final store = build();
      expect(store.all, hasLength(1));
      expect(store.all.single.text, 'first');
    });

    test('a garbage target or negative line degrades to null', () {
      // Null targets are already legal (free-standing reminders), so the safe
      // reading of an unusable target is "no target" — not a click-through into
      // a page id of empty string, or an index that throws when used.
      settings.values[ReminderStore.settingsKey] = [
        {
          'id': 'r1',
          'text': 't',
          'at': '2026-08-05T16:00:00.000',
          'notebookId': '',
          'pageId': 7,
          'blockId': 'bk1',
          'line': -2,
        },
      ];

      final r = build().all.single;
      expect(r.notebookId, isNull);
      expect(r.pageId, isNull);
      expect(r.blockId, 'bk1');
      expect(r.line, isNull);
    });

    test('a line index that cannot be a line degrades to null, like a negative',
        () {
      // `num.toInt()` truncates and saturates instead of throwing, so a blob
      // written by hand or by a future migration used to turn `2.7` into line 2
      // — a line nobody wrote — and `1e300` into 9223372036854775807, which
      // Reminder.toJson then persists and a click-through dereferences out of
      // bounds. That is the same failure a negative index is rejected for.
      settings.values[ReminderStore.settingsKey] = [
        {'id': 'huge', 'text': 't', 'at': '2026-08-05T16:00:00.000', 'line': 1e300},
        {'id': 'frac', 'text': 't', 'at': '2026-08-05T16:00:00.000', 'line': 2.7},
        {'id': 'whole', 'text': 't', 'at': '2026-08-05T16:00:00.000', 'line': 3.0},
      ];

      final store = build();

      expect(store.byId('huge')!.line, isNull);
      expect(store.byId('frac')!.line, isNull);
      expect(store.byId('whole')!.line, 3,
          reason: 'JSON writes whole numbers as doubles; line 3 is still line 3');
    });

    test('epoch milliseconds are accepted as a time', () {
      // Nothing writes this form, but the rest of the codebase stores times as
      // nowMs(), so a hand-edited or migrated blob plausibly contains one.
      final ms = DateTime(2026, 8, 5, 16).millisecondsSinceEpoch;
      settings.values[ReminderStore.settingsKey] = [
        {'id': 'r1', 'text': 't', 'at': ms},
      ];

      expect(build().all.single.at, DateTime(2026, 8, 5, 16));
    });

    test('a firedAt stamp without the flag does NOT count as fired', () {
      // Erring towards showing a reminder once more; the opposite error
      // swallows it silently, which is the failure this module exists to
      // prevent.
      settings.values[ReminderStore.settingsKey] = [
        {
          'id': 'r1',
          'text': 't',
          'at': '2026-08-05T09:00:00.000',
          'firedAt': '2026-08-05T09:00:00.000',
        },
      ];

      expect(build().due(now).map((r) => r.id), ['r1']);
    });
  });

  group('due and firing', () {
    test('nothing is due before its time, and it is due at exactly its time',
        () {
      // `at == now` counts as due, matching agenda.dart where an item due
      // exactly now is due but not yet overdue.
      final store = build();
      final r = store.add(text: 'x', at: DateTime(2026, 8, 5, 16));

      expect(store.due(DateTime(2026, 8, 5, 15, 59, 59)), isEmpty);
      expect(store.due(DateTime(2026, 8, 5, 16)).map((x) => x.id), [r.id]);
    });

    test('due returns oldest first', () {
      final store = build();
      final late0 = store.add(text: 'late', at: DateTime(2026, 8, 5, 15));
      final early = store.add(text: 'early', at: DateTime(2026, 8, 5, 9));

      expect(store.due(now).map((r) => r.id), [early.id, late0.id]);
    });

    test('a reminder does not fire twice in one session', () {
      final store = build();
      final r = store.add(text: 'x', at: DateTime(2026, 8, 5, 15));

      expect(store.due(now).map((x) => x.id), [r.id]);
      store.markFired([r.id], now);

      expect(store.due(now), isEmpty);
      expect(store.byId(r.id)!.fired, isTrue);
      expect(store.byId(r.id)!.firedAt, now);
    });

    test('a reminder does not fire again after a restart', () {
      // The flag has to reach the settings file. In memory only, every launch
      // replays every past reminder.
      final store = build();
      final r = store.add(text: 'x', at: DateTime(2026, 8, 5, 15));
      store.markFired([r.id], now);

      settings.restart();
      final reopened = build();

      expect(reopened.due(now), isEmpty);
      expect(reopened.byId(r.id)!.fired, isTrue);
    });

    test('markFired keeps the first firedAt and writes once for a batch', () {
      final store = build();
      final a = store.add(text: 'a', at: DateTime(2026, 8, 5, 9));
      final b = store.add(text: 'b', at: DateTime(2026, 8, 5, 10));

      store.markFired([a.id, b.id], now);
      final writesAfterBatch = settings.writes;

      store.markFired([a.id, b.id], now.add(const Duration(hours: 2)));

      expect(store.byId(a.id)!.firedAt, now,
          reason: 're-stamping makes an old reminder look freshly fired');
      expect(store.byId(b.id)!.firedAt, now);
      expect(settings.writes, writesAfterBatch,
          reason: 'nothing changed, so nothing should be written');
    });

    test('dismiss takes a reminder out of due and out of the schedule', () {
      final store = build();
      final r = store.add(text: 'x', at: DateTime(2026, 8, 5, 15));

      store.dismiss(r.id, now);

      expect(store.due(now), isEmpty);
      expect(store.nextDueAt(now), isNull);
      expect(store.byId(r.id), isNotNull, reason: 'kept for the retention window');
    });
  });

  group('snooze', () {
    test('snooze moves the time forward and un-fires it', () {
      final store = build();
      final r = store.add(text: 'x', at: DateTime(2026, 8, 5, 15));
      store.markFired([r.id], now);

      store.snooze(r.id, const Duration(minutes: 10), now);

      final after = store.byId(r.id)!;
      expect(after.at, now.add(const Duration(minutes: 10)));
      expect(after.fired, isFalse);
      expect(after.firedAt, isNull);
      expect(store.due(now), isEmpty);
      expect(store.due(now.add(const Duration(minutes: 10))).map((x) => x.id),
          [r.id]);
    });

    test('snoozing something long overdue lands in the future, not the past',
        () {
      // Measured from its own time, a three-day-old reminder snoozed by ten
      // minutes is still two days overdue and re-fires on the next tick — a
      // Snooze button that does nothing however often you press it.
      final store = build();
      final r = store.add(text: 'x', at: now.subtract(const Duration(days: 3)));

      store.snooze(r.id, const Duration(minutes: 10), now);

      expect(store.byId(r.id)!.at, now.add(const Duration(minutes: 10)));
      expect(store.due(now), isEmpty);
    });

    test('a snooze survives a restart', () {
      final store = build();
      final r = store.add(text: 'x', at: DateTime(2026, 8, 5, 15));
      store.markFired([r.id], now);
      store.snooze(r.id, const Duration(hours: 1), now);

      settings.restart();
      final reopened = build();

      expect(reopened.byId(r.id)!.at, now.add(const Duration(hours: 1)));
      expect(reopened.byId(r.id)!.fired, isFalse);
      expect(reopened.due(now), isEmpty);
    });

    test('snoozing a dismissed reminder does not resurrect it', () {
      // Documented conservative choice: re-arming something the user finished
      // with nags them with a nudge they explicitly killed.
      final store = build();
      final r = store.add(text: 'x', at: DateTime(2026, 8, 5, 15));
      store.dismiss(r.id, now);

      store.snooze(r.id, const Duration(hours: 1), now);

      expect(store.byId(r.id)!.dismissed, isTrue);
      expect(store.byId(r.id)!.at, DateTime(2026, 8, 5, 15));
      expect(store.due(now.add(const Duration(days: 1))), isEmpty);
    });

    test('reschedule moves a fired reminder to an absolute time and re-arms it',
        () {
      final store = build();
      final r = store.add(text: 'x', at: DateTime(2026, 8, 5, 9));
      store.markFired([r.id], now);

      store.reschedule(r.id, DateTime(2026, 8, 6, 9), now);

      expect(store.byId(r.id)!.fired, isFalse);
      expect(store.nextDueAt(now), DateTime(2026, 8, 6, 9));
    });
  });

  group('missedWhileAway', () {
    test('a reminder that came due while the app was closed comes back', () {
      // The scenario the whole feature exists for. Session one is running
      // before the reminder is due, so due() correctly returns nothing and
      // nothing is ever marked fired. Days later the app opens again.
      final store = build();
      final r = store.add(text: 'Re-read 2.7', at: DateTime(2026, 8, 2, 16));

      expect(store.due(DateTime(2026, 8, 2, 15)), isEmpty,
          reason: 'not due yet in the session before the app was closed');

      settings.restart();
      final reopened = build();

      final missed = reopened.missedWhileAway(now, staleAfter: Duration.zero);
      expect(missed.map((x) => x.id), [r.id]);
      expect(missed.single.text, 'Re-read 2.7');
    });

    test('staleAfter separates "missed" from "just fired"', () {
      // The discriminating case: both are due, only one was unreachable.
      final store = build();
      final old = store.add(text: 'old', at: now.subtract(const Duration(days: 2)));
      final fresh =
          store.add(text: 'fresh', at: now.subtract(const Duration(seconds: 30)));

      expect(store.due(now).map((r) => r.id), [old.id, fresh.id]);
      expect(
          store.missedWhileAway(now, staleAfter: const Duration(minutes: 2))
              .map((r) => r.id),
          [old.id]);
    });

    test('the default staleAfter is two minutes, boundary included', () {
      final store = build();
      final r = store.add(text: 'x', at: now.subtract(const Duration(minutes: 2)));

      expect(store.missedWhileAway(now).map((x) => x.id), [r.id]);
      expect(
          store.missedWhileAway(now.subtract(const Duration(seconds: 1))), isEmpty);
    });

    test('what has been surfaced or dismissed is not "missed"', () {
      // Otherwise the catch-up list announces reminders the student already saw
      // this session, and stops meaning anything.
      final store = build();
      final shown = store.add(text: 'shown', at: now.subtract(const Duration(days: 1)));
      final killed = store.add(text: 'killed', at: now.subtract(const Duration(days: 1)));
      final missed = store.add(text: 'missed', at: now.subtract(const Duration(days: 1)));

      store.markFired([shown.id], now);
      store.dismiss(killed.id, now);

      expect(store.missedWhileAway(now, staleAfter: Duration.zero).map((r) => r.id),
          [missed.id]);
    });

    test('the catch-up list is oldest first and clears once acknowledged', () {
      final store = build();
      final week = store.add(text: 'week', at: now.subtract(const Duration(days: 7)));
      final hour = store.add(text: 'hour', at: now.subtract(const Duration(hours: 1)));
      final day = store.add(text: 'day', at: now.subtract(const Duration(days: 1)));

      final missed = store.missedWhileAway(now, staleAfter: Duration.zero);
      expect(missed.map((r) => r.id), [week.id, day.id, hour.id]);

      store.markFired([for (final r in missed) r.id], now);
      settings.restart();

      expect(build().missedWhileAway(now, staleAfter: Duration.zero), isEmpty,
          reason: 'acknowledging the list must outlive the session');
    });

    test('nothing in the future is ever missed', () {
      final store = build();
      store.add(text: 'x', at: now.add(const Duration(hours: 1)));

      expect(store.missedWhileAway(now, staleAfter: Duration.zero), isEmpty);
    });
  });

  group('nextDueAt', () {
    test('is null when there is nothing to wait for', () {
      final store = build();
      expect(store.nextDueAt(now), isNull);
    });

    test('is the earliest future reminder', () {
      final store = build();
      store.add(text: 'later', at: DateTime(2026, 8, 6, 9));
      store.add(text: 'sooner', at: DateTime(2026, 8, 5, 16));
      store.add(text: 'latest', at: DateTime(2026, 9, 1, 9));

      expect(store.nextDueAt(now), DateTime(2026, 8, 5, 16));
    });

    test('ignores fired and dismissed reminders', () {
      // A finished reminder that still set the timer would wake the app up to
      // do nothing, over and over.
      final store = build();
      final a = store.add(text: 'a', at: DateTime(2026, 8, 5, 16));
      final b = store.add(text: 'b', at: DateTime(2026, 8, 5, 17));
      final c = store.add(text: 'c', at: DateTime(2026, 8, 5, 18));

      store.markFired([a.id], now);
      store.dismiss(b.id, now);

      expect(store.nextDueAt(now), DateTime(2026, 8, 5, 18));
      expect(store.byId(c.id), isNotNull);

      store.dismiss(c.id, now);
      expect(store.nextDueAt(now), isNull);
    });

    test('an overdue unfired reminder reports now, never a negative wait', () {
      // Two bugs at once: skipping it entirely loses a reminder the app failed
      // to show, and returning its own past instant gives the caller a negative
      // duration to arm a timer with.
      final store = build();
      store.add(text: 'x', at: now.subtract(const Duration(days: 3)));

      final next = store.nextDueAt(now);
      expect(next, now);
      expect(next!.difference(now), Duration.zero);
    });

    test('onChanged fires on every persisted change so the timer is re-armed',
        () {
      // A stale timer is a missed nudge: adding a reminder for five minutes
      // from now must not wait behind a timer armed for next week.
      var calls = 0;
      final store = build(onChanged: () => calls++);

      final r = store.add(text: 'x', at: DateTime(2026, 8, 6, 9));
      expect(calls, 1);
      store.snooze(r.id, const Duration(hours: 1), now);
      expect(calls, 2);
      store.dismiss(r.id, now);
      expect(calls, 3);
      store.remove(r.id, now);
      expect(calls, 4);
    });
  });

  group('retention', () {
    test('a month-old dismissal is swept, a recent one is kept', () {
      // One retention concept for everything the user can get back: the same 30
      // days as the recycle bin.
      final store = build();
      final stale = store.add(text: 'stale', at: DateTime(2026, 6, 1, 9));
      final recent = store.add(text: 'recent', at: DateTime(2026, 8, 1, 9));
      final live = store.add(text: 'live', at: DateTime(2026, 8, 6, 9));

      store.dismiss(stale.id, now.subtract(const Duration(days: 31)));
      store.dismiss(recent.id, now.subtract(const Duration(days: 3)));

      // The sweep runs on write, so it needs one more write to happen.
      store.add(text: 'trigger', at: DateTime(2026, 8, 7, 9), now: now);

      expect(store.all.map((r) => r.id), isNot(contains(stale.id)));
      expect(store.all.map((r) => r.id), contains(recent.id));
      expect(store.all.map((r) => r.id), contains(live.id));

      settings.restart();
      expect(build().all.map((r) => r.text),
          ['recent', 'live', 'trigger'],
          reason: 'the pruned list is what reaches the settings file');
    });

    test('a dismissal of unknown age is never swept', () {
      // "Unknown age" must not resolve to "delete it" — the cost of keeping the
      // row is bytes; the cost of guessing is destroying something recoverable.
      settings.values[ReminderStore.settingsKey] = [
        {
          'id': 'ancient',
          'text': 'no stamp',
          'at': '2020-01-01T09:00:00.000',
          'dismissed': true,
        },
      ];

      final store = build();
      store.add(text: 'trigger', at: DateTime(2026, 8, 7, 9), now: now);

      expect(store.all.map((r) => r.id), contains('ancient'));
    });

    test('a live reminder older than the retention window is never swept', () {
      // Retention applies to dismissals only. A reminder you never dealt with
      // is exactly the one the catch-up list has to be able to show you.
      final store = build();
      final ancient = store.add(text: 'ancient', at: DateTime(2025, 1, 1, 9));

      store.add(text: 'trigger', at: DateTime(2026, 8, 7, 9), now: now);

      expect(store.all.map((r) => r.id), contains(ancient.id));
      expect(store.missedWhileAway(now, staleAfter: Duration.zero).map((r) => r.id),
          [ancient.id]);
    });
  });
}
