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
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/theme/tokens.dart';
import 'package:openote/ui/command_bar.dart';
import 'package:openote/ui/math_bar.dart';

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

  /// The chrome as the app builds it. There is one band now: the equation
  /// palette borrows the command row rather than sitting on a strip of its
  /// own, and the whole design is that borrowing it moves nobody's tab.
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
    // The row goes back to the tab the student chose - Home, here - rather
    // than to a page face of its own: the equation borrows the command row
    // now that the band below it is gone, and gives it straight back.
    expect(find.byIcon(Icons.format_bold), findsOneWidget,
        reason: 'the row is the chosen tab, not blank');
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

  group('a chip is big enough to read', () {
    // *"The boxes to select maths stuff is quite small, particularly an issue
    // for large operators. I dont know if it would be better to boost the
    // size of all the items or just the large operators, but worth finding a
    // solution."*
    //
    // Both, because measuring says they are one problem: **27 of the 231
    // previews did not fit the old fixed 34x32 cell** and were silently
    // shrunk by the `FittedBox` inside it. The tallest is `\sum` at 37.3px,
    // whose limits stack above and below; the widest is `\gcd(a,b)` at
    // 98.2px. One cell size cannot serve both, so the cell is uniform in
    // height and follows its content in width.

    Future<Size> chip(WidgetTester tester, String id,
        {bool dense = false}) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        theme: onoteTheme(Brightness.light),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MathChip(
                item: mathItemsById[id]!,
                onTap: (_) {},
                surfaces: OnoteSurfaces.light,
                dense: dense),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return tester.getSize(find.byType(MathChip));
    }

    testWidgets('tall enough for a summation, which is what prompted it',
        (tester) async {
      final s = await chip(tester, 'sum');
      // The preview measures 37.3px at 12px type and 40.4 at the 13 it is
      // drawn at now; the old cell was 32 high.
      expect(s.height, greaterThanOrEqualTo(MathChip.roomyHeight));
      expect(s.height, greaterThan(OnoteSize.button),
          reason: 'the old cell was the height of a toolbar button');
    });

    testWidgets('and its width follows what is in it', (tester) async {
      // The part that cannot be done with one number. `\gcd(a,b)` needs
      // nearly three times the width of a `\sum`, and a cell sized for the
      // first would make every panel absurd.
      final sum = await chip(tester, 'sum');
      final gcd = await chip(tester, 'fn-gcd');
      final pi = await chip(tester, 'pi');
      expect(gcd.width, greaterThan(sum.width * 2));
      expect(pi.width, lessThan(gcd.width));
      expect(sum.height, gcd.height,
          reason: 'uniform HEIGHT is what keeps a Wrap of these tidy');
    });

    testWidgets('never past the ceiling, so one template cannot set the width',
        (tester) async {
      // Six rows are wide enough to hit it — the gcd/lcm/max/min/nCr/nPr
      // templates — and they scale down a couple of per cent rather than
      // making every panel as wide as the worst case.
      for (final id in ['fn-gcd', 'fn-lcm', 'fn-nCr', 'fn-nPr']) {
        final s = await chip(tester, id);
        expect(s.width, lessThanOrEqualTo(MathChip.roomyMaxWidth + 4),
            reason: id);
      }
    });

    testWidgets('nothing in the whole table overflows its cell',
        (tester) async {
      for (final item in mathItems) {
        await chip(tester, item.id);
        expect(tester.takeException(), isNull, reason: item.id);
      }
    });

    testWidgets('the four on the command row stay dense', (tester) async {
      // That row is 44px tall and a picker-sized chip would fill it edge to
      // edge. Its four previews are also the four simplest in the table, and
      // the complaint was about the pickers, where the operators live.
      for (final id in kMathQuickShapes) {
        final s = await chip(tester, id, dense: true);
        expect(s.height, OnoteSize.button, reason: id);
      }
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

    testWidgets('given room, every door is on the row', (tester) async {
      // The shape this guard used to have was `width < 1240`, measured at a
      // 2600 px view: a promise that the NATURAL row fits the smallest window
      // the app opens. It was true, and then it stopped being affordable.
      // Round four gave every kind of thing its own named door at the owner's
      // request, which spent the headroom; this guard's own comment said what
      // that cost — "the next thing that wants a place on it has to take
      // something else off". Two things then wanted a place: a Calculus door
      // where `∑ ∫` was, and an Evaluate button whose entire purpose is to
      // not be in a fold. Measured at 1415 px.
      //
      // So the row folds rather than paying, and what is worth guarding
      // changes with it: not a number, but that nothing is ever unreachable.
      // The pair of tests below is that promise at both ends.
      await pumpBar(tester, onInsert: (_) {});
      for (final door in kMathDoors) {
        expect(find.text(door.label), findsOneWidget,
            reason: '${door.label} should be on the row when there is room');
      }
      expect(find.text(kMathFoldLabel), findsNothing,
          reason: 'and the fold does not sit there doing nothing');
    });

    testWidgets('squeezed, the far doors fold and stay reachable',
        (tester) async {
      // 1280 is the smallest window the app opens, and the row is wider than
      // that now. The doors are listed in the order a student meets the
      // topics, so the ones that fold are the far ones.
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MathBar(
              latexMode: false,
              onToggleLatex: () {},
              onInsert: (_) {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'no overflow: the row fits whatever it is given');

      expect(find.text(kMathFoldLabel), findsOneWidget,
          reason: 'something had to fold at this width');
      expect(find.text('Shapes'), findsOneWidget,
          reason: 'the nearest door never folds');
      expect(find.text('Subjects'), findsNothing,
          reason: 'the furthest one goes first');

      // **And the commands keep their places**, which is the whole reason the
      // doors are what folds: Evaluate was taken out of a fold on purpose.
      expect(find.text('Graph'), findsOneWidget);
      expect(find.text('Evaluate'), findsOneWidget);

      // Reachable, not merely alive: the fold's panel is the hidden doors'
      // own contents under their own names.
      await tester.tap(find.text(kMathFoldLabel));
      await tester.pumpAndSettle();
      expect(find.text('Subjects'), findsOneWidget,
          reason: "the folded door's name is the heading over its symbols");
    });

    testWidgets('a panel closes when resizing takes its button away',
        (tester) async {
      // Both directions of the same fault: a panel can outlive the control
      // that opened it. Widen until nothing folds and the fold's own panel
      // would be left showing an empty list; narrow until the open door
      // folds and its panel is left anchored to a button that is gone.
      // `pumpBar` widens to 2600 itself, so the squeeze comes after it.
      await pumpBar(tester, onInsert: (_) {});
      tester.view.physicalSize = const Size(1280, 900);
      await tester.pumpAndSettle();

      // **Counting chips, not finding text.** A door's name appears both as
      // its button on the row and as a heading inside the fold's panel, so
      // `find.text('Subjects')` cannot tell an open panel from a closed one
      // — a first version of this test asserted on it and passed with the
      // fix disabled. Only the quick shapes put a `MathChip` on the row, so
      // the count says whether a panel is up.
      final onRowOnly = kMathQuickShapes.length;
      expect(find.byType(MathChip), findsNWidgets(onRowOnly),
          reason: 'nothing open yet');

      await tester.tap(find.text(kMathFoldLabel));
      await tester.pumpAndSettle();
      expect(find.byType(MathChip).evaluate().length,
          greaterThan(onRowOnly), reason: "the fold's panel is open");

      // Widen past the point where anything folds: the panel it belonged to
      // would now be an empty list under no headings.
      tester.view.physicalSize = const Size(2600, 900);
      await tester.pumpAndSettle();
      expect(find.text(kMathFoldLabel), findsNothing,
          reason: 'nothing folds at this width');
      expect(find.byType(MathChip), findsNWidgets(onRowOnly),
          reason: 'and its panel closed rather than showing nothing');

      // Now the other direction: open a door, then narrow until it folds.
      await tester.tap(find.text('Subjects'));
      await tester.pumpAndSettle();
      expect(find.byType(MathChip).evaluate().length, greaterThan(onRowOnly),
          reason: "Subjects' panel is open");

      tester.view.physicalSize = const Size(900, 900);
      await tester.pumpAndSettle();
      expect(find.text('Subjects'), findsNothing,
          reason: 'its button folded');
      expect(find.byType(MathChip), findsNWidgets(onRowOnly),
          reason: 'and its panel went with it, rather than being left '
              'anchored to a button that no longer exists');
      expect(tester.takeException(), isNull);
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
      // **This used to live in the fold, and these tests used to pin it
      // there** — "a deliberate, smaller-footprint choice for a second
      // command sharing the same equation, not an oversight". The owner
      // reversed it twice over, once gently and once not:
      //
      //   *"this is super helpful and i like it (although its rather buried
      //   away at the moment, this isnt ideal because those who would want it
      //   probably wont just stumble across it)"*
      //
      //   *"We are also hiding this option in a menu, making it hard to find,
      //   anoying to get to, and basically impossible to just stumble across,
      //   which is how most people learn about these features."*
      //
      // Stumbling across it was the requirement the fold could not meet, so
      // it is a labelled button beside Graph — the other thing you can do
      // with the equation you just wrote.
      testWidgets('is a labelled button on the row, beside Graph',
          (tester) async {
        var evaluated = 0;
        await pumpBar(tester,
            onInsert: (_) {}, onEvaluateAtValue: () => evaluated++);
        expect(find.text('Evaluate'), findsOneWidget,
            reason: 'readable without opening anything');
        await tester.tap(find.text('Evaluate'));
        await tester.pumpAndSettle();
        expect(evaluated, 1);
      });

      testWidgets('and is no longer in the fold at all', (tester) async {
        // Two routes to one command is how a menu quietly becomes the place
        // people look first again.
        await pumpBar(tester,
            onInsert: (_) {}, onEvaluateAtValue: () {});
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Evaluate at a value'), findsNothing);
      });

      testWidgets('is on the LaTeX face too, the same as Graph', (tester) async {
        var evaluated = 0;
        await pumpBar(tester,
            onInsert: (_) {},
            latexMode: true,
            onEvaluateAtValue: () => evaluated++);
        await tester.tap(find.text('Evaluate'));
        await tester.pumpAndSettle();
        expect(evaluated, 1);
      });
    });
  });
}
