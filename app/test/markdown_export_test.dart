// The Markdown projection of a graph or a substitute block.
//
// Neither type had a test here before today. `pageMarkdownOf` is the ONE
// function both the file exporter and the external API's `read_page` share
// (see its own doc comment), so a block silently falling through its
// `switch` — the exact way `board` once did for a whole release — would
// have been invisible to a person reading the exported page AND to anything
// calling the API, with nothing on either side to say a block went missing.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/export/markdown_export.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

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
    tmp = Directory.systemTemp.createTempSync('onote_mdexport_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('T');
    app = AppState(repo)..notebookId = nb.id;
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

  group('a graph block', () {
    test('carries its equation, not nothing', () {
      if (!haveSqlite) return;
      final md = pageMarkdownOf(app, 'Curves', [
        Block(type: BlockType.graph, x: 0, y: 0, w: 300, h: 200,
            content: {'latex': 'y=3x+10'}),
      ]);
      expect(md, contains('y=3x+10'));
      expect(md, contains('Graph of'));
    });

    test('an empty graph writes nothing for itself, and nothing throws', () {
      if (!haveSqlite) return;
      final md = pageMarkdownOf(app, 'Curves', [
        Block(type: BlockType.graph, x: 0, y: 0, w: 300, h: 200,
            content: {'latex': ''}),
      ]);
      expect(md, isNot(contains('Graph of')));
    });
  });

  group('a substitute block', () {
    test('with a value carries the equation AND the worked-out result', () {
      if (!haveSqlite) return;
      final md = pageMarkdownOf(app, 'Numbers', [
        Block(type: BlockType.substitute, x: 0, y: 0, w: 260,
            content: {'latex': 'y=3x+10', 'value': '2'}),
      ]);
      expect(md, contains('y=3x+10'));
      expect(md, contains('x = 2'));
      expect(md, contains('16'),
          reason: '3 × 2 + 10 = 16, and it is IN the exported text');
    });

    test('with nothing typed yet carries only the equation', () {
      if (!haveSqlite) return;
      final md = pageMarkdownOf(app, 'Numbers', [
        Block(type: BlockType.substitute, x: 0, y: 0, w: 260,
            content: {'latex': 'y=3x+10', 'value': ''}),
      ]);
      expect(md, contains('y=3x+10'));
      expect(md, contains('Evaluate'));
      expect(md, isNot(contains('16')));
    });

    test('a bad value reads as the calculator error, not a crash', () {
      if (!haveSqlite) return;
      final md = pageMarkdownOf(app, 'Numbers', [
        Block(type: BlockType.substitute, x: 0, y: 0, w: 260,
            content: {'latex': 'y=3x+10', 'value': 'banana'}),
      ]);
      expect(md, contains('y=3x+10'));
      expect(md, isNotEmpty);
    });

    test('an empty substitute block writes nothing for itself', () {
      if (!haveSqlite) return;
      final md = pageMarkdownOf(app, 'Numbers', [
        Block(type: BlockType.substitute, x: 0, y: 0, w: 260,
            content: {'latex': '', 'value': ''}),
      ]);
      expect(md, isNot(contains('Evaluate')));
    });
  });

  test('a graph and a substitute block on the same page both survive', () {
    if (!haveSqlite) return;
    final md = pageMarkdownOf(app, 'Both', [
      Block(type: BlockType.graph, x: 0, y: 0, w: 300, h: 200,
          content: {'latex': 'y=x^2'}),
      Block(type: BlockType.substitute, x: 0, y: 300, w: 260,
          content: {'latex': 'y=x^2', 'value': '3'}),
    ]);
    expect(md, contains('Graph of'));
    expect(md, contains('Evaluate'));
    expect(md, contains('9'), reason: '3² = 9');
  });
}
