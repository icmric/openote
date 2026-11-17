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
import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/core/onote_text.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/model/tags.dart';
import 'package:openote/editor/text_block_view.dart';
import 'package:openote/export/import_job.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';
import 'package:openote/ui/device_class.dart' show debugTouchPlatform;
import 'package:openote/ui/notebook_manager.dart';
import 'package:openote/ui/onboarding.dart';
import 'package:openote/ui/phone_shell.dart';
import 'package:openote/ui/protect_dialog.dart';
import 'package:openote/ui/settings_dialog.dart';
import 'package:openote/ui/sync_dialog.dart';
import 'package:openote/ui/ui_scale_host.dart';

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
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      localeListResolutionCallback: onoteResolveLocale,
      // The harness mounts its own MaterialApp, so it has to honour the
      // language the same way `main.dart` does — otherwise a screenshot
      // "in Spanish" is a screenshot in English.
      locale: app.uiLocale,
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
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
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

  // The import progress card, mid-import and completed — states that only
  // exist while a real .onepkg is streaming in, so a screenshot is the only
  // way to review them.
  testWidgets('import progress card', (t) async {
    if (!_enabled) return markTestSkipped('set ONOTE_SCREENSHOTS=1 to render');
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await seed(t);
    final job = ImportJob.debugCreate(app, 'Discrete Maths.onepkg')
      ..state = ImportJobState.writing
      ..message = 'Importing "Week 6 — Graphs"…'
      ..pagesDone = 118
      ..pagesTotal = 324;
    ImportJob.current = job;
    addTearDown(() => ImportJob.current = null);
    // Not `shot`: its pumpAndSettle never settles while the card's progress
    // indicators animate — which they do for as long as the import runs, by
    // design. Pump fixed frames instead.
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(key: key, child: AppShell(app: app)),
    ));
    for (var i = 0; i < 2; i++) {
      await t.pump(const Duration(milliseconds: 800));
    }
    await expectLater(
        find.byKey(key), matchesGoldenFile('goldens/import_running.png'));

    job
      ..state = ImportJobState.done
      ..message = 'Imported 324 pages, 372 images and 64,616 ink strokes.';
    job.debugNotify();
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    await expectLater(
        find.byKey(key), matchesGoldenFile('goldens/import_done.png'));
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

  // The chrome in another language, because a translation that overflows a
  // toolbar is invisible to every assertion in the suite. Spanish is the
  // longest of the six on the words that matter (Configuraciones, Sincronizar,
  // Insertar), so it is the one that would break first.
  testWidgets('shell in Spanish', (t) async {
    if (!_enabled) return markTestSkipped('set ONOTE_SCREENSHOTS=1 to render');
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await seed(t);
    app.setUiLocale(const Locale('es'));
    await shot(t, app, Brightness.light, 'shell_spanish');
  });

  // The welcome flow, which is drawn rather than written and therefore cannot
  // be reviewed any other way — reading `_CanvasStoryPainter` tells you what
  // it paints, not whether it reads. One image per step; the first is caught
  // at the frame its animation rests on.
  for (final step in [0, 1, 2]) {
    testWidgets('onboarding step $step', (t) async {
      if (!_enabled) return markTestSkipped('set ONOTE_SCREENSHOTS=1 to render');
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await seed(t);
      const key = ValueKey('onboarding-shot');
      t.view.physicalSize = const Size(1100, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          localizationsDelegates: kOnoteLocalizations,
          supportedLocales: kOnoteLocales,
          debugShowCheckedModeBanner: false,
          theme: onoteTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                  onPressed: () => showOnboarding(c, app),
                  child: const Text('open')),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pump(const Duration(milliseconds: 450));
      await t.pumpAndSettle();
      for (var i = 0; i < step; i++) {
        await t.tap(find.text('Next'));
        await t.pumpAndSettle();
      }
      await expectLater(
          find.byKey(key), matchesGoldenFile('goldens/onboarding_$step.png'));
      app.cancelPendingSave();
    });
  }

  // ── The navigator (S7): groups, the plus menu, the bin, a drag in flight ──
  //
  // Drawn at a small window so the navigator is most of the picture, and with
  // the boundary ABOVE the navigator's overlay, so menus, the bin's panel and
  // the drag pill are in the image.
  Future<GlobalKey> mountNav(WidgetTester t, AppState app, Brightness b,
      {Size size = const Size(900, 640)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(b),
      darkTheme: onoteTheme(Brightness.dark),
      themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      debugShowCheckedModeBanner: false,
      builder: (c, child) => RepaintBoundary(key: key, child: child),
      home: AppShell(app: app),
    ));
    for (var i = 0; i < 2; i++) {
      await t.pump(const Duration(milliseconds: 800));
      await t.pumpAndSettle();
    }
    return key;
  }

  Future<void> snap(WidgetTester t, GlobalKey key, String name) =>
      expectLater(find.byKey(key), matchesGoldenFile('goldens/$name.png'));

  for (final b in [Brightness.light, Brightness.dark]) {
    testWidgets('navigator states ${b.name}', (t) async {
      if (!_enabled) return markTestSkipped('set ONOTE_SCREENSHOTS=1 to render');
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await seed(t);
      await t.runAsync(() async {
        for (var i = 0; i < 4; i++) {
          await app.addSection();
        }
        final secs =
            app.nodes.where((n) => n.kind == NodeKind.section).toList();
        app.groupSectionsTogether(secs[2].id, secs[3].id);
        app.groupToRename = null;
        final pages =
            app.nodes.where((n) => n.kind == NodeKind.page).toList();
        await app.deleteNode(pages.last.id);
        await app.deleteNode(secs.last.id);
        await app.selectPage(
            app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
      });
      final key = await mountNav(t, app, b);
      await snap(t, key, 'nav_${b.name}_resting');

      // The plus beside the section list.
      await t.tap(find.byKey(const ValueKey('nav-add-section')));
      await t.pumpAndSettle();
      await snap(t, key, 'nav_${b.name}_plus_menu');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();

      // The bin's panel.
      await t.tap(find.byTooltip('Recycle bin'));
      await t.pumpAndSettle();
      await snap(t, key, 'nav_${b.name}_bin');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();

      // A section carried over the middle of another: "Group together".
      final loose = app.nodes
          .where((n) => n.kind == NodeKind.section && n.parentId == null)
          .toList();
      expect(loose.length, greaterThanOrEqualTo(2));
      final from = find.text(loose.first.title).first;
      final to = find.text(loose.last.title).first;
      final g = await t.startGesture(t.getCenter(from));
      await g.moveBy(const Offset(0, 6));
      await t.pump();
      await g.moveTo(t.getCenter(to));
      await t.pump();
      await snap(t, key, 'nav_${b.name}_drag_group');
      await g.moveTo(t.getTopLeft(to) + const Offset(20, -6));
      await t.pump();
      await snap(t, key, 'nav_${b.name}_drag_above');
      await g.cancel();
      await t.pumpAndSettle();
      app.cancelPendingSave();
    });
  }

  // Narrow navigators: the places row gives up its words, then its numbers'
  // place, then everything but the icons.
  for (final w in [150.0, 190.0, 232.0]) {
    testWidgets('navigator places at ${w.toInt()}', (t) async {
      if (!_enabled) return markTestSkipped('set ONOTE_SCREENSHOTS=1 to render');
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await seed(t);
      await t.runAsync(() async {
        final pages =
            app.nodes.where((n) => n.kind == NodeKind.page).toList();
        await app.deleteNode(pages.last.id);
        await app.selectPage(pages.first.id);
      });
      app.navSectionsCollapsed = true;
      app.navPagesW = w;
      final key = await mountNav(t, app, Brightness.light);
      await snap(t, key, 'nav_places_${w.toInt()}');
      app.cancelPendingSave();
    });
  }

  // ── The phone layout: the page, and the drawer ─────────────────────────────
  for (final drawer in [false, true]) {
    testWidgets('phone ${drawer ? 'drawer' : 'page'}', (t) async {
      if (!_enabled) return markTestSkipped('set ONOTE_SCREENSHOTS=1 to render');
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await seed(t);
      app.systemLocale = () => const Locale('en', 'AU');
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      t.view.padding = const FakeViewPadding(top: 36, bottom: 20);
      t.view.viewPadding = const FakeViewPadding(top: 36, bottom: 20);
      addTearDown(t.view.reset);
      final key = GlobalKey();
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        theme: onoteTheme(Brightness.light),
        debugShowCheckedModeBanner: false,
        builder: (c, child) => RepaintBoundary(key: key, child: child),
        home: AppShell(app: app),
      ));
      for (var i = 0; i < 2; i++) {
        await t.pump(const Duration(milliseconds: 800));
        await t.pumpAndSettle();
      }
      if (drawer) {
        t.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
        await t.pumpAndSettle();
      }
      await expectLater(find.byKey(key),
          matchesGoldenFile('goldens/phone_${drawer ? 'drawer' : 'page'}.png'));
      app.cancelPendingSave();
    });
  }

  for (final which in ['Insert', 'format']) {
    testWidgets('phone sheet $which', (t) async {
      if (!_enabled) return markTestSkipped('set ONOTE_SCREENSHOTS=1 to render');
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await seed(t);
      app.systemLocale = () => const Locale('en', 'AU');
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      t.view.padding = const FakeViewPadding(top: 36, bottom: 20);
      t.view.viewPadding = const FakeViewPadding(top: 36, bottom: 20);
      addTearDown(t.view.reset);
      final key = GlobalKey();
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        theme: onoteTheme(Brightness.light),
        debugShowCheckedModeBanner: false,
        builder: (c, child) => RepaintBoundary(key: key, child: child),
        home: AppShell(app: app),
      ));
      for (var i = 0; i < 2; i++) {
        await t.pump(const Duration(milliseconds: 800));
        await t.pumpAndSettle();
      }
      if (which == 'Insert') {
        await t.tap(find.text('Insert'));
      } else {
        await t.tap(find.byIcon(Icons.text_format));
      }
      await t.pumpAndSettle();
      await expectLater(find.byKey(key),
          matchesGoldenFile('goldens/phone_sheet_$which.png'));
      app.cancelPendingSave();
    });
  }

  // ── Every phone and tablet screen, light and dark ─────────────────────────
  Future<void> device(
    WidgetTester t,
    String name,
    Size size, {
    Brightness b = Brightness.light,
    bool touch = true,
    Future<void> Function(WidgetTester t, AppState app, BuildContext shell)? act,
  }) async {
    final app = await seed(t);
    app.systemLocale = () => const Locale('en', 'AU');
    final tablet = size.shortestSide >= 600;
    final pad = tablet
        ? const FakeViewPadding(top: 24, bottom: 16)
        : const FakeViewPadding(top: 36, bottom: 20);
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    t.view.padding = pad;
    t.view.viewPadding = pad;
    addTearDown(t.view.reset);
    if (touch) debugTouchPlatform = true;
    try {
      final key = GlobalKey();
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        theme: onoteTheme(b),
        debugShowCheckedModeBanner: false,
        builder: (c, child) => RepaintBoundary(
            key: key, child: UiScaleHost(app: app, child: child!)),
        home: AppShell(app: app),
      ));
      for (var i = 0; i < 2; i++) {
        await t.pump(const Duration(milliseconds: 800));
        await t.pumpAndSettle();
      }
      if (act != null) {
        await act(t, app, t.element(find.byType(AppShell)));
        await t.pumpAndSettle();
      }
      await expectLater(find.byKey(key), matchesGoldenFile('goldens/$name.png'));
    } finally {
      debugTouchPlatform = null;
    }
    app.cancelPendingSave();
  }

  Future<void> openDrawer(WidgetTester t, AppState app, BuildContext c) async {
    t.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await t.pumpAndSettle();
  }

  final screens = <String, (Size, Brightness, Future<void> Function(WidgetTester, AppState, BuildContext)?)>{
    'phone_page_dark': (const Size(390, 844), Brightness.dark, null),
    'phone_drawer_dark': (const Size(390, 844), Brightness.dark, openDrawer),
    'phone_drawer_recent': (const Size(390, 844), Brightness.light,
        (t, app, c) async {
      await openDrawer(t, app, c);
      await t.tap(find.byKey(const ValueKey('phone-nav-recent')));
    }),
    'phone_drawer_search': (const Size(390, 844), Brightness.light,
        (t, app, c) async {
      await openDrawer(t, app, c);
      await t.enterText(
          find.descendant(
              of: find.byType(PhoneNavigator), matching: find.byType(TextField)),
          'a');
    }),
    'phone_sheet_Page': (const Size(390, 844), Brightness.light,
        (t, app, c) async => await t.tap(find.text('Page'))),
    'phone_sheet_Share': (const Size(390, 844), Brightness.light,
        (t, app, c) async {
      await t.tap(find.text('Insert'));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.ios_share));
    }),
    'phone_notebooks': (const Size(390, 844), Brightness.light,
        (t, app, c) async {
      unawaited(showNotebookManager(c, app));
    }),
    'phone_landscape': (const Size(844, 390), Brightness.light, null),
    'tablet_landscape': (const Size(1280, 800), Brightness.light, null),
    'tablet_landscape_dark': (const Size(1280, 800), Brightness.dark, null),
    'tablet_portrait': (const Size(800, 1280), Brightness.light, null),
    'tablet_portrait_drawer': (const Size(800, 1280), Brightness.light, openDrawer),
  };
  for (final e in screens.entries) {
    testWidgets('screen ${e.key}', (t) async {
      if (!_enabled) return markTestSkipped('set ONOTE_SCREENSHOTS=1 to render');
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await device(t, e.key, e.value.$1, b: e.value.$2, act: e.value.$3);
    });
  }

  // ── Desktop dialogs (#41, #42) ─────────────────────────────────────────────
  //
  // The two reports were about dialogs: buttons drawn too thin to aim at, and a
  // cramped Sync window whose scroll bar sat on its controls. Rendered with a
  // mouse rather than touch, at the reporter's own window size and a small
  // laptop's, so the comfort pass can be looked at rather than assumed.
  final dialogs = <String, Future<void> Function(WidgetTester, AppState, BuildContext)>{
    'notebooks': (t, app, c) async => unawaited(showNotebookManager(c, app)),
    'sync': (t, app, c) async => unawaited(showSyncDialog(c, app)),
    'settings': (t, app, c) async => unawaited(showSettingsDialog(c, app)),
    'lock': (t, app, c) async =>
        unawaited(askNewPasscode(c, 'Week 3')),
  };
  for (final d in dialogs.entries) {
    for (final size in const [Size(1920, 1025), Size(1366, 768)]) {
      testWidgets('dialog ${d.key} ${size.width.toInt()}', (t) async {
        if (!_enabled) return markTestSkipped('set ONOTE_SCREENSHOTS=1 to render');
        if (!haveSqlite) return markTestSkipped('sqlite unavailable');
        await device(t, 'dialog_${d.key}_${size.width.toInt()}', size,
            touch: false, act: d.value);
      });
    }
  }

  // ── The marker under a word the app corrected ──────────────────────────────
  for (final b in [Brightness.light, Brightness.dark]) {
    testWidgets('autocorrect marker ${b.name}', (t) async {
      if (!_enabled) return markTestSkipped('set ONOTE_SCREENSHOTS=1 to render');
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final app = await seed(t);
      app.systemLocale = () => const Locale('en', 'AU');
      final blk = Block(
          id: 'fx',
          type: BlockType.text,
          x: 0,
          y: 0,
          w: 380,
          content: {
            'text': 'We went to the lab and I think we dont',
            'autoWidth': false
          });
      app.editingBlockId = 'fx';
      t.view.physicalSize = const Size(460, 150);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        theme: onoteTheme(b),
        debugShowCheckedModeBanner: false,
        builder: (c, child) => RepaintBoundary(key: key, child: child),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
                width: 380, child: TextBlockView(block: blk, app: app)),
          ),
        ),
      ));
      await t.showKeyboard(find.byType(TextField));
      const before = 'We went to the lab and I think we dont';
      t.testTextInput.updateEditingValue(const TextEditingValue(
          text: before, selection: TextSelection.collapsed(offset: before.length)));
      await t.pump();
      t.testTextInput.updateEditingValue(const TextEditingValue(
          text: '$before ',
          selection: TextSelection.collapsed(offset: before.length + 1)));
      await t.pump();
      await t.pump();
      await t.pump();
      await expectLater(
          find.byKey(key), matchesGoldenFile('goldens/autocorrect_marker_${b.name}.png'));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
      app.cancelPendingSave();
    });
  }

  // ── Review writing: the panel on a wide window, the sheet on a tall one ──
  for (final narrow in [false, true]) {
    for (final b in [Brightness.light, Brightness.dark]) {
      testWidgets('review writing ${narrow ? 'sheet' : 'panel'} ${b.name}',
          (t) async {
        if (!_enabled) return markTestSkipped('set ONOTE_SCREENSHOTS=1 to render');
        if (!haveSqlite) return markTestSkipped('sqlite unavailable');
        final app = await seed(t);
        await t.runAsync(() async {
          final blk = app.blocks.firstWhere((x) => x.type == BlockType.text);
          blk.content['text'] = 'The lecture covered how cells recieve signals '
              'from outside. Its a process called signalling, and their are '
              'three main types.\n\nRemember to check definately before the '
              'exam, but we seperated the samples anyway .';
          app.docRevision++;
          await OnoteText.warmUp(EnglishDialect.australian);
          app.systemLocale = () => const Locale('en', 'AU');
          await app.review.refresh();
        });
        t.view.physicalSize = narrow ? const Size(900, 1200) : const Size(1440, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final key = GlobalKey();
        await t.pumpWidget(MaterialApp(
          localizationsDelegates: kOnoteLocalizations,
          supportedLocales: kOnoteLocales,
          theme: onoteTheme(b),
          darkTheme: onoteTheme(Brightness.dark),
          themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          debugShowCheckedModeBanner: false,
          builder: (c, child) => RepaintBoundary(key: key, child: child),
          home: AppShell(app: app),
        ));
        for (var i = 0; i < 2; i++) {
          await t.pump(const Duration(milliseconds: 800));
          await t.pumpAndSettle();
        }
        app.toggleReview();
        await t.pumpAndSettle();
        app.review.openFirst();
        await t.pumpAndSettle();
        await expectLater(find.byKey(key),
            matchesGoldenFile('goldens/review_${narrow ? 'sheet' : 'panel'}_${b.name}.png'));
        app.cancelPendingSave();
      });
    }
  }
}
