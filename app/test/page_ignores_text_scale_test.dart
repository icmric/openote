// The page is a drawing surface: its boxes sit at fixed places and its tables
// have fixed column widths measured with unscaled text. A phone set to a large
// system font made the text in them bigger than the room measured for it, so it
// wrapped and landed on whatever was beside it. The page draws its text at its
// own size whatever the system setting is; the pinch zoom is how it is enlarged.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

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
    tmp = Directory.systemTemp.createTempSync('onote_textscale_');
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

  Future<void> pump(WidgetTester t, double scale) async {
    final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
    app.importPage(app.notebookId!, page.id, [
      Block(
          type: BlockType.text,
          x: 80,
          y: 120,
          w: 300,
          h: 120,
          content: {'text': 'Every cell is measured', 'autoWidth': false}),
    ], PageProps());
    app.reloadNodes();
    await app.selectPage(page.id);
    app.markOnboardingSeen();
    t.view.physicalSize = const Size(1500, 950);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: AppShell(app: app),
    ));
    await t.pump(const Duration(milliseconds: 900));
    await t.pumpAndSettle();
  }

  testWidgets('a large system font does not enlarge the text on the page',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t, 1.6);
    final onPage = t.renderObject<RenderParagraph>(
        find.textContaining('Every cell is measured').first);
    expect(onPage.textScaler.scale(10), 10,
        reason: 'the page draws its text at its own size');
    // The chrome around it still follows the setting.
    final chrome = t.renderObject<RenderParagraph>(find.text('Insert').first);
    expect(chrome.textScaler.scale(10), closeTo(16, .01),
        reason: 'the toolbar still honours the system font size');
    app.cancelPendingSave();
  });
}
