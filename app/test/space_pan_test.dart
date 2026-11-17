// §1.15 / #20: holding Space turns a drag into a pan, with any pointer.
//
// Middle-drag pans, two fingers pan, the wheel scrolls — and a graphics
// tablet has none of those, so a pen could only move round the page by the
// scroll bar. Space is the convention in drawing programs and free here (Alt
// already moves a text box). Over a box, the box must not move or open; with
// the pen in hand, nothing is drawn; and a Space typed into a box is a space.
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/l10n/l10n.dart';
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
  late Block box;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_spacepan_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('S');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    await app
        .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
    box = Block(
        type: BlockType.text,
        x: 200,
        y: 200,
        w: 300,
        h: 160,
        content: {'text': 'over a box', 'autoWidth': false});
    app.addBlock(box, recordUndo: false);
    app.select(null);
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

  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) =>
              SizedBox(width: 900, height: 700, child: PageCanvas(state: app)),
        ),
      ),
    ));
    await t.pump();
    await t.pump();
  }

  Block at() => app.blocks.firstWhere((b) => b.id == box.id);
  Offset boxCentre() =>
      app.canvas.pageToScreen(Offset(at().x + at().w / 2, at().y + 40));
  int strokes() => app.blocks.where((b) => b.type == BlockType.ink).length;

  Future<void> drag(WidgetTester t, Offset from, Offset by,
      {PointerDeviceKind kind = PointerDeviceKind.mouse}) async {
    final g = await t.startGesture(from, kind: kind);
    for (var i = 1; i <= 6; i++) {
      await g.moveTo(from + by * (i / 6));
      await t.pump();
    }
    await g.up();
    await t.pump();
  }

  testWidgets('Space-drag over a box pans, and leaves the box alone',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t);
    final before = app.canvas.offset;
    final where = (at().x, at().y);
    await t.sendKeyDownEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(find.byKey(const ValueKey('space-pan')), findsOneWidget);
    await drag(t, boxCentre(), const Offset(-120, -80));
    await t.sendKeyUpEvent(LogicalKeyboardKey.space);
    await t.pump();

    expect(app.canvas.offset - before, const Offset(-120, -80),
        reason: 'the page follows the pointer');
    expect((at().x, at().y), where, reason: 'the box did not move');
    expect(app.editingBlockId, isNull, reason: 'nor did it open');
    expect(find.byKey(const ValueKey('space-pan')), findsNothing,
        reason: 'gone once Space is up');
  });

  testWidgets('with the pen in hand, a Space-drag draws nothing', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.tool = Tool.pen;
    await pump(t);
    final before = app.canvas.offset;
    final ink = strokes();
    await t.sendKeyDownEvent(LogicalKeyboardKey.space);
    await t.pump();
    await drag(t, const Offset(560, 450), const Offset(-60, -40),
        kind: PointerDeviceKind.stylus);
    await t.sendKeyUpEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(app.canvas.offset - before, const Offset(-60, -40));
    expect(strokes(), ink, reason: 'no stroke');

    // And without Space the pen draws, as it always did.
    await drag(t, const Offset(560, 450), const Offset(-60, -40),
        kind: PointerDeviceKind.stylus);
    await t.pump(const Duration(seconds: 3));
    expect(strokes(), greaterThan(ink));
  });

  testWidgets('letting go of Space mid-drag finishes the pan', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t);
    final before = app.canvas.offset;
    await t.sendKeyDownEvent(LogicalKeyboardKey.space);
    await t.pump();
    final g = await t.startGesture(const Offset(560, 450));
    await g.moveTo(const Offset(540, 450));
    await t.pump();
    await t.sendKeyUpEvent(LogicalKeyboardKey.space);
    await t.pump();
    await g.moveTo(const Offset(510, 450));
    await t.pump();
    await g.up();
    await t.pump();
    expect(app.canvas.offset - before, const Offset(-50, 0));
    expect(find.byKey(const ValueKey('space-pan')), findsNothing);
  });

  testWidgets('a Space typed into a box is a space, not a pan', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t);
    app.select(box.id, edit: true);
    await t.pump();
    await t.pump();
    expect(app.editingBlockId, box.id);
    await t.sendKeyDownEvent(LogicalKeyboardKey.space);
    await t.pump();
    expect(find.byKey(const ValueKey('space-pan')), findsNothing);
    await t.sendKeyUpEvent(LogicalKeyboardKey.space);
  });
}
