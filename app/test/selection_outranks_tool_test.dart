// Something selected is something you picked up, whatever is in your hand.
//
// The owner, after the side-button lasso started working: *"One issue though
// is that it doesnt seem to hold the selection after releasing the button. I
// suspect this is because it puts it right into draw mode again, this isnt
// what it should do. Whenever something on the page is selected (such that it
// is moveable, NOT when in editing mode) then pen should act as regular touch
// input, moving the selected items when dragged. I guess though ideally if
// some items are selected but i start using the pen elsewhere on the page
// (i.e. not within the selection zone) it should at minimum deselect the
// items, although ideally also start drawing as if they wernt selected."*
//
// Two separate causes, both here: the selection was being THROWN AWAY by the
// tool coming back (`AppState.setTool`), and even kept it had no way to be
// dragged under a drawing tool (`PageCanvas._selectionTakes`).
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/ink/ink_storage.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/app.dart';
import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;

  setUp(() {
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_seltool_');
  });

  tearDown(() {
    AppState.syncLogEnabled = true;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> openPage(WidgetTester t) async {
    await t.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Ink');
      app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      await app.selectPage(
          app.nodes.where((n) => n.kind == NodeKind.page).first.id);
    });
    await t.pumpWidget(testApp(Scaffold(
      body: SizedBox(
        width: 800,
        height: 600,
        child: ListenableBuilder(
          listenable: app,
          builder: (_, __) => PageCanvas(state: app),
        ),
      ),
    )));
    await t.pump();
    await t.pump();
  }

  Future<void> drag(WidgetTester t, Offset from, Offset to,
      {PointerDeviceKind kind = PointerDeviceKind.stylus}) async {
    // Which handler wraps the canvas is decided at build time from `app.tool`,
    // so a tool set a line ago is not in the tree until this.
    await t.pump();
    final g = await t.startGesture(from, kind: kind);
    for (var i = 1; i <= 4; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 4)!);
      await t.pump();
    }
    await g.up();
    await t.pump();
    app.cancelPendingSave();
  }

  List<Block> ink() =>
      app.blocks.where((b) => b.type == BlockType.ink).toList();

  /// One stroke, selected, with the pen in hand — where the report starts.
  Future<Block> aSelectedStroke(WidgetTester t) async {
    app.setTool(Tool.pen);
    await drag(t, const Offset(200, 200), const Offset(260, 215));
    final b = ink().single;
    app.selectMany([b.id]);
    await t.pump();
    return b;
  }

  testWidgets('A DRAG INSIDE THE SELECTION MOVES IT, PEN IN HAND', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    final b = await aSelectedStroke(t);
    final x0 = b.x, y0 = b.y;

    await drag(t, const Offset(230, 207), const Offset(270, 247));

    // Forty screen pixels is forty page units only at 100%: the drag moves
    // what was dragged, not what the screen measured.
    final moved = 40 / app.canvas.scale;
    final after = ink().single;
    expect(after.id, b.id, reason: 'the same stroke, moved rather than redrawn');
    expect(after.x, closeTo(x0 + moved, 1.5));
    expect(after.y, closeTo(y0 + moved, 1.5));
    expect(ink(), hasLength(1), reason: 'and nothing was drawn doing it');
  });

  testWidgets('A PRESS ANYWHERE ELSE PUTS IT DOWN AND DRAWS', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    final b = await aSelectedStroke(t);
    final x0 = b.x;

    await drag(t, const Offset(520, 420), const Offset(560, 440));

    expect(app.selectedIds, isEmpty, reason: 'the selection was put down');
    expect(ink(), hasLength(2), reason: 'and the pen drew, as it would have '
        'done if nothing had been selected at all');
    expect(ink().firstWhere((x) => x.id == b.id).x, x0,
        reason: 'the one that was selected did not move an inch');
  });

  testWidgets('THE TOOL COMING BACK DOES NOT THROW THE SELECTION AWAY',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    final b = await aSelectedStroke(t);

    // What a side button does on the way out and back: the lasso is handed
    // over, makes a selection, and hands the pen back.
    app.setTool(Tool.lasso, automatic: true);
    app.selectMany([b.id]);
    app.setTool(Tool.pen, automatic: true);
    expect(app.selectedIds, contains(b.id),
        reason: 'letting go of the button is not a decision to drop it');

    // Choosing a tool still is one.
    app.setTool(Tool.pen);
    expect(app.selectedIds, isEmpty,
        reason: 'reaching for the pen in the toolbar means you are done');
  });

  testWidgets('an eraser aimed into a selection still rubs out', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    final b = await aSelectedStroke(t);
    final x0 = b.x;
    // Whole strokes, so what the gesture did is unambiguous.
    app.setEraserMode(EraserMode.stroke);
    // As a side button hands it over, with the selection still live.
    app.setTool(Tool.eraser, automatic: true);
    await t.pump();

    await drag(t, const Offset(230, 207), const Offset(240, 210));

    // Either the block went with its last stroke or it is standing there
    // empty; both are "rubbed out". What it must not be is moved.
    final left = ink();
    expect(left.expand((b) => InkStorage.strokesOf(b.content)), isEmpty,
        reason: 'rubbed out');
    if (left.isNotEmpty) {
      expect(left.single.x, x0, reason: 'and not shoved about instead');
    }
  });

  testWidgets('a box being typed into is not something you picked up',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await openPage(t);
    final box = app.addBlock(Block(
        type: BlockType.text, x: 120, y: 120, w: 300, content: {'text': 'hi'}));
    app.select(box.id, edit: true);
    app.setTool(Tool.pen, automatic: true);
    await t.pump();
    await t.pump();

    // Inside the box, which is selected — but the caret is in it, and writing
    // on a box you are typing in is drawing, not dragging. Through the
    // controller, because where page (200, 140) lands on the screen is the
    // page's business.
    final at = app.canvas.pageToScreen(const Offset(200, 140));
    expect(app.blockRect(app.blocks.firstWhere((x) => x.id == box.id))
        .contains(const Offset(200, 140)), isTrue,
        reason: 'the press lands inside the selection, or this test proves '
            'nothing about the rule it is here for');
    await drag(t, at, at + const Offset(60, 15));

    expect(ink(), hasLength(1), reason: 'the pen drew over it');
    expect(app.blocks.firstWhere((x) => x.id == box.id).x, 120,
        reason: 'and the box stayed where it was');
  });
}
