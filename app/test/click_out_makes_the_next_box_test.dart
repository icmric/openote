// Writing somewhere, then clicking the page, means "and now here".
//
// The owner: *"If i am in a box and click out onto the canvas, it should auto
// create a new content box rather than unfocusing the current box, then
// requiring another click to create a new box."*
//
// The old rule spent the first click closing the box you had already finished
// with, which is not a thing anybody sets out to do — you click the page
// because you want to write there. Driven through the real shell and a real
// tap, because the whole claim is about what one pointer-up does.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';

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
    tmp = Directory.systemTemp.createTempSync('onote_clickout_');
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

  Future<void> pumpShell(WidgetTester tester, List<Block> blocks) async {
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    app.importPage(app.notebookId!, page.id, blocks, PageProps());
    app.reloadNodes();
    await app.selectPage(page.id);
    app.markOnboardingSeen();
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      home: AppShell(app: app),
    ));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
  }

  Block note(String text, {double y = 120}) => Block(
        type: BlockType.text,
        x: 80,
        y: y,
        w: 300,
        h: 44,
        content: {'text': text, 'autoWidth': false},
      );

  /// A point on the canvas well clear of anything on the page.
  Offset emptyCanvas(WidgetTester tester) {
    final r = tester.getRect(find.byType(PageCanvas));
    return Offset(r.left + r.width * 0.55, r.top + r.height * 0.72);
  }

  Future<void> tapEmpty(WidgetTester tester) async {
    await tester.tapAt(emptyCanvas(tester));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  testWidgets('clicking the page from inside a box starts the next one',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(tester, [note('hello')]);
    final first = app.blocks.single.id;

    await tester.tap(find.text('hello').first);
    await tester.pumpAndSettle();
    expect(app.editingBlockId, first, reason: 'in the box');

    await tapEmpty(tester);

    expect(app.blocks.length, 2,
        reason: 'one click, one new box — it used to take two, and the '
            'first one did nothing you asked for');
    final next = app.blocks.firstWhere((b) => b.id != first);
    expect(app.editingBlockId, next.id, reason: 'and the caret is in it');
    expect(app.pendingEmptyBlockId, next.id,
        reason: 'the same no-chrome box a click on empty page has always '
            'made, not a second kind of new box');
    app.cancelPendingSave();
  });

  testWidgets('and clicking on from an empty one leaves nothing behind',
      (tester) async {
    // The reason this is safe to do at all: a text box exited with nothing
    // in it removes itself, so clicking about the page moves ONE empty box
    // around rather than dropping a trail of them.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(tester, [note('hello')]);

    await tester.tap(find.text('hello').first);
    await tester.pumpAndSettle();
    await tapEmpty(tester);
    expect(app.blocks.length, 2);

    // A second click somewhere else, with the new box still empty.
    final r = tester.getRect(find.byType(PageCanvas));
    await tester.tapAt(Offset(r.left + r.width * 0.30, r.top + r.height * 0.55));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(app.blocks.length, 2,
        reason: 'still two: the empty one was taken away as the next one '
            'was made');
    expect(app.blocks.where((b) => b.id != app.editingBlockId).single.content,
        containsPair('text', 'hello'),
        reason: 'and the one with writing in it is untouched');
    app.cancelPendingSave();
  });

  testWidgets('a block merely SELECTED is still put down by the first click',
      (tester) async {
    // A different gesture with a different meaning: you picked a block up to
    // move or restyle it, and clicking the page is how you put it down. Only
    // being INSIDE a box means "and now here".
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(tester, [note('hello')]);
    final first = app.blocks.single.id;

    app.select(first); // selected, not editing
    await tester.pumpAndSettle();
    expect(app.editingBlockId, isNull);

    await tapEmpty(tester);

    expect(app.blocks.length, 1, reason: 'no new box');
    expect(app.selectedIds, isEmpty, reason: 'it was put down');
    app.cancelPendingSave();
  });
}
