// The Maths tab (plan: v0.18 §5.2, revised).
//
// The owner's report on the first cut: "you seem to have decided to put all
// the options in the box itself, this isnt great. I want them in the bar up
// the top like it is in onenote. This tab only appears when editing a maths
// equation."
//
// Two promises that pull against each other: the tab has to be THERE the
// moment an equation opens, and GONE the moment it closes. A contextual tab
// that lingers is worse than none at all, because its buttons then act on
// nothing.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/math_block_view.dart';
import 'package:openote/math/active_math.dart';
import 'package:openote/math/math_inventory.dart';
import 'package:openote/math/math_view.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/command_bar.dart';
import 'package:openote/ui/math_bar.dart';

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
    tmp = Directory.systemTemp.createTempSync('onote_mathtab_');
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
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// The toolbar is a single scrolling row of ~30 controls; at the default
  /// 800px test window most of it is off screen and taps miss. Real windows
  /// are wider than the test one, so this is harness, not product.
  void widen(WidgetTester tester) {
    tester.view.physicalSize = const Size(2600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// Editing marks the page dirty, which arms the save debounce. Left running
  /// it fails the test as a leaked timer.
  void settle() => app.cancelPendingSave();

  Future<void> pump(WidgetTester tester) async {
    widen(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) => CommandBar(app: app),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Stand in for an open equation editor. The real registration is covered by
  /// "the block editor puts itself on the toolbar" below; these tests are
  /// about the toolbar, and pumping a whole canvas to reach it would test the
  /// canvas instead.
  void registerEditor({
    List<MathItem>? inserted,
    VoidCallback? onToggle,
    bool latexMode = false,
  }) =>
      app.setActiveMath(ActiveMathEditor(
        owner: 'test',
        insert: (i) => inserted?.add(i),
        latexMode: latexMode,
        latexAvailable: true,
        toggleLatex: onToggle ?? () {},
      ));

  testWidgets('there is no Maths tab until an equation is being written',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(tester);
    expect(find.text('Maths'), findsNothing);
    for (final t in ['Home', 'Insert', 'Draw', 'View']) {
      expect(find.text(t), findsOneWidget, reason: '$t should still be there');
    }
  });

  testWidgets('inserting an equation brings the tab up, already selected',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(tester);
    app.insertEquation(at: const Offset(20, 20));
    registerEditor();
    await tester.pumpAndSettle();
    expect(find.text('Maths'), findsOneWidget);
    // Selected without a second click — the student pressed Alt+= because they
    // want to write maths; making them find the tab is a step for nothing.
    expect(find.byType(MathBar), findsOneWidget);
    settle();
  });

  testWidgets('and it goes away again the moment the equation is finished',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(tester);
    final b = app.insertEquation(at: const Offset(20, 20));
    registerEditor();
    await tester.pumpAndSettle();
    expect(find.text('Maths'), findsOneWidget);

    app.select(b.id, edit: false);
    app.clearActiveMath('test');
    await tester.pumpAndSettle();
    expect(find.text('Maths'), findsNothing,
        reason: 'buttons that act on nothing are worse than no buttons');
    // …and the toolbar falls back to a real tab rather than a blank row.
    expect(find.byType(MathBar), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    settle();
  });

  testWidgets('the tab drives whichever equation is open', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final inserted = <MathItem>[];
    var toggled = 0;
    await pump(tester);
    app.insertEquation(at: const Offset(20, 20));
    registerEditor(inserted: inserted, onToggle: () => toggled++);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('fraction — type 1/2'));
    await tester.pumpAndSettle();
    expect(inserted.single.id, 'frac');

    await tester.tap(find.text('LaTeX'));
    expect(toggled, 1);
    settle();
  });

  testWidgets('a student can still leave the tab while writing an equation',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(tester);
    app.insertEquation(at: const Offset(20, 20));
    registerEditor();
    await tester.pumpAndSettle();
    expect(find.byType(MathBar), findsOneWidget);

    // Without this the tab would drag itself back on the very next rebuild and
    // the Insert tab would be unreachable for as long as an equation was open.
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    expect(find.byType(MathBar), findsNothing);
    expect(find.text('Maths'), findsOneWidget,
        reason: 'left, not gone — the equation is still open');

    await tester.tap(find.text('Maths'));
    await tester.pumpAndSettle();
    expect(find.byType(MathBar), findsOneWidget);
    settle();
  });

  testWidgets('the block editor puts itself on the toolbar, and takes itself '
      'off again', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The seam between the two halves: the tab is useless if the editor never
    // registers, and it acts on a dead editor if the editor never unregisters.
    final block = app.insertEquation(at: const Offset(20, 20));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 500,
          child: MathBlockView(block: block, app: app),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(app.activeMath, isNotNull,
        reason: 'an open equation must reach the toolbar');

    // Tear the editor down the way leaving the page does.
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await tester.pumpAndSettle();
    expect(app.activeMath, isNull,
        reason: 'the tab would otherwise drive an editor that is gone');
    settle();
  });

  group('what the bar itself offers', () {
    Future<void> pumpBar(
      WidgetTester tester, {
      required ValueChanged<MathItem> onInsert,
      bool latexMode = false,
      String? result,
    }) async {
      widen(tester);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: MathBar(
              latexMode: latexMode,
              result: result,
              onToggleLatex: () {},
              onInsert: onInsert,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('every shape button draws as notation, not as source',
        (tester) async {
      await pumpBar(tester, onInsert: (_) {});
      expect(find.byType(MathSourceFallback), findsNothing);
      // The fixed row IS the muscle memory — all of it has to be present.
      for (final id in kMathStructureIds) {
        final item = mathItemsById[id]!;
        final tip = item.typeIt == null
            ? item.name
            : '${item.name} — type ${item.typeIt}';
        expect(find.byTooltip(tip), findsOneWidget,
            reason: '$id is missing from the shapes row');
      }
    });

    testWidgets('a symbol category opens as a gallery and inserts on tap',
        (tester) async {
      MathItem? got;
      await pumpBar(tester, onInsert: (i) => got = i);
      await tester.tap(find.text('Greek'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('theta — type theta').first);
      await tester.pumpAndSettle();
      expect(got?.id, 'greek-theta');
    });

    testWidgets('searching in plain words inserts the first hit on Enter',
        (tester) async {
      MathItem? got;
      await pumpBar(tester, onInsert: (i) => got = i);
      await tester.enterText(find.byType(TextField), 'not equal');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(got?.id, 'neq');
    });

    testWidgets('the calculator answer rides along at the end', (tester) async {
      await pumpBar(tester, onInsert: (_) {}, result: '42');
      expect(find.text('= 42'), findsOneWidget);
    });

    testWidgets('the LaTeX view swaps the buttons for a plain-words note',
        (tester) async {
      await pumpBar(tester, onInsert: (_) {}, latexMode: true);
      expect(find.text('Buttons'), findsOneWidget);
      expect(find.textContaining('Writing the LaTeX by hand'), findsOneWidget);
    });
  });
}
