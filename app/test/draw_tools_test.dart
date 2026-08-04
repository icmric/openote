// Picking a pen must actually pick the pen.
//
// Reported: "I am at the moment unable to select the pen or anything in the
// menu." Ink is the reason half the users are here, so the tool buttons are
// worth pinning at the widget level rather than trusting that a state method
// with no branches must work.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/command_bar.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<AppState> newApp(WidgetTester tester) async {
    late AppState app;
    late Repository repo;
    final tmp = Directory.systemTemp.createTempSync('onote_draw_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Draw');
      app = AppState(repo)..notebookId = nb.id;
      app.nodes = repo.loadNodes(nb.id);
    });
    return app;
  }

  /// The bar at a realistic desktop width, inside a Listenable rebuild exactly
  /// as `AppShell` mounts it — the rebuild is the part that could plausibly
  /// throw the tab selection away.
  Widget host(AppState app, {double width = 1280}) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: ListenableBuilder(
              listenable: app,
              builder: (_, __) => Column(children: [CommandBar(app: app)]),
            ),
          ),
        ),
      );

  testWidgets('the Draw tab selects each ink tool', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    await tester.pumpWidget(host(app));

    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();

    for (final (tip, want) in const [
      ('Pen  (P)', Tool.pen),
      ('Highlighter  (H)', Tool.highlighter),
      ('Eraser  (E)', Tool.eraser),
      ('Lasso-select ink', Tool.lasso),
    ]) {
      await tester.tap(find.byTooltip(tip));
      await tester.pumpAndSettle();
      expect(app.tool, want, reason: 'tapping "$tip" must select $want');
    }
  });

  testWidgets('the Draw tab survives the rebuild its own tap causes',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    await tester.pumpWidget(host(app));

    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pen  (P)'));
    await tester.pumpAndSettle();

    // Selecting a tool calls notifyListeners, which rebuilds the whole shell.
    // If the bar's tab index were lost in that rebuild the user would be
    // bounced back to Home and it would look exactly like "the pen won't
    // select" — so assert the Draw row is still on screen.
    expect(find.byTooltip('Pen  (P)'), findsOneWidget,
        reason: 'the Draw row must still be showing after picking a tool');
    expect(app.tool, Tool.pen);
  });

  testWidgets('the tab row stays usable on a narrow window', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    // A laptop with the navigator open leaves the bar well under 900px. The
    // command row scrolls; the TAB row must not overflow, because an
    // overflowing child is clipped and clipped pixels do not hit-test — the
    // tabs would silently stop responding.
    await tester.pumpWidget(host(app, width: 560));
    await tester.pump();
    expect(tester.takeException(), isNull,
        reason: 'a narrow command bar must not overflow');

    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pen  (P)'));
    await tester.pumpAndSettle();
    expect(app.tool, Tool.pen);
  });
}
