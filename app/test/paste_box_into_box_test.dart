// A box cut from the canvas pastes its writing into the box you are editing.
//
// The owner: *"if i cut a whole box at the moment i can paste the box in its
// entirety onto the canvas somewhere, however if i cut a box, begin editing
// another box and attempt to paste it within another box, it just pastes
// whatever is in my clipboard. Id ideally like it to paste the contents of
// that box into the box im currently editing."*
//
// The projection is the interesting part: a paragraph brings its own text,
// and anything it was carrying — a table, a picture — has to come with it.
// A table's payload lives in the host block's own `atoms` map, so pasting the
// text alone would leave a reference pointing at nothing, which is the
// "pointer to a payload nothing can reach" the editor guards against
// everywhere else.
//
// And some boxes have no writing at all. Handwriting, a graph, a board, a
// page window: there is no honest text for those, so the whole paste declines
// rather than silently dropping them, and they still paste on the canvas.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/model/inline_atom.dart';
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
    tmp = Directory.systemTemp.createTempSync('onote_boxpaste_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('B');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    // No real clipboard under the harness; the copy-time snapshot must not
    // try to read one.
    app.readSystemClipboardText = () async => null;
    app.reloadNodes();
    await app.selectPage(
        app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
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

  /// A box on the page. [content] is its own; the type decides what it is.
  Block add(BlockType type, Map<String, dynamic> content,
      {double y = 100, double x = 60, double? h}) {
    final b = Block(type: type, x: x, y: y, w: 300, h: h, content: content);
    app.addBlock(b, recordUndo: false);
    return b;
  }

  /// Cut [bs] to the block clipboard, as Ctrl+X on the canvas does.
  void cut(List<Block> bs) {
    app.selectMany({for (final b in bs) b.id});
    app.cutSelectedBlocks();
  }

  /// Open [host] for editing, with the caret at [caret].
  ///
  /// Registered the way the widget does when it builds — a real
  /// LiveMarkdownController, so the picture and marker rules that live in it
  /// apply to a paste exactly as they do to typing.
  Block open(Block host, {int? caret}) {
    final c = LiveMarkdownController(
        text: host.content['text'] as String? ?? '', dark: false);
    addTearDown(c.dispose);
    app.select(host.id, edit: true);
    app.setActiveEditor(c, host, 'text');
    if (caret != null) {
      c.selection = TextSelection.collapsed(offset: caret);
    }
    return host;
  }

  /// A fresh destination box, open for editing.
  Block editing(String text, {int? caret}) =>
      open(add(BlockType.text, {'text': text}, y: 400), caret: caret);

  group('what a box reads as', () {
    test('a paragraph brings its own writing', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      cut([add(BlockType.text, {'text': 'osmosis is diffusion'})]);
      expect(app.blockClipboardAsText()?.text, 'osmosis is diffusion');
    });

    test('a code box comes as a fence, with its language', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      cut([
        add(BlockType.code, {'source': 'print(1)', 'language': 'python'})
      ]);
      expect(app.blockClipboardAsText()?.text, '```python\nprint(1)\n```');
    });

    test('an equation comes as an equation', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      cut([
        add(BlockType.math, {'latex': 'x^2'})
      ]);
      expect(app.blockClipboardAsText()?.text, r'$$' '\n' r'x^2' '\n' r'$$');
    });

    test('a picture comes as its reference, at the size it was', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      cut([
        add(BlockType.image, {'blob': 'sha256:abc'}, h: 200)
      ]);
      expect(app.blockClipboardAsText()?.text, '![](sha256:abc =300x200)');
    });

    test('several boxes come in the order they sit on the page', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Cut in one order, laid out in another: the page decides.
      final low = add(BlockType.text, {'text': 'second'}, y: 300);
      final high = add(BlockType.text, {'text': 'first'}, y: 100);
      cut([low, high]);
      expect(app.blockClipboardAsText()?.text, 'first\n\nsecond');
    });

    test('a box with no writing in it declines, and so does the whole paste',
        () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      for (final b in [
        add(BlockType.ink, {'strokes': <dynamic>[]}),
        add(BlockType.graph, {'latex': 'y=x'}),
        add(BlockType.board, {'columns': <dynamic>[]}),
        add(BlockType.file, {'blob': 'sha256:abc', 'name': 'notes.pdf'}),
      ]) {
        cut([b]);
        expect(app.blockClipboardAsText(), isNull, reason: '${b.type}');
      }
      // ALL or nothing: half a paste would lose the handwriting silently.
      cut([
        add(BlockType.text, {'text': 'words'}),
        add(BlockType.ink, {'strokes': <dynamic>[]}, y: 200),
      ]);
      expect(app.blockClipboardAsText(), isNull);
    });

    test('a box from a NEWER Openote declines rather than being flattened',
        () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Its type and content are carried through untouched; inventing text
      // for it is the one way to lose it. It still pastes on the canvas.
      final odd = Block.fromJson({
        'id': 'n1',
        'type': 'hologram',
        'x': 60.0,
        'y': 100.0,
        'w': 300.0,
        'content': {'spin': 3},
      });
      app.addBlock(odd, recordUndo: false);
      cut([odd]);
      expect(app.blockClipboardAsText(), isNull);
      expect(odd.rawType, 'hologram', reason: 'and it is still itself');
    });

    test('nothing on the clipboard reads as nothing', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      expect(app.blockClipboardAsText(), isNull);
    });
  });

  group('pasted into the box being edited', () {
    test('the writing lands at the caret', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      cut([add(BlockType.text, {'text': 'osmosis'})]);
      final host = editing('Before  after', caret: 7);
      expect(app.pasteBlocksIntoText(), isTrue);
      expect(host.content['text'], 'Before osmosis after');
    });

    test("a table comes with its payload, under an id of its own", () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The reference is a pointer; its payload lives in the host block. A
      // paste that moved the words and not the table would write a reference
      // to nothing — which is exactly what the editor guards against.
      const atom = InlineAtom(id: 't1', type: 'table', content: {
        'cells': [
          ['Element', 'Symbol'],
          ['Sodium', 'Na'],
        ]
      });
      final content = <String, dynamic>{
        'text': 'Results: ${atom.reference('2x2 table')}'
      };
      InlineAtom.putIn(content, atom);
      cut([add(BlockType.text, content)]);

      final host = editing('', caret: 0);
      expect(app.pasteBlocksIntoText(), isTrue);
      final text = host.content['text'] as String;
      final ids = InlineAtom.idsIn(text);
      expect(ids, hasLength(1));
      expect(ids.single, isNot('t1'),
          reason: 'a paste mints: the payload is a copy, not the original');
      final atoms = InlineAtom.allIn(host.content);
      expect(atoms.keys, ids, reason: 'the reference resolves in its new home');
      expect(atoms[ids.single]!.content['cells'], atom.content['cells']);
    });

    test('and an existing table in the destination is kept', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      const mine = InlineAtom(id: 'm1', type: 'table', content: {
        'cells': [['mine']]
      });
      const theirs = InlineAtom(id: 't1', type: 'table', content: {
        'cells': [['theirs']]
      });
      final theirContent = <String, dynamic>{'text': theirs.reference('t')};
      InlineAtom.putIn(theirContent, theirs);
      cut([add(BlockType.text, theirContent)]);

      final hostContent = <String, dynamic>{'text': mine.reference('m')};
      InlineAtom.putIn(hostContent, mine);
      final host = open(add(BlockType.text, hostContent, y: 400),
          caret: (hostContent['text'] as String).length);

      expect(app.pasteBlocksIntoText(), isTrue);
      final atoms = InlineAtom.allIn(host.content);
      expect(atoms, hasLength(2));
      expect(
          atoms.values.map((a) => (a.content['cells'] as List).first),
          containsAll([
            ['mine'],
            ['theirs']
          ]));
    });

    test('a picture pasted into a paragraph gets a line of its own', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The rule pictures already have (picture_stays_whole_test) applies to
      // a paste as to anything else — a picture sharing a line is a hash.
      cut([
        add(BlockType.image, {'blob': 'sha256:abc'}, h: 200)
      ]);
      final host = editing('Hello world', caret: 6);
      expect(app.pasteBlocksIntoText(), isTrue);
      expect(host.content['text'],
          'Hello \n![](sha256:abc =300x200)\nworld');
    });

    test('it is one undo step', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      cut([add(BlockType.text, {'text': 'osmosis'})]);
      final host = editing('Before ', caret: 7);
      expect(app.pasteBlocksIntoText(), isTrue);
      expect(host.content['text'], 'Before osmosis');
      app.undo();
      expect(
          app.blocks.firstWhere((b) => b.id == host.id).content['text'],
          'Before ');
    });

    test('not into a code box, which is not Markdown', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      cut([add(BlockType.text, {'text': 'osmosis'})]);
      final code = add(BlockType.code, {'source': 'x = 1', 'language': 'python'},
          y: 400);
      final c = TextEditingController(text: 'x = 1');
      addTearDown(c.dispose);
      app.select(code.id, edit: true);
      app.setActiveEditor(c, code, 'source');
      expect(app.pasteBlocksIntoText(), isFalse);
      expect(code.content['source'], 'x = 1');
    });

    test('and not when no box is being edited', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      cut([add(BlockType.text, {'text': 'osmosis'})]);
      app.select(null);
      app.activeEditor = null;
      expect(app.pasteBlocksIntoText(), isFalse);
    });

    test('the boxes are still there to paste on the canvas afterwards', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Pasting into a box does not consume the clipboard, so the same cut
      // can go on the canvas as well.
      cut([add(BlockType.text, {'text': 'osmosis'})]);
      editing('', caret: 0);
      expect(app.pasteBlocksIntoText(), isTrue);
      expect(app.canPasteBlocks, isTrue);
      final before = app.blocks.length;
      app.pasteBlocks(at: const Offset(500, 500));
      expect(app.blocks.length, before + 1);
    });
  });

  // -- Where the caret ends up -------------------------------------------
  //
  // The owner, on the paste shipped in v1.0.2: *"the image got pasted in
  // twice, I also had to press undo a couple of times before anything
  // happened ... so it seems like there is a bug with extracting content and
  // pasting it in."*
  //
  // The projection was right; the caret was not. `insertTextAtActiveCursor`
  // set the text and then the caret in TWO value assignments, and the
  // controller's guards read the selection — so the first assignment (whose
  // selection Flutter's own `.text` setter invalidates) could not move the
  // caret, and the second computed it against text the guards had since
  // changed. Measured before the fix: pasting a box ending in a picture left
  // the caret at the START of that picture's reference, one keystroke from
  // "the image disapears but the hash appears".
  group('the caret after a paste', () {
    /// A picture reference the way a box holds one.
    String pic(String tail, {String size = '=90x60'}) =>
        '![](sha256:${'ab' * 32}$tail $size)';

    test('lands after the pasted writing', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      cut([add(BlockType.text, {'text': 'osmosis'})]);
      final host = editing('Notes: ', caret: 7);
      expect(app.pasteBlocksIntoText(), isTrue);
      expect(app.activeEditor!.controller.text, 'Notes: osmosis');
      expect(app.activeEditor!.controller.selection.baseOffset, 14);
      expect(host.content['text'], 'Notes: osmosis');
    });

    test('and after it when the picture rule had to add a line break', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The host is a picture on its own line and the caret is at its end, so
      // the pasted words have to be given a line of their own — which shifts
      // every offset after the break, the caret included.
      cut([add(BlockType.text, {'text': 'just words'})]);
      final ref = pic('');
      editing(ref, caret: ref.length);
      expect(app.pasteBlocksIntoText(), isTrue);
      final c = app.activeEditor!.controller;
      expect(c.text, '$ref\njust words');
      expect(c.selection.baseOffset, c.text.length,
          reason: 'after the pasted words, not one short of them');
    });

    test('never INSIDE the reference of a pasted picture', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // This is the one that mattered: the caret landed at `o.start` of the
      // picture it had just pasted. Typing there splices a character into the
      // reference, it stops matching, and the picture becomes its own hash.
      final src = pic('cd', size: '=120x80');
      cut([
        add(BlockType.text, {'text': 'some words\n$src'})
      ]);
      final hostRef = pic('ff');
      editing(hostRef, caret: hostRef.length);
      expect(app.pasteBlocksIntoText(), isTrue);
      final c = app.activeEditor!.controller;
      expect(c.text, '$hostRef\nsome words\n$src');
      expect(c.selection.baseOffset, c.text.length);
      // And both pictures are whole.
      expect(RegExp(r'!\[\]\(sha256:').allMatches(c.text), hasLength(2));
    });
  });

  // -- One undo step, and it takes the payloads with it ------------------
  group('undoing a paste', () {
    test('gives back the text AND the atoms the paste brought', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The undo point used to be taken INSIDE the insert, which runs after
      // the atoms are written — so the snapshot Ctrl+Z restored already had
      // the pasted payloads in it, and undo left a table's data behind in the
      // destination block for good.
      const atomId = 'atom-1';
      cut([
        add(BlockType.text, {
          'text': 'see ![t](${InlineAtom.scheme}$atomId) there',
          'atoms': {
            atomId: const InlineAtom(
                id: atomId,
                type: 'table',
                content: {'rows': <dynamic>[]}).toJson(),
          },
        })
      ]);
      final host = editing('Notes: ', caret: 7);
      expect(app.pasteBlocksIntoText(), isTrue);
      expect(InlineAtom.allIn(host.content), isNotEmpty,
          reason: 'precondition: the payload came with it');

      app.undo();
      final back = app.blocks.firstWhere((b) => b.id == host.id);
      expect(back.content['text'], 'Notes: ');
      expect(InlineAtom.allIn(back.content), isEmpty,
          reason: 'no payload left pointing at nothing');
    });

    test('is ONE step, not two', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      cut([add(BlockType.text, {'text': 'osmosis'})]);
      final host = editing('Notes: ', caret: 7);
      final deep = app.canUndo;
      expect(app.pasteBlocksIntoText(), isTrue);
      app.undo();
      expect(app.blocks.firstWhere((b) => b.id == host.id).content['text'],
          'Notes: ');
      expect(app.canUndo, deep, reason: 'the paste added exactly one step');
    });

    test('keeps the caret in the box you were writing in', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Ctrl+Z inside a box is this stack's step now, so it must not throw
      // you out of the box — `TextBlockView` re-seeds the open session from
      // the restored block.
      cut([add(BlockType.text, {'text': 'osmosis'})]);
      final host = editing('Notes: ', caret: 7);
      expect(app.pasteBlocksIntoText(), isTrue);
      app.undo();
      expect(app.editingBlockId, host.id);
      expect(app.selectedBlockId, host.id);
      expect(app.selectedIds, contains(host.id),
          reason: 'the three fields `select` sets together stay together — '
              '`BlockView.selected` reads selectedIds, so a box being typed '
              'into that is not in there has no move bar and no handles');
    });

    test('NEGATIVE CONTROL: a box that is not in the step does not reopen',
        () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Undoing back past the box's own creation: there is nothing to edit,
      // and `editingBlockId` must not survive as a name for a box that is
      // no longer on the page.
      app.pushUndo(); // a page without the box
      final host = editing('Notes: ', caret: 7);
      expect(app.editingBlockId, host.id, reason: 'precondition');
      app.undo();
      expect(app.blocks.any((b) => b.id == host.id), isFalse,
          reason: 'the step being restored never had it');
      expect(app.editingBlockId, isNull);
    });
  });

  // -- Which clipboard is the newer one ----------------------------------
  group('the newer-clipboard check', () {
    test('compares the plain text the clipboard holds, on both sides',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // `probeClipboard` reports `text: null` for a clipboard holding an
      // IMAGE — correctly, because an image is what would paste — but the
      // snapshot taken when the boxes were copied reads the plain text
      // unconditionally. Feeding this the kind's `text` therefore compared
      // null against the text that was really there, ruled the boxes stale,
      // and pasted the clipboard's picture instead of the box just cut. It
      // takes `plainText` now: the same question on both sides.
      app.readSystemClipboardText = () async => 'what was there';
      cut([add(BlockType.text, {'text': 'osmosis'})]);
      expect(await app.blockClipboardIsNewer('what was there'), isTrue);
      expect(await app.blockClipboardIsNewer(null), isFalse,
          reason: 'null is not "the same text"; it is a different clipboard');
      expect(await app.blockClipboardIsNewer('something newer'), isFalse);
    });
  });
}
