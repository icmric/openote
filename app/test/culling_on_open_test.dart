// A page opened part-way down still draws what is on it.
//
// The owner: *"if the page loads already part way down, the page content wont
// load until i scroll up. I assume this has to do with detecting when to load
// something based on the top of the box rather than any of the perimiter."*
//
// Very nearly — it is the HEIGHT. A text block carries none: it is whatever
// its words come to, known only once it has been laid out and recorded in
// `renderSizes`, which `selectPage` clears. So on a page's first frame every
// auto-height block was assumed 60px tall, and a tall block whose top sits
// above the viewport did not overlap that guess. Culled, so never laid out,
// so never measured, so culled for ever.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/page_canvas.dart';
import 'package:openote/editor/text_block_view.dart';
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

  testWidgets('a tall block above the fold is drawn, not culled', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    AppState.syncLogEnabled = false;
    late Directory tmp;
    late Repository repo;
    late AppState app;
    await t.runAsync(() async {
      tmp = Directory.systemTemp.createTempSync('onote_cull_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('C');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
      app.importPage(
          nb.id,
          page.id,
          [
            // Far enough down that the FIRST frame — which is drawn before
            // the remembered view is restored — never shows it, so it is
            // never measured there either. Genuinely long, and carrying no
            // `h`, exactly like every paragraph anybody writes.
            Block(
              type: BlockType.text,
              x: 60,
              y: 2000,
              w: 420,
              content: {
                'text': List.generate(60, (i) => 'Line $i of a long note.')
                    .join('\n'),
                'autoWidth': false,
              },
            ),
          ],
          PageProps());
      app.reloadNodes();
      await app.selectPage(page.id);
      // **Scrolled down before the first frame**, through the same route the
      // app uses: a page remembers the view it was left at and restores it on
      // open. So this block is never once laid out at the top of the screen
      // and never once measured. Panning the controller directly would not
      // do — mounting the canvas restores the remembered view over it.
      app.canvas.panBy(const Offset(0, -2400));
      app.rememberViewForTest(page.id);
      app.canvas.jumpTo(1, Offset.zero);
    });
    app.markOnboardingSeen();
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    addTearDown(() {
      AppState.syncLogEnabled = true;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      home: AppShell(app: app),
    ));
    await t.pump(const Duration(milliseconds: 900));
    await t.pumpAndSettle();


    expect(find.byType(TextBlockView), findsOneWidget,
        reason: 'the block covers the whole screen at this scroll position; '
            'it was culled on a 60px guess at its height, and stayed culled '
            'because a block that is never laid out is never measured');
    expect(find.byType(PageCanvas), findsOneWidget);
    // And now that it has been drawn once, it is measured — which is what
    // lets every later frame cull it honestly.
    expect(app.renderSizes.values.map((s) => s.height).single,
        greaterThan(1000),
        reason: 'a block that is never laid out is never measured, which is '
            'why the wrong guess was permanent rather than momentary');
  });
}
