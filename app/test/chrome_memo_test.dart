// The chrome does not rebuild for a keystroke that cannot change it.
//
// `AppState.markDirty()` runs on every character — it has to, because the
// auto-width measurement that makes a box grow as you type happens in the
// parent's build — and `AppShell` wraps the whole application in one
// `ListenableBuilder`. Measured on the `ui_perf_probe` notebook, median frame
// after `markDirty()`, debug build, by stubbing each region out in turn: the
// command bar cost 31.6 ms of a 62.7 ms frame and the object row 15.2 ms.
// Neither can look different because a character was typed in the middle of a
// paragraph. Both are memoised now (`lib/ui/memo.dart`), and the same frame
// measures 18.7 ms.
//
// Memoising has ONE failure mode and it is a nasty one: a value the subtree
// renders but the key does not list goes stale — it lands in the state and
// paints only when something else happens to invalidate the memo. That is a
// bug which passes a quick look and fails in real use, so this file does not
// leave it to discipline:
//
//  (a) a source scan finds every `app.<member>` the memoised widget reads and
//      fails unless it is either in that widget's `memoInputs()` or declared
//      below as an action that renders nothing;
//  (b) the memo is proved to actually HIT — a notification that changes
//      nothing leaves the very same widget instances in the tree, which is
//      the only thing that makes (a) worth having;
//  (c) it is proved to RELEASE — a change to a keyed value really does
//      rebuild;
//  (d) and the two live things inside the memoised rows — the word count and
//      the badges — are proved still live, because they listen for
//      themselves.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/command_bar.dart';
import 'package:openote/ui/compacting_toolbar.dart';
import 'package:openote/ui/object_row.dart';

import 'support/app.dart';
import 'support/sqlite.dart';

/// Members of `AppState` a memoised widget may touch without listing them:
/// they are called, not rendered. Adding to this list is a claim that the
/// member's RESULT never reaches the screen from that widget — check before
/// you add one.
const _actionsOnly = {
  'applyTextColor', 'blankOutSelection', 'insertFlashcard', 'makeCardAtCaret',
  'recolorSelectedInk', 'redo', 'refresh', 'setActiveBlockFont',
  'setActiveBlockFontSize', 'setAngleMode', 'setBackground', 'setEraserMode',
  'setPageLayout', 'setPenProximitySwitch', 'setTagDue', 'setTool',
  'setTouchDrawing', 'toggleFind', 'toggleLinePrefix', 'toggleLinksPanel',
  'toggleList', 'togglePlannerPanel', 'toggleSnap', 'toggleStudyPanel',
  'toggleTagOnSelection', 'toggleTagsPanel', 'toggleTocPanel', 'undo',
  'wrapSelection',
  // Read only inside an `onPressed`, to seed a picker or a fit-to-content.
  'activeEditor', 'contentBounds',
  // Listened to directly, by an `AnimatedBuilder` on the controller itself.
  'canvas',
};

/// The body of one class in a file, by name — from its declaration to the
/// next top-level `class`.
String _classBody(String source, String name) {
  final start = source.indexOf('class $name');
  expect(start, isNot(-1), reason: '$name is not in this file any more');
  final next = source.indexOf('\nclass ', start + 1);
  return source.substring(start, next == -1 ? source.length : next);
}

