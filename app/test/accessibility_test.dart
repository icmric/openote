// What a screen reader actually gets.
//
// The first version of the v0.24 review said "121 Tooltips against 6 uses of
// Semantics" and concluded the app was unusable with a screen reader. That
// inference was wrong, and this file is the measurement that replaced it: a
// `Tooltip` IS a semantic label — Flutter wraps its child in
// `Semantics(label: message)`, and `IconButton` builds one from its `tooltip:`
// — so the tooltips are labels, and the page's own words reach the semantics
// tree through the ordinary `Text` widgets that draw them.
//
// The one real hole was maths. `Math.tex` paints glyph boxes and says nothing,
// so an equation was silence in the middle of a page that otherwise reads
// perfectly. It now carries its own LaTeX as a label — not spoken maths, which
// is designed in v0.21 and not built, but what the student typed, which beats
// nothing.
//
// These assertions exist so the claim in the review stays true: a control that
// loses its tooltip, or a canvas that stops exposing its text, turns one of
// them red.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/math/math_view.dart';
import 'package:openote/ui/app_shell.dart';

import 'support/app.dart';
import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  /// Every non-empty label in the tree, flattened.
  List<String> labelsIn(WidgetTester tester) {
    final out = <String>[];
    void walk(SemanticsNode n) {
      final label = n.getSemanticsData().label;
      if (label.isNotEmpty) out.add(label);
      n.visitChildren((c) {
        walk(c);
        return true;
      });
    }

    walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
    return out;
  }

  testWidgets('an equation is announced, not silent', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(testApp(const Scaffold(
      body: Center(
        child: OnoteMath(r'E=mc^{2}', textStyle: TextStyle(fontSize: 20)),
      ),
    )));
    await tester.pumpAndSettle();

    expect(labelsIn(tester).any((s) => s.contains('E=mc^{2}')), isTrue,
        reason: 'a rendered equation must carry its source as a label — '
            'without it, it is a silent hole in a page that otherwise reads');
    handle.dispose();
  });

  testWidgets('the shell labels its controls and exposes the page text',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final handle = tester.ensureSemantics();
    AppState.syncLogEnabled = false;
    addTearDown(() => AppState.syncLogEnabled = true);

    late Repository repo;
    late AppState app;
    final tmp = Directory.systemTemp.createTempSync('onote_a11y_');
    await tester.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Biology');
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
            content: {'text': 'The mitochondrion is the powerhouse'}),
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
    app.markOnboardingSeen();

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(testApp(AppShell(app: app),
        brightness: Brightness.light));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    final labels = labelsIn(tester);
    expect(labels.any((s) => s.contains('mitochondrion')), isTrue,
        reason: 'the words on the page reach the semantics tree — this is the '
            'claim the review makes, and it is what makes the app readable '
            'at all with a screen reader');
    expect(labels.length, greaterThan(8),
        reason: 'the chrome labels its controls: every icon-only button in '
            'the app carries a tooltip, and a Tooltip IS a Semantics label');
    app.cancelPendingSave();
    handle.dispose();
  });

  test('every icon-only button carries a tooltip', () {
    // The source scan behind the claim above. An `IconButton` with no
    // `tooltip:` is unlabelled unless a parent `Tooltip` supplies one; three
    // in `command_bar.dart` are exactly that case (the study and planner
    // badges, and the font button), and they are listed here so a FOURTH one
    // appearing has to be a decision rather than an oversight.
    const knownWrappedByParent = 3;
    var missing = 0;
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final chunk in source.split('IconButton(').skip(1)) {
        var depth = 1, i = 0;
        while (i < chunk.length && depth > 0) {
          if (chunk[i] == '(') depth++;
          if (chunk[i] == ')') depth--;
          i++;
        }
        if (!chunk.substring(0, i).contains('tooltip:')) missing++;
      }
    }
    expect(missing, lessThanOrEqualTo(knownWrappedByParent),
        reason: 'an icon with no words beside it and no tooltip is a button '
            'nobody can name — either give it one, or wrap it in a Tooltip '
            'and raise the count here with a note saying which');
  });
}
