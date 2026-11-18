// Waiting for something that happens on the real clock, without guessing how
// long it takes. See `docs/writing-tests.md`, rule 2.
//
// A fixed `Future.delayed(400 ms)` followed by `expect(...)` is a guess about
// how fast the machine is: right on a laptop, wrong on a loaded CI runner, and
// the failure looks exactly like a bug. Poll for the condition instead, with a
// deadline generous enough that only a real failure reaches it.
import 'package:flutter_test/flutter_test.dart';

/// Wait until [done] holds, checking every 10 ms on the REAL clock, and fail
/// naming [what] if it has not after [timeout].
///
/// For `test()` bodies, and inside `tester.runAsync` in a `testWidgets` body:
/// a widget test's own clock is fake, and a real-time wait outside `runAsync`
/// never ends.
///
/// Only for something that must eventually HAPPEN. To check that something
/// does NOT happen there is no deadline that proves it; wait for an event
/// that is known to come after it instead, or test the rule on a fake clock.
Future<void> eventually(
  bool Function() done, {
  required String what,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final clock = Stopwatch()..start();
  while (!done()) {
    if (clock.elapsed > timeout) {
      fail('waited ${timeout.inSeconds} s for $what, and it never happened');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// [eventually] for a widget test: pump a frame, and while [done] does not
/// hold, let 10 ms of REAL time pass (for file and database work, which a
/// widget test's fake clock does not drive) and pump again. Fails naming
/// [what] after [timeout] of real time.
///
/// Instead of `await t.runAsync(() => Future.delayed(100 ms))` followed by an
/// `expect`: that is a guess that the work finishes in 100 ms.
Future<void> pumpUntil(
  WidgetTester t,
  bool Function() done, {
  required String what,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final clock = Stopwatch()..start();
  while (true) {
    await t.pump();
    if (done()) return;
    if (clock.elapsed > timeout) {
      fail('waited ${timeout.inSeconds} s for $what, and it never happened');
    }
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
}
