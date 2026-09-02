// The equation box grows with what you write, and never overflows.
//
// Maths was the only block type in the app with NO width strategy at all —
// every other type grows, wraps or scrolls. While editing, the equation was
// pinned to `Block.w`, so anything wider was clipped and Flutter painted the
// overflow stripe. Measured before the fix, on a block made exactly as Alt+=
// makes one (w: 360): the width the equation needed climbed 23 → 121 → 219 →
// 316 → 414 px while the field stayed 338 px, and from the fourth step on
// every keystroke logged "A RenderLine overflowed by N pixels on the right."
//
// Worse, one press of a Maths-tab button could do it in a single step: read
// mode spends 24 px of padding against editing's 20, so a block written back
// at its read width has exactly 4 px of slack, and one `\square` slot spends
// it. The box the student has to type into ended up off the right-hand edge.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/math_block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/math/math_editor.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_mathgrow_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('T');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
  });

  tearDown(() {
    AppState.syncLogEnabled = true;
    if (!haveSqlite) return;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Pump the block at a fixed viewport, letting the post-frame growth run
  /// without waiting on the save debounce (which `pumpAndSettle` would).
  Future<void> settle(WidgetTester tester, Block b) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: b.w,
            child: MathBlockView(block: b, app: app),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Editing arms AppState's save debounce, and the test binding asserts no
    // timer is pending when the body ends — which is checked BEFORE tearDown.
    app.cancelPendingSave();
  }

  testWidgets('a long equation grows the box instead of overflowing it',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final overflows = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (d) {
      final s = d.exception.toString();
      if (s.contains('overflowed')) {
        overflows.add(s.split('\n').first);
      } else {
        previous?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = previous);

    final b = app.insertEquation(at: const Offset(20, 20));
    final startWidth = b.w;

    // Write an equation far wider than the block it started in.
    final e = MathEditor.open('')!;
    for (final ch in 'a+b+c+d+e+f+g+h+i+j+k+l+m+n+o+p'.split('')) {
      e.insertChar(ch);
    }
    b.content['latex'] = e.latex;

    await settle(tester, b);
    // Re-pump at the grown width, the way the canvas would.
    await settle(tester, b);

    expect(overflows, isEmpty,
        reason: 'the equation must never paint outside its box: '
            '${overflows.take(2).join(" | ")}');
    expect(b.w, greaterThan(startWidth),
        reason: 'the box has to widen to what is actually being written — '
            'it stayed at $startWidth while the equation kept growing');
  });

  testWidgets('and it stops growing at a ceiling rather than eating the page',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final b = app.insertEquation(at: const Offset(20, 20));
    final e = MathEditor.open('')!;
    for (var i = 0; i < 200; i++) {
      e.insertChar('x');
      e.insertChar('+');
    }
    b.content['latex'] = e.latex;

    await settle(tester, b);
    await settle(tester, b);
    await settle(tester, b);

    expect(b.w, lessThanOrEqualTo(900.0),
        reason: 'past the ceiling a block stops being a block and starts '
            'being the page — it scrolls from there instead');
  });

  testWidgets('growth never shrinks a box the student widened themselves',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final b = app.insertEquation(at: const Offset(20, 20));
    b.content['latex'] = 'x';
    b.w = 600;
    await settle(tester, b);
    await settle(tester, b);
    expect(b.w, 600,
        reason: 'a box that twitches narrower mid-keystroke is worse than one '
            'that is wider than it needs to be');
  });
}
