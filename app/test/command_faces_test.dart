// The command row's two faces (owner, v0.23; moved off their own band later).
//
// *"moving the user to a new menu up there when entering maths mode without
// them doing anything is jarring and its best to not force any navigation."*
//
// The design answers that structurally rather than politely: there is no tab
// to be moved to, and the chrome is the same height whatever is showing.
//
// These invariants survived the band being removed — the owner: *"We still
// have this extra bar of options under the existing menu bar … Lets move all
// of that into its own tab called 'Page'."* The equation palette borrows the
// command row instead of a strip of its own, which is the same loan one row
// higher, and the page controls are a tab. What must not change is that
// nobody is navigated and nothing moves under them, so these tests now
// measure the whole chrome rather than one band of it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/math/active_math.dart';
import 'package:openote/math/evaluate.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/command_bar.dart';
import 'package:openote/ui/math_bar.dart';
import 'package:openote/ui/object_face.dart';
import 'package:openote/ui/command_faces.dart';

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
    tmp = Directory.systemTemp.createTempSync('onote_objrow_');
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

  ActiveMathEditor standIn() => ActiveMathEditor(
        owner: 'test',
        insert: (_) {},
        latexMode: false,
        latexAvailable: true,
        toggleLatex: () {},
      );

  Block textBlock(String id) => Block(
      id: id, type: BlockType.text, x: 0, y: 0, w: 300, content: {'text': ''});

  group('which face, decided without a widget tree', () {
    test('nothing being written is the page', () {
      if (!haveSqlite) return;
      expect(objectFaceOf(app), ObjectFace.page);
    });

    test('an equation in a box of its own', () {
      if (!haveSqlite) return;
      final b = app.insertEquation(at: const Offset(10, 10));
      expect(app.editingBlockId, b.id);
      expect(objectFaceOf(app), ObjectFace.equation);
      app.cancelPendingSave();
    });

    test('an equation in a SENTENCE — the block being edited is text', () {
      if (!haveSqlite) return;
      app.blocks.add(textBlock('p1'));
      app.editingBlockId = 'p1';
      expect(objectFaceOf(app), ObjectFace.page,
          reason: 'a paragraph on its own is not maths');
      app.setActiveMath(standIn());
      expect(objectFaceOf(app), ObjectFace.equation,
          reason: 'only the open editor can say, and it has');
    });

    test('and the one frame where the editor has not registered yet', () {
      if (!haveSqlite) return;
      app.insertEquation(at: const Offset(10, 10));
      app.activeMath = null;
      expect(objectFaceOf(app), ObjectFace.equation,
          reason: 'the model knows before the editor has built; falling back '
              'to the page would flash the page controls for a frame every '
              'time an equation opened');
      app.cancelPendingSave();
    });

    test('a text block being edited is still the page', () {
      if (!haveSqlite) return;
      app.blocks.add(textBlock('p1'));
      app.editingBlockId = 'p1';
      expect(objectFaceOf(app), ObjectFace.page,
          reason: 'Home already carries the formatting, on the tab the '
              'student chose');
    });
  });

  group('parity, enforced by the constructor', () {
    testWidgets('the equation face is built from closures and primitives, '
        'with no AppState in scope', (tester) async {
      // This test compiles or it does not. If someone gives EquationFace an
      // `AppState`, a `Block` or an `EquationPlacement`, this line stops
      // building — which is the point: the rule is a compile error, not a
      // review catch.
      final face = EquationFace(
        math: standIn(),
        angleMode: AngleMode.degrees,
        onToggleAngleMode: () {},
        recentIds: const ['pi'],
      );
      tester.view.physicalSize = const Size(2600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(body: Align(
              alignment: Alignment.topLeft, child: face))));
      await tester.pumpAndSettle();
      expect(find.byType(MathBar), findsOneWidget);
    });

    testWidgets('a block equation and one in a sentence get the same row',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      tester.view.physicalSize = const Size(2600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      Future<List<String>> chipsFor(void Function() setUp) async {
        app.blocks.clear();
        app.editingBlockId = null;
        app.activeMath = null;
        setUp();
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
        return tester
            .widgetList<MathChip>(find.byType(MathChip))
            .map((c) => c.item.id)
            .toList();
      }

      final inBox = await chipsFor(() {
        app.insertEquation(at: const Offset(10, 10));
        app.setActiveMath(standIn());
      });
      final inSentence = await chipsFor(() {
        app.blocks.add(textBlock('p1'));
        app.editingBlockId = 'p1';
        app.setActiveMath(standIn());
      });
      expect(inBox, isNotEmpty);
      expect(inSentence, inBox,
          reason: 'a regular user does not think a standalone maths box is '
              'any different to one in a text box');
      app.cancelPendingSave();
    });
  });

  group('the chrome does not move', () {
    testWidgets('same height, and the tabs in the same pixels, in every state',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      tester.view.physicalSize = const Size(2600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: Column(children: [
            ListenableBuilder(
              listenable: app,
              builder: (_, __) => CommandBar(app: app),
            ),
            const Expanded(child: ColoredBox(color: Color(0xFFEEEEEE))),
          ]),
        ),
      ));
      await tester.pumpAndSettle();

      Map<String, double> tabXs() => {
            for (final t in ['Home', 'Insert', 'Draw', 'Page'])
              t: tester.getRect(find.text(t)).left,
          };
      double pageTop() =>
          tester.getRect(find.byType(ColoredBox).last).top;

      final restingTabs = tabXs();
      final restingTop = pageTop();

      app.insertEquation(at: const Offset(10, 10));
      app.setActiveMath(standIn());
      await tester.pumpAndSettle();

      expect(find.byType(MathBar), findsOneWidget);
      expect(tabXs(), restingTabs,
          reason: 'every tab in the same pixel it was in');
      expect(pageTop(), restingTop,
          reason: 'the page did not move, which is the whole design');

      // …and back again.
      app.clearActiveMath('test');
      app.editingBlockId = null;
      await tester.pumpAndSettle();
      expect(tabXs(), restingTabs);
      expect(pageTop(), restingTop);
      app.cancelPendingSave();
    });

    testWidgets('the chrome is one height, whatever it is showing',
        (tester) async {
      // The number itself is not the property — 32 for the tabs and 44 for
      // the command row is a design choice and may change. The property is
      // that it is the SAME number in every state, because that is what means
      // the canvas box never moves and there is no compensating pan to write.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      tester.view.physicalSize = const Size(2600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ListenableBuilder(
              listenable: app,
              builder: (_, __) => CommandBar(app: app),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final resting = tester.getSize(find.byType(CommandBar)).height;

      for (final go in [
        () => tester.tap(find.text('Draw')),
        () => tester.tap(find.text('Page')),
        () => tester.tap(find.text('Insert')),
      ]) {
        await go();
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(CommandBar)).height, resting);
      }

      app.insertEquation(at: const Offset(10, 10));
      app.setActiveMath(standIn());
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(CommandBar)).height, resting,
          reason: 'an equation borrows the row; it does not add one');
      app.cancelPendingSave();
    });
  });

  group('tabbing away from an equation', () {
    Future<void> chrome(WidgetTester tester) async {
      tester.view.physicalSize = const Size(2600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
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
    }

    testWidgets('shows that tab, and gives the palette back to the next one',
        (tester) async {
      // Found reviewing the branch, not reported. Tapping a tab mid-equation
      // is the way to reach Home's formatting without closing the equation,
      // and it was remembered in a plain flag — which nothing ever cleared,
      // because closing an equation does not run any code that could. So the
      // SECOND equation opened in a sitting silently got no palette at all.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await chrome(tester);

      app.insertEquation(at: const Offset(10, 10));
      app.setActiveMath(standIn());
      await tester.pumpAndSettle();
      expect(find.byType(MathBar), findsOneWidget);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.byType(MathBar), findsNothing,
          reason: 'the way out, for the rare case of wanting Home mid-equation');

      app.clearActiveMath('test');
      app.editingBlockId = null;
      await tester.pumpAndSettle();

      app.insertEquation(at: const Offset(10, 200));
      app.setActiveMath(standIn());
      await tester.pumpAndSettle();
      expect(find.byType(MathBar), findsOneWidget,
          reason: 'a new equation is not the one they tabbed away from');
      app.cancelPendingSave();
    });
  });

  group('what is above the tabs', () {
    testWidgets('undo and redo are there whatever tab you are on',
        (tester) async {
      // Reported: *"We are also lacking an undo and redo button at the moment,
      // these are pretty important to have."* They existed — at the head of
      // the Home row — which is to say they were missing from three quarters
      // of the app. They are not a Home command: they are what you press when
      // something has gone wrong, whatever you were doing when it did.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      tester.view.physicalSize = const Size(2600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
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

      for (final tab in ['Insert', 'Draw', 'Page', 'Home']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.undo), findsOneWidget, reason: tab);
        expect(find.byIcon(Icons.redo), findsOneWidget, reason: tab);
      }
      app.cancelPendingSave();
    });

    testWidgets('and the word count is too', (tester) async {
      // The owner: *"move the word count to the bar next to all the other
      // options up top."* It is the one thing off the old band that is not a
      // setting — you do not change it, you glance at it.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      tester.view.physicalSize = const Size(2600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      app.blocks.add(Block(
          type: BlockType.text,
          x: 0,
          y: 0,
          w: 300,
          content: {'text': 'one two three'}));
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

      expect(find.text('3 words'), findsOneWidget);
      await tester.tap(find.text('Draw'));
      await tester.pumpAndSettle();
      expect(find.text('3 words'), findsOneWidget,
          reason: 'a number checked twenty times an hour is not behind a tab');
      app.cancelPendingSave();
    });
  });

  group('the page face', () {
    testWidgets('is the Page tab, and carries what the View tab used to',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      tester.view.physicalSize = const Size(2600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
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
      expect(find.byType(PageFace), findsNothing,
          reason: 'not until somebody asks for it');
      await tester.tap(find.text('Page'));
      await tester.pumpAndSettle();
      expect(find.byType(PageFace), findsOneWidget);
      for (final tip in [
        'Background: blank',
        'Background: grid',
        'Zoom in  (Ctrl+=)',
        'Zoom out  (Ctrl+-)',
        'Zoom to fit content',
      ]) {
        expect(find.byTooltip(tip), findsOneWidget, reason: tip);
      }
      // And it acts on the page.
      await tester.tap(find.byTooltip('Background: grid'));
      await tester.pumpAndSettle();
      expect(app.pageProps.background, 'grid');
      app.cancelPendingSave();
    });
  });
}
