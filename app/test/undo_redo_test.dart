// Undo/redo is the app's riskiest state machine and had zero coverage. These
// tests are pure — no widgets, no database — because `AppState`'s snapshot stack
// only touches `blocks`/`pageProps`.
//
// One of them (`a table edit is undoable`) is a regression test: table cells
// were written with `markDirty()` but no `pushUndo()`, unlike every other
// editor, so Ctrl+Z skipped past all the typing in a table.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

/// A repository stub: undo/redo never reaches storage, and constructing a real
/// one would drag SQLite into a pure test.
class _NoopRepo implements Repository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

AppState _app() {
  final app = AppState(_NoopRepo())
    ..notebookId = 'nb'
    ..pageId = 'pg';
  return app;
}

Block _text(String s, {double x = 10, double y = 20}) =>
    Block(type: BlockType.text, x: x, y: y, content: {'text': s});

void main() {
  test('undo restores the pre-change block list', () {
    final app = _app()..blocks = [_text('first')];
    app.addBlock(_text('second'));
    expect(app.blocks.length, 2);

    app.undo();
    expect(app.blocks.length, 1);
    expect(app.blocks.single.content['text'], 'first');
  });

  test('undo then redo is an identity', () {
    final app = _app()..blocks = [_text('a')];
    app.addBlock(_text('b'));
    final before = app.blocks.map((b) => b.content['text']).toList();

    app.undo();
    app.redo();
    expect(app.blocks.map((b) => b.content['text']).toList(), before);
  });

  test('a fresh change clears the redo stack', () {
    final app = _app()..blocks = [_text('a')];
    app.addBlock(_text('b'));
    app.undo();
    expect(app.canRedo, true);

    app.addBlock(_text('c')); // diverges from the undone future
    expect(app.canRedo, false,
        reason: 'redoing after a new edit would resurrect a discarded branch');
  });

  test('restoring a snapshot clears selection and editing state', () {
    final app = _app()..blocks = [_text('a')];
    final b = app.addBlock(_text('b'));
    app.select(b.id, edit: true);
    expect(app.selectedIds, isNotEmpty);
    expect(app.editingBlockId, b.id);

    app.undo();
    expect(app.selectedIds, isEmpty,
        reason: 'the selected block may no longer exist after a restore');
    expect(app.editingBlockId, isNull);
    expect(app.selectedBlockId, isNull);
  });

  test('the undo stack is capped and drops the OLDEST entry', () {
    final app = _app()..blocks = [];
    // 105 pushes over a 100-entry cap: the earliest states must fall off, and
    // the most recent 100 must remain reachable.
    for (var i = 0; i < 105; i++) {
      app.addBlock(_text('block $i'));
    }
    expect(app.blocks.length, 105);
    for (var i = 0; i < 100; i++) {
      app.undo();
    }
    expect(app.canUndo, false, reason: 'exactly 100 states were retained');
    // Having exhausted the stack we are back at the oldest RETAINED state,
    // which is 5 blocks in — not the empty page.
    expect(app.blocks.length, 5);
  });

  test('page props round-trip through undo', () {
    final app = _app()..blocks = [];
    app.pageProps.background = 'blank';
    app.setBackground('grid');
    expect(app.pageProps.background, 'grid');
    app.undo();
    expect(app.pageProps.background, 'blank');
  });

  test('undo is a no-op on an empty stack', () {
    final app = _app()..blocks = [_text('only')];
    app.undo();
    app.redo();
    expect(app.blocks.single.content['text'], 'only');
  });

  test('a table edit is undoable (regression: table writes skipped pushUndo)',
      () {
    final app = _app()..blocks = [];
    final table = app.addBlock(Block(
      type: BlockType.table,
      x: 0,
      y: 0,
      content: {
        'cells': [
          ['a', 'b'],
          ['c', 'd'],
        ]
      },
    ));
    // What TableBlockView._write does on a cell commit.
    app.pushUndo();
    table.content['cells'] = [
      ['CHANGED', 'b'],
      ['c', 'd'],
    ];
    app.updateBlock(table);

    app.undo();
    final cells = app.blocks.single.content['cells'] as List;
    expect((cells.first as List).first, 'a',
        reason: 'undo must step back over the table edit, not past it');
  });
}
