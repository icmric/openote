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
import 'package:openote/l10n/l10n.dart';
import 'package:openote/math/active_math.dart';
import 'package:openote/math/math_inventory.dart';
import 'package:openote/math/math_view.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/command_bar.dart';
import 'package:openote/ui/math_bar.dart';
import 'package:openote/ui/object_row.dart';

import 'support/sqlite.dart';

/// One backslash, named so the expectations read as what a student types.
const String bs = '\\';

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

  /// The chrome as the app builds it: the bar, then the object row under it.
  /// Both, because the whole design is that the second one changes without
  /// the first one moving.
  Future<void> pump(WidgetTester tester) async {
    widen(tester);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) => Column(children: [
            CommandBar(app: app),
            ObjectRow(app: app),
          ]),
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

  testWidgets('there is no Maths tab, and there never is', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(tester);
    expect(find.text('Maths'), findsNothing);
    for (final t in ['Home', 'Insert', 'Draw']) {
      expect(find.text(t), findsOneWidget, reason: '$t should be there');
    }
    expect(find.text('View'), findsNothing,
        reason: "the page's own controls are on the object row, and the four "
            'preferences View also held were already in Settings');
  });

  testWidgets('the palette arrives WITHOUT the student being moved',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(tester);
    // The student is on Insert, deliberately.
    await tester.tap(find.text('Insert'));
    await tester.pumpAndSettle();
    expect(find.text('Equation'), findsOneWidget, reason: 'the Insert row');

    app.insertEquation(at: const Offset(20, 20));
    registerEditor();
    await tester.pumpAndSettle();

    expect(find.byType(MathBar), findsOneWidget,
        reason: 'the palette is there the moment the equation is');
    expect(find.text('Equation'), findsWidgets,
        reason: 'and Insert is STILL what the command row is showing \u2014 the '
            'owner: "its best to not force any navigation"');
    settle();
  });

  testWidgets('a badge says what the row is about, and cannot be pressed',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(tester);
    expect(find.text('Equation'), findsNothing);
    app.insertEquation(at: const Offset(20, 20));
    registerEditor();
    await tester.pumpAndSettle();

    final badge = find.ancestor(
        of: find.byTooltip('Esc when you are done'),
        matching: find.byType(ExcludeFocus));
    expect(badge, findsOneWidget, reason: 'the badge is up');
    expect(
        find.descendant(of: badge, matching: find.byType(InkWell)),
        findsNothing,
        reason: 'nothing to press means nothing to be moved onto');
    settle();
  });

  testWidgets('and the row goes back to the page when the equation is done',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(tester);
    final b = app.insertEquation(at: const Offset(20, 20));
    registerEditor();
    await tester.pumpAndSettle();
    expect(find.byType(MathBar), findsOneWidget);

    app.select(b.id, edit: false);
    app.clearActiveMath('test');
    await tester.pumpAndSettle();
    expect(find.byType(MathBar), findsNothing,
        reason: 'buttons that act on nothing are worse than no buttons');
    expect(find.byType(PageFace), findsOneWidget,
        reason: 'the row is the page\'s again, not blank');
    settle();
  });

  testWidgets('the row drives whichever equation is open', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final inserted = <MathItem>[];
    var toggled = 0;
    await pump(tester);
    app.insertEquation(at: const Offset(20, 20));
    registerEditor(inserted: inserted, onToggle: () => toggled++);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('fraction (1/2)'));
    await tester.pumpAndSettle();
    expect(inserted.single.id, 'frac');

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Write the LaTeX by hand'));
    await tester.pumpAndSettle();
    expect(toggled, 1);
    settle();
  });

  testWidgets('the chrome is the same height in every state', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(tester);
    final resting = tester.getSize(find.byType(Column).first).height;

    app.insertEquation(at: const Offset(20, 20));
    registerEditor();
    await tester.pumpAndSettle();
    final writing = tester.getSize(find.byType(Column).first).height;

    expect(writing, resting,
        reason: 'the canvas box must not move when an equation opens \u2014 that '
            'is what makes "do not move the user" a property of the layout '
            'rather than a promise somebody has to keep');
    settle();
  });

  testWidgets('the block editor puts itself on the toolbar, and takes itself '
      'off again', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The seam between the two halves: the tab is useless if the editor never
    // registers, and it acts on a dead editor if the editor never unregisters.
    final block = app.insertEquation(at: const Offset(20, 20));
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
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
    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(body: SizedBox())));
    await tester.pumpAndSettle();
    expect(app.activeMath, isNull,
        reason: 'the tab would otherwise drive an editor that is gone');
    settle();
  });

  group('what the toolbar actually reaches, not just a stub', () {
    // Every test above stands in for the editor with a hand-rolled
    // `ActiveMathEditor` (see `registerEditor`), which is right for testing
    // the BAR — but it means `drawGraph`/`evaluateAtValue` were never once
    // exercised as the real closures a real block hands the toolbar. These
    // two open an actual `MathBlockView`, pull the closures IT registered,
    // and check a real block lands on the page — the whole seam, end to end.
    testWidgets("Draw the graph makes a real graph block", (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final block = app.insertEquation(at: const Offset(20, 20));
      block.content['latex'] = 'y=3x+10';
      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: SizedBox(width: 500, child: MathBlockView(block: block, app: app)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(app.activeMath?.drawGraph, isNotNull);

      app.activeMath!.drawGraph!();
      await tester.pumpAndSettle();

      final graphs = app.blocks.where((b) => b.type == BlockType.graph);
      expect(graphs.length, 1);
      expect(graphs.single.content['from'], block.id);
      expect(graphs.single.content['latex'], 'y=3x+10');
      settle();
    });

    testWidgets("Evaluate at a value makes a real substitute block",
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final block = app.insertEquation(at: const Offset(20, 20));
      block.content['latex'] = 'y=3x+10';
      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: SizedBox(width: 500, child: MathBlockView(block: block, app: app)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(app.activeMath?.evaluateAtValue, isNotNull);

      app.activeMath!.evaluateAtValue!();
      await tester.pumpAndSettle();

      final subs = app.blocks.where((b) => b.type == BlockType.substitute);
      expect(subs.length, 1);
      expect(subs.single.content['from'], block.id);
      expect(subs.single.content['latex'], 'y=3x+10');
      settle();
    });

    testWidgets('an empty equation offers neither, silently', (tester) async {
      // Reachable but harmless: an equation with nothing in it must not
      // scatter an empty graph or substitute block across the page just
      // because a menu happened to be enabled.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final block = app.insertEquation(at: const Offset(20, 20));
      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: SizedBox(width: 500, child: MathBlockView(block: block, app: app)),
        ),
      ));
      await tester.pumpAndSettle();

      app.activeMath?.drawGraph?.call();
      app.activeMath?.evaluateAtValue?.call();
      await tester.pumpAndSettle();

      expect(app.blocks.where((b) => b.type == BlockType.graph), isEmpty);
      expect(app.blocks.where((b) => b.type == BlockType.substitute), isEmpty);
      settle();
    });
  });

  group('what the bar itself offers', () {
    // Round two of this bar measured 1725-2230 px against a 1280 px default
    // window, with no scrollbar and a dead mouse wheel, so the search box and
    // the LaTeX escape hatch were simply off the edge. These keep it honest.

    Future<void> pumpBar(
      WidgetTester tester, {
      required ValueChanged<MathItem> onInsert,
      bool latexMode = false,
      VoidCallback? onToggle,
      VoidCallback? onDrawGraph,
      VoidCallback? onEvaluateAtValue,
      List<String> recents = const ['theta', 'pi'],
    }) async {
      widen(tester);
      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MathBar(
              latexMode: latexMode,
              recentIds: recents,
              onToggleLatex: onToggle ?? () {},
              onDrawGraph: onDrawGraph,
              onEvaluateAtValue: onEvaluateAtValue,
              onInsert: onInsert,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the whole row fits a 1280 px window', (tester) async {
      await pumpBar(tester, onInsert: (_) {});
      final w = tester.getSize(find.byType(MathBar)).width;
      // Measured, and reported here so a regression names its own number.
      // Below this the row scrolls (drag or wheel, added with the doors) —
      // but the first cut was 1725-2230 px with NO scroll at all, and half of
      // "chaotic" was controls the student could not reach.
      //
      // 1150 → 1240 when Graph came out of the `...` fold and onto the row,
      // at the owner's request: *"i dont love the location of the 'graph
      // this' button, isnt super intuitive. Could we maybe break this out
      // into its own button?"* It costs 72 px of what was 135 px of
      // headroom. The row still fits a 1280 window; there is simply less
      // room than there was, and the next thing that wants a place on it has
      // to take something else off.
      expect(w, lessThan(1240),
          reason: 'measured ' + w.toString() + ' px; the row has to fit the '
              'smallest window the app opens, which is 1280');
    });

    testWidgets('the row carries no answer readout at all any more',
        (tester) async {
      // It used to hold a live `= 42` slot. The owner found the top of the
      // window an unintuitive place for an answer, so it moved to the caret
      // (`= ` writes it) and the row lost a control rather than gaining one.
      await pumpBar(tester, onInsert: (_) {});
      expect(find.textContaining('='), findsNothing,
          reason: 'no readout, and nothing left behind where it stood');
    });

    testWidgets('every quick shape draws as notation, not as source',
        (tester) async {
      await pumpBar(tester, onInsert: (_) {});
      expect(find.byType(MathSourceFallback), findsNothing);
      for (final id in kMathQuickShapes) {
        final item = mathItemsById[id]!;
        // `name (\x)` — the owner's format: one label to read, not a
        // sentence with an instruction buried in the middle of it.
        final tip = item.typeIt == null
            ? item.name
            : item.name + ' (' + item.typeIt! + ')';
        expect(find.byTooltip(tip), findsOneWidget,
            reason: id + ' is missing from the quick shapes');
      }
    });

    testWidgets('the shapes are all one size, so the row is not ragged',
        (tester) async {
      await pumpBar(tester, onInsert: (_) {});
      final widths = <double>{};
      for (final chip in find.byType(MathChip).evaluate()) {
        widths.add(tester.getSize(find.byWidget(chip.widget)).width);
      }
      expect(widths.length, 1,
          reason: 'ragged widths were half of what read as chaotic: ' +
              widths.toString());
    });

    testWidgets('a door opens a GRID and inserts on tap', (tester) async {
      MathItem? got;
      await pumpBar(tester, onInsert: (i) => got = i);
      await tester.tap(find.text('Shapes'));
      await tester.pumpAndSettle();

      // A grid, not a column. Every gallery used to be one symbol per row —
      // Greek was a 1119 px column — because a Container with an alignment
      // expands to fill its loose constraints.
      final rows = <double>{};
      for (final e in find.byType(MathChip).evaluate()) {
        rows.add(tester.getTopLeft(find.byWidget(e.widget)).dy);
      }
      final chips = find.byType(MathChip).evaluate().length;
      expect(rows.length, lessThan(chips),
          reason: chips.toString() + ' chips on ' + rows.length.toString() +
              ' rows is a column, not a grid');

      // `\rt` is the advertised route now; `\root` still works but is not
      // what the tooltip teaches.
      await tester.tap(find.byTooltip(r'nth root (\rt)').first);
      await tester.pumpAndSettle();
      expect(got?.id, 'nthroot');
    });

    testWidgets('there is a door for each kind of thing', (tester) async {
      // The owner, on the single Symbols door: "We have more space to play
      // with in that bar than your using, so we can break symbols,
      // opperators, large opperators, functions, etc out into their own
      // things." A door named for what is behind it is a shorter path than a
      // search box, for anyone who can see the door.
      await pumpBar(tester, onInsert: (_) {});
      for (final door in kMathDoors) {
        expect(find.text(door.label), findsOneWidget,
            reason: door.label + ' is missing from the row');
        expect(mathDoorItems(door), isNotEmpty,
            reason: door.label + ' opens on nothing');
      }
    });

    testWidgets('the search finds a symbol by name, whichever door it is in',
        (tester) async {
      MathItem? got;
      await pumpBar(tester, onInsert: (i) => got = i);
      await tester.tap(find.byTooltip('Find a symbol by name'));
      await tester.pumpAndSettle();
      // It opens on what you used lately, which is the other half of "I know
      // I had it a minute ago".
      expect(find.text('Recent'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'not equal');
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(got?.id, 'neq');
    });

    testWidgets('every door wears a drop-down arrow', (tester) async {
      // The owner: "id like a little arrow on the menu buttons up top when
      // there is a drop down to make it clear they are a menu." Without one a
      // door is indistinguishable from the chips beside it, every one of
      // which inserts something on the first click.
      await pumpBar(tester, onInsert: (_) {});
      final arrows = find.descendant(
        of: find.byType(MathBar),
        matching: find.byIcon(Icons.arrow_drop_down),
      );
      expect(arrows, findsNWidgets(kMathDoors.length + 1),
          reason: 'one per door, plus the search');
    });

    testWidgets('clicking a second door opens it in the SAME click',
        (tester) async {
      // A modal barrier swallows that first press, so it used to take two —
      // close, then open. Measured by what is on screen after ONE tap.
      await pumpBar(tester, onInsert: (_) {});
      await tester.tap(find.text('Greek'));
      await tester.pumpAndSettle();
      expect(find.byType(MathChip), findsWidgets);
      final greekChips = find.byType(MathChip).evaluate().length;

      await tester.tap(find.text('Sets'));
      await tester.pumpAndSettle();
      final setsChips = find.byType(MathChip).evaluate().length;
      expect(setsChips, isNot(greekChips),
          reason: 'one tap has to land on the second door, not just dismiss '
              'the first');
      // And the Sets panel really is the one showing.
      expect(find.byTooltip('is in (' + bs + 'in)'), findsOneWidget);
    });

    testWidgets('clicking the open door again closes it', (tester) async {
      await pumpBar(tester, onInsert: (_) {});
      final closed = find.byType(MathChip).evaluate().length;
      await tester.tap(find.text('Greek'));
      await tester.pumpAndSettle();
      expect(find.byType(MathChip).evaluate().length, greaterThan(closed));
      await tester.tap(find.text('Greek'));
      await tester.pumpAndSettle();
      expect(find.byType(MathChip).evaluate().length, closed);
    });

    testWidgets('the More door groups its three subjects under headings',
        (tester) async {
      // Most doors are one list and get no heading — a label for the only
      // group on screen is a label for nothing. `More` is three unrelated
      // subjects sharing a door, which is the case that earns them.
      await pumpBar(tester, onInsert: (_) {});
      await tester.tap(find.text('Subjects'));
      await tester.pumpAndSettle();
      expect(find.text('Geometry'), findsOneWidget);
      expect(find.text('Stats'), findsOneWidget);
      expect(find.text('Science'), findsOneWidget);

      // …and a single-subject door does not get one.
      await tester.tap(find.text('Greek'));
      await tester.pumpAndSettle();
      expect(find.text('Greek'), findsOneWidget,
          reason: 'only the door itself, not a heading repeating its name');
    });

    testWidgets('a search miss says so IN the panel, and points somewhere',
        (tester) async {
      await pumpBar(tester, onInsert: (_) {});
      await tester.tap(find.byTooltip('Find a symbol by name'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzzznothing');
      await tester.pumpAndSettle();
      // Where the student is looking, rather than a message that appears
      // somewhere else only after they press Enter.
      expect(find.textContaining('Write the LaTeX by hand'), findsOneWidget);
    });

    testWidgets('the LaTeX view is one item behind the more menu',
        (tester) async {
      var toggled = 0;
      await pumpBar(tester, onInsert: (_) {}, onToggle: () => toggled++);
      expect(find.text('LaTeX'), findsNothing,
          reason: 'a word-labelled button for the escape hatch spends row '
              'width on something most students never press');
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write the LaTeX by hand'));
      await tester.pumpAndSettle();
      expect(toggled, 1);
    });

    testWidgets('Graph is a button on the row, not an item in the fold',
        (tester) async {
      // The owner, having used it: "i dont love the location of the 'graph
      // this' button, isnt super intuitive. Could we maybe break this out
      // into its own button?" It was in the fold because it cost the row no
      // width there — which is a reason to hide a SETTING, not a command
      // that makes something.
      var drawn = 0;
      await pumpBar(tester, onInsert: (_) {}, onDrawGraph: () => drawn++);
      expect(find.text('Graph'), findsOneWidget);
      await tester.tap(find.text('Graph'));
      await tester.pumpAndSettle();
      expect(drawn, 1);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Draw the graph'), findsNothing,
          reason: 'and it is not in both places');
    });

    testWidgets('and it is on the LaTeX face too, or the two disagree',
        (tester) async {
      // Parity is the whole point of the object row: the same equation, the
      // same controls, whichever view of it you are looking at.
      var drawn = 0;
      await pumpBar(tester,
          onInsert: (_) {}, latexMode: true, onDrawGraph: () => drawn++);
      expect(find.text('Graph'), findsOneWidget);
      await tester.tap(find.text('Graph'));
      await tester.pumpAndSettle();
      expect(drawn, 1);
    });

    testWidgets('and in LaTeX mode the row says so in plain words',
        (tester) async {
      await pumpBar(tester, onInsert: (_) {}, latexMode: true);
      expect(find.textContaining('Writing the LaTeX by hand'), findsOneWidget);
      expect(find.byType(MathChip), findsNothing);
    });

    group('evaluating at a value', () {
      // Unlike Graph, this lives in the fold rather than on the row itself —
      // a deliberate, smaller-footprint choice for a second command sharing
      // the same equation, not an oversight; these pin that placement down
      // the same way the Graph tests above pin ITS placement.
      testWidgets('is one item behind the more menu, not a row button',
          (tester) async {
        var evaluated = 0;
        await pumpBar(tester,
            onInsert: (_) {}, onEvaluateAtValue: () => evaluated++);
        expect(find.textContaining('Evaluate'), findsNothing,
            reason: 'nothing on the row itself until the menu is opened');

        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Evaluate at a value'), findsOneWidget);
        await tester.tap(find.textContaining('Evaluate at a value'));
        await tester.pumpAndSettle();
        expect(evaluated, 1);
      });

      testWidgets('is greyed out when there is nothing to evaluate',
          (tester) async {
        // Same rule the LaTeX toggle already follows for `latexAvailable`:
        // a menu item that does nothing when pressed is worse than none.
        await pumpBar(tester, onInsert: (_) {}, onEvaluateAtValue: null);
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        final item = tester.widget<PopupMenuItem<String>>(
            find.ancestor(
                of: find.textContaining('Evaluate at a value'),
                matching: find.byType(PopupMenuItem<String>)));
        expect(item.enabled, isFalse);
      });

      testWidgets('is on the LaTeX face too, the same as Graph', (tester) async {
        var evaluated = 0;
        await pumpBar(tester,
            onInsert: (_) {},
            latexMode: true,
            onEvaluateAtValue: () => evaluated++);
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Evaluate at a value'));
        await tester.pumpAndSettle();
        expect(evaluated, 1);
      });
    });
  });
}
