// Every tab switch animates, and the Equation badge is a way back.
//
// Two reports about the same row:
//
//   *"there are animations between the bars which is great, however this is
//   only for home and insert, going to and from draw and page from home just
//   cuts (and vice versa), between home and page cuts, but from insert to
//   home or page (and vice versa) has the animation, this must all be
//   consistent."*
//
//   *"there is a button labled "equation" which pops up in the toolbar when
//   editing an equation, this is good, however it does not function as a
//   button. If i click out of it into one of the other tabs, i am unable to
//   go back into this toolbar, even though im still in the equation editing
//   mode, meaning i have to click out of the equation and back in for this
//   to become accessable again."*
//
// **How a cut is detected.** `pumpAndSettle` cannot see one — it runs the
// clock to the end, and a transition that never happened and one that has
// finished look identical. What distinguishes them is the MIDDLE: an
// `AnimatedSwitcher` mid-transition holds the outgoing child and the
// incoming one at once, and one that decided nothing changed holds a single
// child the whole way. So these pump half a duration and count.
//
// The cause was `Widget.canUpdate`: the key sat on the `SingleChildScrollView`
// INSIDE an unkeyed `ScrollConfiguration`, and the switcher only ever compares
// its direct child. Three faces therefore presented the same unkeyed
// `ScrollConfiguration`, and the two that carried a key at the top — Insert,
// and the equation — were the two that animated.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/math/active_math.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
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
    tmp = Directory.systemTemp.createTempSync('onote_bartrans_');
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

  Future<void> pumpBar(WidgetTester t) async {
    t.view.physicalSize = const Size(2600, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) => CommandBar(app: app),
        ),
      ),
    ));
    await t.pumpAndSettle();
  }

  /// How many children the face switcher is holding right now.
  ///
  /// Two means a transition is in flight — `AnimatedSwitcher` keeps the
  /// outgoing child alive beside the incoming one for the duration. One means
  /// it swapped in place, which is the cut.
  int facesInFlight(WidgetTester t) {
    final switcher = find.byType(AnimatedSwitcher);
    expect(switcher, findsOneWidget, reason: 'one switcher owns the face');
    // The switcher's own children, not every FadeTransition in the subtree:
    // a face may well contain its own. `AnimatedSwitcher` wraps each child in
    // the transition its `transitionBuilder` returns, and puts them in a
    // Stack, so its direct Stack's children are the count.
    final stack = find
        .descendant(of: switcher, matching: find.byType(Stack))
        .evaluate()
        .first;
    return (stack.widget as Stack).children.length;
  }

  group('every tab switch animates', () {
    // The exact pairs named in the report, plus the ones that already worked
    // so a fix cannot trade one for another.
    const pairs = [
      ('Home', 'Draw'),
      ('Home', 'Page'),
      ('Draw', 'Page'),
      ('Home', 'Insert'),
      ('Insert', 'Page'),
      ('Insert', 'Draw'),
    ];

    for (final (from, to) in pairs) {
      testWidgets('$from to $to', (tester) async {
        if (!haveSqlite) return markTestSkipped('sqlite unavailable');
        await pumpBar(tester);

        await tester.tap(find.text(from));
        await tester.pumpAndSettle();

        await tester.tap(find.text(to));
        await tester.pump(); // the frame that starts it
        await tester.pump(const Duration(milliseconds: 75)); // halfway
        expect(facesInFlight(tester), 2,
            reason: '$from → $to CUT: the switcher is holding one child '
                'halfway through what should be a 150ms transition');

        await tester.pumpAndSettle();
        expect(facesInFlight(tester), 1, reason: 'and it finishes');
        app.cancelPendingSave();
      });

      testWidgets('$to back to $from', (tester) async {
        if (!haveSqlite) return markTestSkipped('sqlite unavailable');
        // *"(and vice versa)"* — stated in the report for a reason, and a
        // key that is wrong is wrong in both directions.
        await pumpBar(tester);
        await tester.tap(find.text(to));
        await tester.pumpAndSettle();
        await tester.tap(find.text(from));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 75));
        expect(facesInFlight(tester), 2, reason: '$to → $from CUT');
        app.cancelPendingSave();
      });
    }
  });

  group('the Equation badge', () {
    /// An equation registered as the open one, so the row lends it the face.
    ///
    /// The same stand-in `command_faces_test.dart` uses, and for the same
    /// reason: `setActiveMath` is how an editor announces itself, and this
    /// harness mounts the bar without the canvas under it. What is under
    /// test is which face the row shows and how you get back to it, neither
    /// of which the editor takes any part in.
    Future<void> openEquation(WidgetTester t) async {
      await pumpBar(t);
      app.editingBlockId = 'eq1';
      app.setActiveMath(ActiveMathEditor(
        owner: 'test',
        insert: (_) {},
        latexMode: false,
        latexAvailable: true,
        toggleLatex: () {},
      ));
      app.refreshChrome();
      await t.pumpAndSettle();
    }

    testWidgets('appears while an equation is open', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await openEquation(tester);
      expect(find.text('Equation'), findsOneWidget);
      app.cancelPendingSave();
    });

    testWidgets('brings the equation tools back after tabbing away',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await openEquation(tester);
      // The equation's palette is on the row. `MathBar` is the whole of that
      // face and exists nowhere else, which makes it the marker rather than
      // any one chip's label.
      expect(find.byType(MathBar), findsOneWidget,
          reason: 'the equation face is showing to begin with');

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.byType(MathBar), findsNothing,
          reason: 'tabbing away hands the row back, which is intended');
      expect(find.text('Equation'), findsOneWidget,
          reason: 'and the badge stays, because the equation is still open');

      // THE BUG: this was a one-way trip. `_tabbedAwayFrom` was set and
      // nothing could clear it, so the only way back was closing the
      // equation and reopening it.
      await tester.tap(find.text('Equation'));
      await tester.pumpAndSettle();
      expect(find.byType(MathBar), findsOneWidget,
          reason: 'pressing the badge is the way back');
      app.cancelPendingSave();
    });

    testWidgets('and the equation is still being edited afterwards',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The badge is wrapped in `ExcludeFocus` precisely so the trip back
      // cannot cost the equation the keyboard it is holding.
      await openEquation(tester);
      final id = app.editingBlockId;
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Equation'));
      await tester.pumpAndSettle();
      expect(app.editingBlockId, id);
      app.cancelPendingSave();
    });

    testWidgets('is not pressable while it is already showing', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // A control that does nothing when pressed is worse than one that
      // cannot be — so there is no InkWell under it in this state.
      await openEquation(tester);
      expect(
          find.descendant(
              of: find.ancestor(
                  of: find.text('Equation'), matching: find.byType(Tooltip)),
              matching: find.byType(InkWell)),
          findsNothing);
      app.cancelPendingSave();
    });
  });
}
