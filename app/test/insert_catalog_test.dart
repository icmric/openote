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

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/command_bar.dart';
import 'package:openote/ui/command_button.dart';
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
    test('is ten things in three groups', () {
      expect(kInsertGroups.map((g) => g.title).toList(),
          ['Write', 'Bring in', 'Link up']);
      expect(kInsertItems.length, 10);
      expect(kInsertItems.map((i) => i.id).toList(), [
        'equation', 'table', 'code', 'board',
        'image', 'pdf', 'video', 'file',
        'pagelink', 'portal',
      ]);
    });

    test('and no longer offers what something else already does better', () {
      final ids = kInsertItems.map((i) => i.id).toSet();
      expect(ids.contains('text'), isFalse,
          reason: 'a left click on the canvas already makes a text box, and '
              'the Draw tab has the deliberate version');
      expect(ids.contains('flashcard'), isFalse,
          reason: "Home's card button reads the line you are on");
      expect(ids.contains('template'), isFalse,
          reason: 'laying out a whole page is not adding something to it');
    });

    test('every label is a noun a fifteen-year-old uses', () {
      for (final i in kInsertItems) {
        expect(i.label, isNot(contains('here')));
        expect(i.label.trim(), i.label);
        expect(i.label.length, lessThan(14), reason: i.id);
      }
      // The renames, explicitly.
      expect(kInsertItems.firstWhere((i) => i.id == 'image').label, 'Picture');
      expect(kInsertItems.firstWhere((i) => i.id == 'board').label, 'Board');
      expect(kInsertItems.firstWhere((i) => i.id == 'video').label, 'Video');
    });

    test('a tooltip never repeats the label', () {
      for (final i in kInsertItems) {
        if (i.tooltip == null) continue;
        expect(i.tooltip!.toLowerCase(), isNot(contains(i.label.toLowerCase())),
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
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
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
      await tester.tap(find.text('Insert'));
      await tester.pumpAndSettle();

      for (final i in kInsertItems) {
        if (i.showLabel) {
          expect(find.text(i.label), findsOneWidget, reason: i.id);
        } else {
          // Wordless, but never nameless: the icon is there and the name is
          // one hover away.
          expect(find.byIcon(i.icon), findsOneWidget, reason: i.id);
          expect(
              find.byTooltip(i.tooltip == null
                  ? i.label
                  : '${i.label} — ${i.tooltip}'),
              findsOneWidget,
              reason: i.id);
        }
      }
      expect(find.text('Text box'), findsNothing);
      expect(find.text('Flashcard'), findsNothing);
      expect(find.text('Template'), findsNothing);
      app.cancelPendingSave();
    });

    testWidgets('and fits the smallest window the app opens', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
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
      await tester.tap(find.text('Insert'));
      await tester.pumpAndSettle();
      // The run has to clear a 1280 window with the navigator open (~965
      // usable). Measured end to end: the left edge of the first control to
      // the right edge of the last.
      final first = tester.getRect(find.ancestor(
          of: find.text(kInsertItems.first.label),
          matching: find.byType(CommandButton)));
      final last = tester.getRect(find.ancestor(
          of: find.text(kInsertItems.last.label),
          matching: find.byType(CommandButton)));
      final total = last.right - first.left;
      expect(total, lessThan(965),
          reason: 'measured ${total.toStringAsFixed(0)}px; the old flat row '
              'of thirteen measured 1217 against a 965 window');
      app.cancelPendingSave();
    });
  });

  group('the canvas right-click menu', () {
    Future<void> open(WidgetTester tester) async {
      widen(tester);
      await tester.pumpWidget(MaterialApp(
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
      await open(tester);
      for (final i in kInsertItems) {
        expect(find.text(i.menuLabel), findsOneWidget, reason: i.id);
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
      final flat = kInsertItemsAndExtras.map((i) => i.id).toSet();
      for (final item in kInsertItems) {
        for (final extra in item.extras) {
          expect(flat, contains(extra.id), reason: '${item.id} ▸ ${extra.id}');
        }
      }
      expect(flat, contains('table-file'));
    });

    test('and every one of them can be run', () {
      for (final i in kInsertItemsAndExtras) {
        expect(i.label.trim(), isNotEmpty, reason: i.id);
        expect(i.label.toLowerCase(), isNot(contains('here')),
            reason: '${i.id}: a right click already means here');
      }
    });
  });

}
