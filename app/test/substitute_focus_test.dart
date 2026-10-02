// Clicking into the "evaluate at value" field while a text box is open.
//
// Reported: *"i can only enter the text box if i have already clicked on the
// whole 'evaluate at value' containing box. Like if i click on the field while
// another box is still focused, it will move the caret into it as if it was
// going to edit it, but then it will just dispear from it and the other box
// never looses focus."*
//
// The mechanism is a paragraph that re-claims the keyboard after every build:
//
//     if (!_focus.hasFocus && !inlineChildFocused) _focus.requestFocus();
//
// Its purpose is to pick the keyboard up for a block that has just been opened
// for editing, and `BlockType.substitute` is not in `_editableType` — so
// tapping that field never makes it the editing block, the paragraph stays the
// editing block, and on the next build it simply takes the keyboard back.
//
// Needs the real shell: the reclaim lives in the paragraph's build, and a test
// that mounts the substitute block on its own never has a paragraph to fight.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/substitute_block_view.dart';
import 'package:openote/editor/text_block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/math/math_field.dart';
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
    tmp = Directory.systemTemp.createTempSync('onote_subfocus_');
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

  /// A page holding a sentence and a substitute block, in the real shell.
  Future<void> pumpShell(WidgetTester t) async {
    final nb = app.notebookId!;
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    final text = Block(
        type: BlockType.text,
        x: 60,
        y: 120,
        w: 420,
        content: {'text': 'A sentence to be editing.'});
    // An UNRELATED equation, well away from both — the second claimant.
    // Reported separately: *"if im in a maths equation (any maths equation,
    // even one not linked to that evaluator) it still has the same issue."*
    final maths = Block(
        type: BlockType.math,
        x: 620,
        y: 120,
        w: 300,
        content: {'latex': 'a^2+b^2', 'display': true});
    app.importPage(nb, page.id, [text, maths], PageProps());
    app.reloadNodes();
    await app.selectPage(page.id);
    app.markOnboardingSeen();
    // Beside the sentence, well clear of it, so a tap cannot land on both.
    app.insertSubstitute(latex: 'y=3x+10', from: null)
      ..x = 60
      ..y = 380;
    app.cancelPendingSave();

    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      home: AppShell(app: app),
    ));
    await t.pump(const Duration(milliseconds: 900));
    await t.pumpAndSettle();
  }

  /// The one field inside the substitute block — `x = [     ]`.
  Finder valueField() => find.descendant(
      of: find.byType(SubstituteBlockView), matching: find.byType(TextField));

  bool valueFieldHasFocus(WidgetTester t) {
    final f = t.widget<TextField>(valueField()).focusNode;
    return f != null && f.hasPrimaryFocus;
  }

  testWidgets('clicking the value field while a sentence is open keeps it',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pumpShell(t);

    // Open the sentence, so a paragraph session is live and holding the
    // keyboard — which is the whole precondition.
    await t.tapAt(
        t.getTopLeft(find.byType(TextBlockView)) + const Offset(24, 14));
    await t.pumpAndSettle();
    app.cancelPendingSave();
    expect(app.editingBlockId, isNotNull, reason: 'the sentence is open');

    expect(valueField(), findsOneWidget, reason: 'the value field is there');
    await t.tap(valueField());
    await t.pumpAndSettle();
    app.cancelPendingSave();

    // Several frames, because the theft happened on a LATER build rather than
    // on the tap: the caret arrived and then went away again.
    // **The missing ingredient: a rebuild.** The reclaim runs in a post-frame
    // callback registered by the paragraph's build, so it cannot steal
    // anything until the paragraph builds again — and in the running app
    // everything causes that. Typing the value is the first thing anybody
    // does, and it notifies.
    app.refreshChrome();
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 80));
    }

    expect(valueFieldHasFocus(t), isTrue,
        reason: 'THE BUG: the caret lands in the value field and the '
            'paragraph takes the keyboard straight back');
  });

  testWidgets('and the sentence still takes the keyboard when it is opened',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The regression guard for whatever fixes the above. That reclaim exists
    // for a reason — a block just opened for editing has to end up with the
    // keyboard — and a fix that stops it doing its job is not a fix.
    await pumpShell(t);

    await t.tapAt(
        t.getTopLeft(find.byType(TextBlockView)) + const Offset(24, 14));
    await t.pumpAndSettle();
    app.cancelPendingSave();

    final field = find
        .descendant(
            of: find.byType(TextBlockView), matching: find.byType(TextField))
        .first;
    expect(t.widget<TextField>(field).focusNode?.hasPrimaryFocus, isTrue,
        reason: 'opening a sentence must still put the caret in it');
  });

  testWidgets('clicking the value field while an EQUATION is open keeps it',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The same bug at its second site. `MathField.build` registers the same
    // kind of post-frame reclaim the paragraph did — `if (mounted &&
    // !_focus.hasFocus) _focus.requestFocus()` — so an open equation held
    // the keyboard against a click into any field outside its own block,
    // whether or not that field's block had anything to do with it.
    await pumpShell(t);

    final maths = app.blocks.firstWhere((b) => b.type == BlockType.math);
    app.select(maths.id, edit: true);
    await t.pumpAndSettle();
    app.cancelPendingSave();
    expect(app.editingBlockId, maths.id, reason: 'the equation is open');

    await t.tap(valueField());
    await t.pumpAndSettle();
    app.cancelPendingSave();

    // Rebuilds, because the theft lands on a LATER build — same reason as
    // the paragraph case above.
    app.refreshChrome();
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 80));
    }

    expect(valueFieldHasFocus(t), isTrue,
        reason: 'THE BUG: the equation takes the keyboard straight back');
  });

  testWidgets('and an equation still takes the keyboard when it is opened',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The regression guard for the above, matching the paragraph's. That
    // reclaim is why an equation can be typed into at all — reported as *"i
    // cant actually type anything right off the bat"* — so a fix that stops
    // it doing its job is not a fix.
    await pumpShell(t);

    final maths = app.blocks.firstWhere((b) => b.type == BlockType.math);
    app.select(maths.id, edit: true);
    await t.pumpAndSettle();
    app.cancelPendingSave();

    expect(find.byType(MathField), findsOneWidget);
    final node = t.widget<Focus>(find
            .descendant(of: find.byType(MathField), matching: find.byType(Focus))
            .first)
        .focusNode;
    expect(node?.hasPrimaryFocus, isTrue,
        reason: 'opening an equation must still put the caret in it');
  });

  testWidgets('clicking the value field closes the block that was open',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // *"the original one i was editing before still seems to stay selected
    // which is kinda odd"* — a tap on a TextField is won by the field, never
    // reaches `BlockView._tap`, and so nothing ended the sentence's session.
    await pumpShell(t);

    await t.tapAt(
        t.getTopLeft(find.byType(TextBlockView)) + const Offset(24, 14));
    await t.pumpAndSettle();
    app.cancelPendingSave();
    expect(app.editingBlockId, isNotNull);

    await t.tap(valueField());
    await t.pumpAndSettle();
    app.cancelPendingSave();

    expect(app.editingBlockId, isNull,
        reason: 'the sentence is no longer being edited');
    expect(app.selectedBlockId,
        app.blocks.firstWhere((b) => b.type == BlockType.substitute).id,
        reason: 'and the block the student is in is the selected one');
  });

  testWidgets('clicking the value field a SECOND time still works', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // The reported workaround was clicking the containing box first, so the
    // second click is the one that used to work. It has to keep working.
    await pumpShell(t);
    await t.tap(valueField());
    await t.pumpAndSettle();
    await t.tap(valueField());
    await t.pumpAndSettle();
    app.cancelPendingSave();
    expect(valueFieldHasFocus(t), isTrue);
  });
}