void main() {
  group('every rendered value is in the key', () {
    // The mutation that turns these red: read a new piece of AppState in one
    // of these widgets' build and forget to add it to `memoInputs`.
    void check(String path, String className) {
      final source = File(path).readAsStringSync();
      final body = _classBody(source, className);
      final inputs = body.substring(body.indexOf('memoInputs()'));
      final declared = inputs.substring(0, inputs.indexOf('\n  }') + 1);

      final read = RegExp(r'app\.([a-zA-Z_]\w*)')
          .allMatches(body)
          .map((m) => m.group(1)!)
          .toSet()
          .difference(_actionsOnly);
      final missing = [
        for (final name in read)
          if (!declared.contains('app.$name')) name
      ]..sort();

      expect(missing, isEmpty,
          reason: '$className renders these but does not key on them, so a '
              'change to one paints only when something else happens to '
              'invalidate the memo — add them to memoInputs(), or to '
              '_actionsOnly if the value truly never reaches the screen: '
              '$missing');
    }

    test('the command bar', () => check('lib/ui/command_bar.dart', '_CommandBarState'));
    test('the object row', () => check('lib/ui/object_row.dart', '_ObjectRowState'));
  });

  group('the memo, through the real widgets', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    late Directory tmp;
    late Repository repo;
    late AppState app;

    Future<void> pump(WidgetTester tester) async {
      AppState.syncLogEnabled = false;
      addTearDown(() => AppState.syncLogEnabled = true);
      // Real disk I/O must run OUTSIDE the fake-async test zone, or the
      // futures it waits on never complete and the test hangs.
      await tester.runAsync(() async {
        tmp = Directory.systemTemp.createTempSync('onote_memo_');
        repo = await Repository.openAt(tmp);
        final nb = await repo.createNotebook('Memo');
        app = AppState(repo)
          ..notebookId = nb.id
          ..spellCheckEnabled = false;
        app.reloadNodes();
        final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
        app.importPage(nb.id, page.id, [
          Block(
              type: BlockType.text,
              x: 40,
              y: 100,
              w: 400,
              content: {'text': 'one two three'}),
        ], PageProps());
        app.reloadNodes();
        await app.selectPage(page.id);
      });
      addTearDown(() {
        app.cancelPendingSave();
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(testApp(Scaffold(
        body: Column(children: [
          ListenableBuilder(
            listenable: app,
            builder: (_, __) => Column(children: [
              CommandBar(app: app),
              ObjectRow(app: app),
            ]),
          ),
        ]),
      )));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
    }

    /// The identity of a widget deep inside each row. If the row rebuilt, this
    /// is a different object; if the memo hit, it is the very same one.
    Object bar(WidgetTester tester) =>
        tester.widget(find.byType(CompactingToolbar).first);

    testWidgets('a notification that changes nothing rebuilds neither row',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pump(tester);

      final before = bar(tester);
      // Exactly what a keystroke does, with nothing about the chrome changed.
      app.markDirty();
      await tester.pumpAndSettle();

      expect(identical(bar(tester), before), isTrue,
          reason: 'the command bar rebuilt for a keystroke that could not '
              'change anything it shows — the memo is not hitting, and every '
              'guard in this file is guarding nothing');
      app.cancelPendingSave();
    });

    testWidgets('a change to a keyed value does rebuild it', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pump(tester);

      final before = bar(tester);
      app.setTool(Tool.pen);
      await tester.pumpAndSettle();

      expect(identical(bar(tester), before), isFalse,
          reason: 'picking up the pen must rebuild the bar');
      expect(find.text('Done'), findsOneWidget,
          reason: 'and the escape hatch out of the tool must appear');
      app.cancelPendingSave();
    });

    testWidgets('the word count stays live inside a row that did not rebuild',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pump(tester);
      expect(find.text('3 words'), findsOneWidget);

      // Typing is exactly the case the memo exists for: the row itself must
      // not rebuild, and the count must change anyway.
      app.blocks.first.content['text'] = 'one two three four five';
      app.markDirty();
      await tester.pumpAndSettle();

      expect(find.text('5 words'), findsOneWidget,
          reason: 'the count listens for itself — it is the one thing in that '
              'row which really does change with every character');
      app.cancelPendingSave();
    });

    // THE CLASSIC MEMO BUG. A cached subtree is built against the theme, the
    // locale and the text direction that were in force when it was built —
    // none of which appear in any key, because they arrive through inherited
    // widgets rather than through `app`. Get this wrong and switching to dark
    // leaves the toolbars painted for the light theme until something else
    // happens to invalidate them. `MemoBuild` drops the cache in
    // `didChangeDependencies`, which covers every inherited widget including
    // ones added later; this is the proof.
    testWidgets('changing the theme rebuilds it, though no key changed',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pump(tester);
      final before = bar(tester);

      // Nothing on either row's key list has moved — only the theme.
      await tester.pumpWidget(testApp(
        Scaffold(
          body: Column(children: [
            ListenableBuilder(
              listenable: app,
              builder: (_, __) => Column(children: [
                CommandBar(app: app),
                ObjectRow(app: app),
              ]),
            ),
          ]),
        ),
        brightness: Brightness.dark,
      ));
      await tester.pumpAndSettle();

      expect(identical(bar(tester), before), isFalse,
          reason: 'the toolbars were still painted for the light theme — a '
              'cached subtree must be dropped when an inherited widget it was '
              'built against changes');
      app.cancelPendingSave();
    });

    testWidgets('the panel buttons still light up when their panel opens',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pump(tester);
      final before = bar(tester);

      app.toggleStudyPanel();
      await tester.pumpAndSettle();
      expect(identical(bar(tester), before), isFalse,
          reason: 'showStudyPanel is keyed, so opening the panel rebuilds the '
              'bar and the button reads as selected');
      app.cancelPendingSave();
    });
  });
}
