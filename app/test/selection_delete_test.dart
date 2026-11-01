// A way to get rid of what is selected that is not a key on a keyboard.
//
// The owner: *"With selected ink, there should be a button that comes up to
// delete the selected ink/text/items, currently it only lets us move them and
// it feels like a no brainer to have this as an option."*
//
// Lassoed ink was the worst case. Gathering it, moving it, scaling it and
// recolouring it all worked; the only way to remove it was the Delete key,
// which is not on a tablet somebody is holding in one hand with a pen in the
// other — the exact person the lasso is for.
//
// It later grew too eager, and the same owner said so: *"i would only want
// this to appear when i have multiple things selected rather than also when i
// have a single thing selected, given this means that when im editing a text
// box we have a bin button and the cross button, and the bin button makes it
// feel messy"*. A selected block carries a cross on its own move bar, so one
// selection was offering two ways to delete one thing.
//
// So the rule is "never two deletes for one thing", which keeps both asks:
// the bin is gone for a lone block that has its own cross, and still there
// for a multiple selection — where the cross belongs to the primary block
// alone.
//
// **Which leaves the things that have no cross**, and the rule used to be
// written as though there were none. Handwriting is painted rather than
// built, so a lone stroke has no bar and never had one; and no block shows
// its bar while a drawing tool is in hand, which used to be impossible to
// observe because picking up a pen cleared the selection, and is now
// ordinary — a side-button lasso hands the pen straight back with the
// selection it just made. Both get the floating button, which is the case it
// was built for in the first place: *"When one or more items are selected
// with the lasso, it should have that little delete icon like we have when
// selecting multiple boxes."*

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/app.dart';
import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<AppState> canvas(WidgetTester tester, String name) async {
    late AppState app;
    late Repository repo;
    final tmp = Directory.systemTemp.createTempSync(name);
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Ink');
      app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      await app.selectPage(
          app.nodes.where((n) => n.kind == NodeKind.page).first.id);
    });
    return app;
  }

  Block ink() => Block(
        type: BlockType.ink,
        x: 120,
        y: 140,
        w: 200,
        h: 100,
        content: {
          'strokes': [
            {
              'id': 's1',
              'brush': {
                'tool': 'pen',
                'color': 'auto',
                'size': 3.0,
                'opacity': 1.0
              },
              'x': [120.0, 200.0, 300.0],
              'y': [150.0, 170.0, 150.0],
              'p': <double>[],
            }
          ]
        },
      );

  Future<void> pump(WidgetTester tester, AppState app) async {
    await tester.pumpWidget(testApp(Scaffold(
      body: ListenableBuilder(
        listenable: app,
        builder: (_, __) => PageCanvas(state: app),
      ),
    )));
    await tester.pump();
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 900));
  }

  testWidgets('nothing selected offers no button', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await canvas(tester, 'onote_del_none_');
    app.addBlock(ink());
    await pump(tester, app);

    expect(find.byIcon(Icons.delete_outline), findsNothing,
        reason: 'a page being read is a page, not a control panel');
    await drain(tester);
  });

  testWidgets('A PEN IN HAND IS THE CASE THAT NEEDS THE BUTTON MOST',
      (tester) async {
    // This used to assert the opposite, and reasoned from it: picking up
    // anything that draws cleared the selection, so "selected, with a pen"
    // was not a state the app could be in, so the lone-block rule could not
    // strand the tablet user it was built for.
    //
    // It can be in that state now, deliberately — a side button borrows the
    // lasso, makes a selection and hands the pen back, and throwing the
    // selection away on the way back was the bug. So the premise is gone and
    // the stranding is real: no block shows its bar while a drawing tool is
    // held, and a tablet has no Delete key.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await canvas(tester, 'onote_del_pen_');
    final b = app.addBlock(ink());
    app.select(b.id);
    expect(app.selectedIds, isNotEmpty, reason: 'precondition');

    app.setTool(Tool.pen, automatic: true);
    expect(app.selectedIds, isNotEmpty,
        reason: 'being handed the pen is not a decision to drop what is '
            'selected');
    await pump(tester, app);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget,
        reason: 'and it is the only way to delete this right now');
    await drain(tester);
  });

  testWidgets('one selected BOX does not get a second delete button',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await canvas(tester, 'onote_del_one_');
    final b = app.addBlock(Block(
        type: BlockType.text,
        x: 40,
        y: 60,
        w: 300,
        content: {'text': 'one thing', 'autoWidth': false}));
    app.select(b.id);
    await pump(tester, app);

    expect(find.byIcon(Icons.delete_outline), findsNothing,
        reason: 'the box already carries a cross on its own bar');
    expect(app.showSelectionDelete, isFalse);
    await drain(tester);
  });

  testWidgets('one selected STROKE does, because it has no bar at all',
      (tester) async {
    // The case the whole button exists for, and the case it had stopped
    // covering: a stroke is its own block now, ink is painted rather than
    // built, and nothing anywhere on it offers a cross.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await canvas(tester, 'onote_del_one_ink_');
    final b = app.addBlock(ink());
    app.select(b.id);
    await pump(tester, app);

    expect(app.showSelectionDelete, isTrue);
    final button = find.byIcon(Icons.delete_outline);
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    expect(app.blocks.where((x) => x.id == b.id), isEmpty);
    await drain(tester);
  });

  testWidgets('a text box being written in does not get one either',
      (tester) async {
    // The reported case, in the words it was reported in: a bin and a cross
    // either side of the same box.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await canvas(tester, 'onote_del_text_');
    final b = app.addBlock(Block(
        type: BlockType.text,
        x: 40,
        y: 60,
        w: 300,
        content: {'text': 'writing', 'autoWidth': false}));
    app.select(b.id, edit: true);
    await pump(tester, app);

    expect(find.byIcon(Icons.delete_outline), findsNothing);
    await drain(tester);
  });

  testWidgets('two selected blocks do get one', (tester) async {
    // A cross belongs to the primary block and says nothing about the rest,
    // so the floating button is the only control that means "all of this".
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await canvas(tester, 'onote_del_two_');
    final a = app.addBlock(ink());
    final b = app.addBlock(Block(
        type: BlockType.text,
        x: 40,
        y: 400,
        w: 300,
        content: {'text': 'also this', 'autoWidth': false}));
    app.select(a.id);
    app.select(b.id, additive: true);
    await pump(tester, app);

    expect(app.selectedIds.length, 2, reason: 'precondition');
    final button = find.byIcon(Icons.delete_outline);
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    expect(app.blocks.where((x) => x.id == a.id || x.id == b.id), isEmpty,
        reason: 'and it takes the whole selection, not just the primary');
    await drain(tester);
  });

  testWidgets('it steps out of the way of the eyedropper', (tester) async {
    // While the eyedropper is armed the next click belongs to it. A button
    // sitting over the page would eat the click that was meant for a colour.
    // (This asserted nothing until a lone stroke started offering a button:
    // with one thing selected there was none to step out of the way.)
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await canvas(tester, 'onote_del_dropper_');
    final b = app.addBlock(ink());
    app.select(b.id);
    app.setPickingInkColor(true);
    await pump(tester, app);

    expect(find.byIcon(Icons.delete_outline), findsNothing);
    await drain(tester);
  });
}
