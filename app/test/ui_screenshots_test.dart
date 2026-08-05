// The UI screenshot harness — renders the real app shell to PNGs.
//
// This exists because the 2026-08 UI review found that every layout defect the
// app had shipped was invisible to state tests and to reading the code; the
// review was only possible once the shell could be *looked at*. The harness
// renders real states (a seeded notebook, panels open, light and dark) at a
// real desktop size with the real bundled fonts, and writes PNGs to
// `test/goldens/`.
//
// **Not a golden test.** Font rasterisation differs per machine, so committed
// goldens would fail everywhere but the machine that made them. The images are
// review artifacts, not assertions — `test/goldens/` is gitignored, and the
// suite is skipped unless explicitly asked for:
//
//     ONOTE_SCREENSHOTS=1 flutter test test/ui_screenshots_test.dart --update-goldens
//
// **Load every bundled face here.** A face the harness does not load renders
// as tofu, and tofu is easy to misread as a UI defect — the first review of
// these images recorded the study panel's mono keyboard hints ("Ctrl+3") as
// skeleton placeholder bars, which they never were. Math symbols (∧ ∨) still
// box because they come from the *OS* fallback chain (`onoteFontFallback`),
// which no test environment has. That one is a known artifact, not an app bug.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/model/tags.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';

import 'support/sqlite.dart';

final bool _enabled = Platform.environment['ONOTE_SCREENSHOTS'] == '1';

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> assets) async {
    final loader = FontLoader(family);
    for (final a in assets) {
      loader.addFont(rootBundle.load(a));
    }
    await loader.load();
  }

  await load('Inter', [
    'assets/fonts/inter/Inter-Regular.ttf',
    'assets/fonts/inter/Inter-Medium.ttf',
    'assets/fonts/inter/Inter-SemiBold.ttf',
    'assets/fonts/inter/Inter-Bold.ttf',
  ]);
  await load('JetBrains Mono', [
    'assets/fonts/jetbrains-mono/JetBrainsMono-Regular.ttf',
    'assets/fonts/jetbrains-mono/JetBrainsMono-Bold.ttf',
  ]);
  // Material icons ship in the SDK, not the app bundle.
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons =
        File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(icons.readAsBytesSync().buffer.asByteData()));
      await loader.load();
    }
  }
}

void main() {
  var haveSqlite = false;
  setUpAll(() async {
    if (!_enabled) return;
    haveSqlite = initSqliteForTests();
    await _loadFonts();
  });

  /// A believable student notebook: three pages, tags, a due date, an exam.
  Future<AppState> seed(WidgetTester tester) async {
    late AppState app;
    late Repository repo;
    final tmp = Directory.systemTemp.createTempSync('onote_shot_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Discrete Maths');
      app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
      var pos = 0;
      TreeNode page(String title) => app.importNode(
          nb.id,
          TreeNode(
              kind: NodeKind.page,
              parentId: section,
              title: title,
              position: 'a${(++pos).toString().padLeft(3, '0')}'));
      final p1 = page('Week 1 — Propositional logic');
      page('Week 2 — Predicates and quantifiers');
      page('Week 3 — Proof techniques');
      final b1 = Block(type: BlockType.text, x: 40, y: 100, w: 520, content: {
        'text': '# Propositional logic\n'
            'A proposition is a statement that is either true or false.\n\n'
            '- Conjunction: p ∧ q\n'
            '- Disjunction: p ∨ q\n'
            '- Negation: ¬p\n\n'
            'What is a tautology?\n'
            '  A formula true under every valuation.'
      });
      NoteTag.writeInto(b1.content, [
        NoteTag(kind: TagKind.question, line: 7),
        NoteTag(kind: TagKind.todo, line: 3, checked: false, due: '2026-08-07'),
      ]);
      final b2 = Block(type: BlockType.text, x: 40, y: 420, w: 520, content: {
        'text': 'Finish tutorial 4 before the lab\n'
            'Remember: De Morgan — ¬(p ∧ q) = ¬p ∨ ¬q'
      });
      NoteTag.writeInto(b2.content, [
        NoteTag(kind: TagKind.todo, line: 0, checked: false),
        NoteTag(kind: TagKind.remember, line: 1),
      ]);
      app.importPage(nb.id, p1.id, [b1, b2], PageProps());
      app.reloadNodes();
      await app.selectPage(p1.id);
      app.study.setExamDate(
          section, DateTime.now().add(const Duration(days: 14)));
    });
    return app;
  }

  Future<void> shot(WidgetTester tester, AppState app, Brightness b,
      String name) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: onoteTheme(b),
      darkTheme: onoteTheme(Brightness.dark),
      themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(key: key, child: AppShell(app: app)),
    ));
    // Twice past the chained save debounces (700ms autosave → 400ms settings).
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
    }
    await expectLater(find.byKey(key), matchesGoldenFile('goldens/$name.png'));
  }

  Future<void> run(WidgetTester tester, String name,
      {Brightness brightness = Brightness.light,
      void Function(AppState app)? arrange}) async {
    if (!_enabled) return markTestSkipped('set ONOTE_SCREENSHOTS=1 to render');
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await seed(tester);
    arrange?.call(app);
    await shot(tester, app, brightness, name);
  }

  testWidgets('shell light', (t) => run(t, 'shell_light'));
  testWidgets('shell dark',
      (t) => run(t, 'shell_dark', brightness: Brightness.dark));
  testWidgets('study panel',
      (t) => run(t, 'shell_study', arrange: (a) => a.toggleStudyPanel()));
  testWidgets('planner panel',
      (t) => run(t, 'shell_planner', arrange: (a) => a.togglePlannerPanel()));
  testWidgets('tags panel',
      (t) => run(t, 'shell_tags', arrange: (a) => a.toggleTagsPanel()));

  // The Insert tab is rendered on its own because it is the one tab that used
  // a different control family, and so the one tab where "does this look like
  // the same app" can only be answered by looking (§7a.2 — a label does not
  // change a command's colour).
  testWidgets('insert tab', (t) async {
    if (!_enabled) return markTestSkipped('set ONOTE_SCREENSHOTS=1 to render');
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await seed(t);
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(MaterialApp(
      theme: onoteTheme(Brightness.light),
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(key: key, child: AppShell(app: app)),
    ));
    for (var i = 0; i < 2; i++) {
      await t.pump(const Duration(milliseconds: 800));
      await t.pumpAndSettle();
    }
    await t.tap(find.text('Insert'));
    await t.pumpAndSettle();
    await expectLater(find.byKey(key), matchesGoldenFile('goldens/insert_tab.png'));
  });

  // The alert popup, which has no other way to be reviewed: it only appears
  // when a reminder comes due, and it appears over whatever you were doing.
  testWidgets('alert popup', (t) async {
    if (!_enabled) return markTestSkipped('set ONOTE_SCREENSHOTS=1 to render');
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await seed(t);
    app.planner.reminders.add(
        text: 'Send the group the week 3 notes',
        at: DateTime.now().subtract(const Duration(minutes: 3)));
    app.planner.startScheduler();
    await shot(t, app, Brightness.light, 'alert_popup');
  });
}
