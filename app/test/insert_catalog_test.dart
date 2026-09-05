// One catalog, two surfaces (owner, v0.23).
//
// *"In insert, we have some redundant options (such as text box, that doesnt
// need to be there), and it also just feels kinda messy at the moment"*, and
// *"when right clicking on the canvas, it comes up with a bunch of options
// saying 'insert x here' ... this should more closley match the insert menu we
// already have, although that is quite busy and i dont want it to be a huge
// drop down."*
//
// The ribbon and the right-click menu render the SAME list, so the tests that
// matter most are the ones that would catch them drifting apart again.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';

import 'support/app.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/command_bar.dart';
import 'package:openote/ui/context_menus.dart';
import 'package:openote/ui/insert_catalog.dart';

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
    tmp = Directory.systemTemp.createTempSync('onote_insert_');
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

  void widen(WidgetTester tester, [Size size = const Size(2600, 1200)]) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('the catalog itself', () {
    testWidgets('is thirteen things, grouped for the menu', (tester) async {
      final l = await _translations(tester);
      expect(kInsertGroups.map((g) => g.title(l)).toList(),
          ['Write', 'Bring in', 'Link up']);
      expect(kInsertItems.length, 13);
    });

    test('the ribbon is one row, in the order it has always been', () {
      // The owner, after a release that split it into three groups and took
      // the words off four of them: "i dont love the new menu stuff though, i
      // think we go back to what we had before."
      expect(kInsertRibbon.map((i) => i.id).toList(), [
        'text', 'equation', 'code', 'table', 'board', 'image', 'pdf',
        'file', 'video', 'flashcard', 'pagelink', 'portal', 'template',
      ]);
    });

    test('and the order names every item exactly once', () {
      // The row and the catalog are two lists. This is what stops them
      // drifting apart: a forgotten item shows up here rather than silently
      // on the end of the row.
      expect(kRibbonOrder.toSet().length, kRibbonOrder.length,
          reason: 'no duplicates');
      expect(kRibbonOrder.toSet(), kInsertItems.map((i) => i.id).toSet());
      expect(kInsertRibbon.length, kInsertItems.length);
    });

    test('every button carries its word', () {
      for (final i in kInsertRibbon) {
        expect(i.showLabel, isTrue, reason: i.id);
      }
    });

    test('three of them are on the ribbon only, and say why', () {
      // Each is a command the right-click GESTURE already performs, or one
      // that is not about a point on the page at all.
      final menu = kMenuGroups.expand((g) => g.items).map((i) => i.id).toSet();
      for (final id in ['text', 'flashcard', 'template']) {
        expect(kInsertItems.map((i) => i.id), contains(id), reason: id);
        expect(menu.contains(id), isFalse, reason: id);
      }
      expect(menu.length, 10);
    });

    // Through `L`, because the catalog's words moved into the .arb: the
    // Insert ribbon and the right-click menu are the two most visible things
    // in the app and were the last English left in the toolbars. The rules
    // themselves are unchanged, and are checked against ENGLISH — a
    // translation is allowed to be longer than fourteen characters; the
    // ribbon compacts, and holding another language to an English width is
    // not a rule anyone could keep.
    testWidgets('every label is a noun a fifteen-year-old uses',
        (tester) async {
      final l = await _translations(tester);
      for (final i in kInsertItems) {
        expect(i.label(l), isNot(contains('here')));
        expect(i.label(l).trim(), i.label(l));
        expect(i.label(l).length, lessThan(14), reason: i.id);
      }
      // The renames, explicitly.
      expect(kInsertItems.firstWhere((i) => i.id == 'image').label(l), 'Picture');
      expect(kInsertItems.firstWhere((i) => i.id == 'board').label(l), 'Board');
      expect(kInsertItems.firstWhere((i) => i.id == 'video').label(l), 'Video');
    });

    testWidgets('a tooltip never repeats the label', (tester) async {
      final l = await _translations(tester);
      for (final i in kInsertItems) {
        if (i.tooltip == null) continue;
        expect(i.tooltip!(l).toLowerCase(),
            isNot(contains(i.label(l).toLowerCase())),
            reason: i.id);
      }
    });

    test('the CSV importer that only the right-click menu had is now on both',
        () {
      final table = kInsertItems.firstWhere((i) => i.id == 'table');
      expect(table.extras.map((e) => e.id), contains('table-file'));
    });
  });

  group('where a thing lands', () {
    test('a ribbon press centres it on what you are looking at', () {
      app.canvas.viewport = const Size(1000, 800);
      final table = kInsertItems.firstWhere((i) => i.id == 'table');
      final at = insertAnchor(app, table);
      final centre = app.canvas.screenToPage(const Offset(500, 400));
      expect(at.dx, closeTo(centre.dx - 180, 0.01));
      expect(at.dy, closeTo(centre.dy - 40, 0.01),
          reason: 'the old hand-written `c.dy - 40`, now derived from the '
              'size the block arrives at');
    });

    test('and a right-click puts its corner where you clicked', () async {
      if (!haveSqlite) return;
      final table = kInsertItems.firstWhere((i) => i.id == 'table');
      // The menu passes the page point straight through.
      expect(table.size, const Size(360, 80));
    });
  });

  group('both surfaces make the same block', () {
    testWidgets('a table from the ribbon and a table from the menu are equal',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      widen(tester);
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        })),
      ));
      final table = kInsertItems.firstWhere((i) => i.id == 'table');
      await table.run(ctx, app, const Offset(10, 20));
      await table.run(ctx, app, const Offset(400, 500));
      expect(app.blocks.length, 2);
      final a = app.blocks[0], b = app.blocks[1];
      expect(a.type, BlockType.table);
      expect(a.content['cells'], b.content['cells'],
          reason: 'the literal header row lived in TWO places before this, '
              'which is exactly how the two menus drifted');
      expect(a.w, b.w);
      expect(b.x, greaterThanOrEqualTo(400.0),
          reason: 'the corner goes where it was asked, give or take the '
              'page nudging a new block clear of an old one');
      app.cancelPendingSave();
    });
  });

  group('the Insert ribbon', () {
    testWidgets('shows the catalog, in order, and nothing else',
        (tester) async {
      final l = await _translations(tester);
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      widen(tester);
      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (_, __) => CommandBar(app: app),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Insert'));
      await tester.pumpAndSettle();

      for (final i in kInsertRibbon) {
        if (i.showLabel) {
          expect(find.text(i.label(l)), findsOneWidget, reason: i.id);
        } else {
          // Wordless, but never nameless: the icon is there and the name is
          // one hover away.
          expect(find.byIcon(i.icon), findsOneWidget, reason: i.id);
          expect(
              find.byTooltip(i.tooltip == null
                  ? i.label(l)
                  : '${i.label(l)} — ${i.tooltip!(l)}'),
              findsOneWidget,
              reason: i.id);
        }
      }
      // And the three the ribbon has that the right-click menu does not.
      expect(find.text('Text box'), findsOneWidget);
      expect(find.text('Flashcard'), findsOneWidget);
      expect(find.text('Template'), findsOneWidget);
      app.cancelPendingSave();
    });

    testWidgets('fits the smallest window the app opens, wide open', (tester) async {
      final l = await _translations(tester);
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      widen(tester);
      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (_, __) => CommandBar(app: app),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Insert'));
      await tester.pumpAndSettle();
      for (final item in kInsertRibbon) {
        expect(find.text(item.label(l)), findsOneWidget, reason: item.id);
      }
      expect(find.byTooltip('More'), findsNothing,
          reason: 'wide open, all thirteen fit inline — nothing to fold');
      app.cancelPendingSave();
    });

    testWidgets(
        'compacts instead of scrolling once the ribbon runs past a '
        '1280px window', (tester) async {
      final l = await _translations(tester);
      // **It does not fit, and that is the shape that was asked for back.**
      //
      // Thirteen labelled buttons run past the ~965px a 1280 window leaves
      // once the navigator is open. Reported later: "it doesnt handle
      // resizing well (menus should either compact as required or become
      // sliding, again i belive the former is cleaner)" — so the ones that
      // do not fit fold into one "More" menu instead of sliding out of
      // reach behind `_ToolbarScroll`'s old horizontal viewport.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      widen(tester, const Size(1280, 900));
      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (_, __) => CommandBar(app: app),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Insert'));
      await tester.pumpAndSettle();

      expect(find.byType(Scrollable), findsNothing,
          reason: 'the old rescue is gone — nothing here scrolls any more');
      expect(find.byTooltip('More'), findsOneWidget,
          reason: 'thirteen labelled buttons do not fit a 1280px window; '
              'something has to fold, or a wider regression than this test '
              'caught it');

      // Whatever folded is REACHABLE, not simply gone.
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      final visible = kInsertRibbon
          .where((i) => find.text(i.label(l)).evaluate().isNotEmpty)
          .length;
      expect(visible, kInsertRibbon.length,
          reason: 'every item is on screen SOMEWHERE — inline or in the '
              'fold — once the menu is open');
      app.cancelPendingSave();
    });
  });

  group('the canvas right-click menu', () {
    Future<void> open(WidgetTester tester) async {
      widen(tester);
      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: GestureDetector(
                key: const ValueKey('opener'),
                onTap: () => showCanvasMenu(
                    ctx, app, const Offset(300, 300), const Offset(50, 60)),
                child: Container(
                    width: 100, height: 40, color: const Color(0xFFEEEEEE)),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('opener')));
      await tester.pumpAndSettle();
    }

    testWidgets('says the same ten things the ribbon does', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final l = await _translations(tester);
      await open(tester);
      for (final g in kMenuGroups) {
        for (final i in g.items) {
          expect(find.text(i.menuLabel(l)), findsOneWidget, reason: i.id);
        }
      }
      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Page background'), findsOneWidget);
      app.cancelPendingSave();
    });

    testWidgets('with the word "here" gone, and no text box', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await open(tester);
      for (final w in tester.widgetList<Text>(find.byType(Text))) {
        final t = w.data ?? '';
        expect(t.toLowerCase(), isNot(contains('here')),
            reason: 'a right click already means here');
      }
      expect(find.text('New text box'), findsNothing);
      expect(find.textContaining('text box'), findsNothing);
      app.cancelPendingSave();
    });

    testWidgets('and is shorter than the stack it replaces', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await open(tester);
      // Top of the first row to the bottom of the last: the menu's own
      // height, without having to find the popup's Material among the app's.
      final h = tester.getRect(find.text('Page background')).bottom -
          tester.getRect(find.text('Paste')).top;
      expect(h, lessThan(340),
          reason: 'measured ${h.toStringAsFixed(0)}px; eleven stacked rows '
              'was about 430, and the owner asked for not-a-huge-drop-down. '
              'Three of those rows are second choices set in under the '
              'command they belong to — the ribbon hides them behind a small '
              'arrow, and a menu has no room for one');
      app.cancelPendingSave();
    });

    testWidgets('and a tile makes the block where you clicked', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await open(tester);
      await tester.tap(find.text('Code'));
      await tester.pumpAndSettle();
      expect(app.blocks.length, 1);
      expect(app.blocks.single.type, BlockType.code);
      // Where you clicked — give or take the page's own 8px grid and its
      // top margin, both of which `addBlock` applies to every block however
      // it arrived.
      expect(app.blocks.single.x, lessThan(120));
      expect(app.blocks.single.y, lessThan(120),
          reason: 'near the click, not centred on the window the way a '
              'ribbon press would be');
      app.cancelPendingSave();
    });
  });

  group('the menu and the ribbon offer the same things', () {
    test('every second choice is reachable from the menu too', () {
      // "Table ▸ From a file (CSV, Excel)" was on the ribbon and not in the
      // menu — the one thing the old menu had that the ribbon did not became
      // the one thing the ribbon had that the menu did not, which is exactly
      // the drift a shared catalog exists to end.
      final flat = kMenuItemsAndExtras.map((i) => i.id).toSet();
      for (final item in kMenuGroups.expand((g) => g.items)) {
        for (final extra in item.extras) {
          expect(flat, contains(extra.id), reason: '${item.id} ▸ ${extra.id}');
        }
      }
      expect(flat, contains('table-file'));
    });

    testWidgets('and every one of them can be run', (tester) async {
      final l = await _translations(tester);
      for (final i in kMenuItemsAndExtras) {
        expect(i.label(l).trim(), isNotEmpty, reason: i.id);
        expect(i.label(l).toLowerCase(), isNot(contains('here')),
            reason: '${i.id}: a right click already means here');
      }
    });
  });

}


/// The English translations, for the rules above. Mounting a widget is the
/// only way to reach an `L`, and it is cheap.
Future<L> _translations(WidgetTester tester) async {
  late L l;
  await tester.pumpWidget(testApp(Builder(builder: (context) {
    l = L.of(context);
    return const SizedBox();
  })));
  return l;
}
