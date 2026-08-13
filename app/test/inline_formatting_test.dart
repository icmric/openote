// The formatting commands (Ctrl+B and friends), which had no test at all —
// which is how "Ctrl+B writes a visible **** into the note and one Backspace
// leaves ***" reached a user.
//
// These drive AppState directly through a registered editor, the same seam
// the toolbar and the shortcuts use.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/list_editing.dart';
import 'package:openote/markdown/md_syntax.dart';
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
  late TextEditingController c;
  late Block block;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_fmt_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('T');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    await app.selectPage(
        app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
    block = Block(type: BlockType.text, x: 0, y: 0, content: {'text': ''});
    app.addBlock(block, recordUndo: false);
    c = TextEditingController();
    app.setActiveEditor(c, block, 'text');
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

  /// Put `text` in the editor with the caret at `|` (or a selection at `«»`).
  void edit(String spec) {
    final b = spec.indexOf('«');
    if (b >= 0) {
      final e = spec.indexOf('»');
      c.value = TextEditingValue(
        text: spec.replaceAll('«', '').replaceAll('»', ''),
        selection: TextSelection(baseOffset: b, extentOffset: e - 1),
      );
      return;
    }
    final i = spec.indexOf('|');
    c.value = TextEditingValue(
      text: spec.replaceFirst('|', ''),
      selection: TextSelection.collapsed(offset: i),
    );
  }

  group('Ctrl+B with nothing selected', () {
    test('formats the WORD the caret is in — it never writes bare markers',
        () {
      if (!haveSqlite) return;
      edit('make this bo|ld please');
      app.wrapSelection('**');
      expect(c.text, 'make this **bold** please');
      expect(c.text.contains('****'), isFalse,
          reason: 'the reported bug: a bare marker pair in the note');
    });

    test('pressing it again on the same word takes the bold off', () {
      if (!haveSqlite) return;
      edit('make this bo|ld please');
      app.wrapSelection('**');
      // The caret is inside the run now; toggling must remove it, not nest.
      c.selection = const TextSelection.collapsed(offset: 14);
      app.wrapSelection('**');
      expect(c.text, 'make this bold please');
    });

    test('in empty space it does nothing rather than leaving markers behind',
        () {
      if (!haveSqlite) return;
      edit('word |');
      app.wrapSelection('**');
      expect(c.text, 'word ');
    });

    test('every mark behaves the same way', () {
      if (!haveSqlite) return;
      for (final m in ['**', '*', '++', '~~', '`', '==']) {
        edit('a wo|rd b');
        app.wrapSelection(m);
        expect(c.text, 'a ${m}word$m b', reason: 'mark "$m"');
      }
    });
  });

  group('with a selection', () {
    test('wraps it and keeps it selected', () {
      if (!haveSqlite) return;
      edit('say «hello» there');
      app.wrapSelection('**');
      expect(c.text, 'say **hello** there');
      expect(c.text.substring(c.selection.start, c.selection.end), 'hello');
    });

    test('unwraps when the selection is exactly the run', () {
      if (!haveSqlite) return;
      edit('say **«hello»** there');
      app.wrapSelection('**');
      expect(c.text, 'say hello there');
    });

    test('unwraps from a PARTIAL selection inside the run', () {
      if (!haveSqlite) return;
      edit('say **h«ell»o** there');
      app.wrapSelection('**');
      expect(c.text, 'say hello there',
          reason: 'it used to nest a second empty pair instead');
    });
  });

  group('a selection is trimmed to what it actually formats', () {
    test('trailing spaces stay OUTSIDE the markers', () {
      if (!haveSqlite) return;
      // The selection is "hello " — the trailing space included, which is
      // what a double-click-and-drag usually grabs.
      edit('say «hello »there');
      app.wrapSelection('**');
      // `**hello **` matches nothing — a marker may not sit against a space
      // — so the asterisks would have stayed visible in the note forever.
      expect(c.text, 'say **hello** there');
    });

    test('a selection of only whitespace does nothing', () {
      if (!haveSqlite) return;
      edit('a«   »b');
      app.wrapSelection('**');
      expect(c.text, 'a   b');
    });

    test('a multi-line selection formats each line, not across them', () {
      if (!haveSqlite) return;
      edit('«one\ntwo»');
      app.wrapSelection('**');
      expect(c.text, '**one**\n**two**',
          reason: 'markers must open and close on the same line, or the '
              'line-based grammar can never match them');
    });

    test('blank lines inside a multi-line selection stay blank', () {
      if (!haveSqlite) return;
      edit('«one\n\ntwo»');
      app.wrapSelection('**');
      expect(c.text, '**one**\n\n**two**');
    });
  });

  group('the caret at the start of a list item', () {
    test('Ctrl+B bolds the word, never the bullet', () {
      if (!haveSqlite) return;
      edit('- |item');
      app.wrapSelection('**');
      expect(c.text, '- **item**',
          reason: 'a hyphen must not count as part of the word');
    });
  });

  group('bold + italic together', () {
    test('produces ***word***, which renders as both', () {
      if (!haveSqlite) return;
      edit('a wo|rd b');
      app.wrapSelection('**');
      c.selection = const TextSelection.collapsed(offset: 8);
      app.wrapSelection('*');
      expect(c.text, 'a ***word*** b');
      // And the grammar agrees it is one bold-italic run, not bold plus a
      // stray asterisk — the imported-formatting bug, reachable by keyboard.
      final marks = [
        for (final m in mdInlineRe.allMatches(c.text)) classifyInline(m).kind
      ];
      expect(marks, [MdInline.boldItalic]);
    });
  });

  group('a mark nested inside another', () {
    test('can be toggled off without corrupting the outer one', () {
      if (!haveSqlite) return;
      edit('**bold *it* end**');
      c.selection = const TextSelection.collapsed(offset: 9); // in "it"
      app.wrapSelection('*');
      expect(c.text, '**bold it end**',
          reason: 'it used to wrap again as `**bold **it** end**`, which '
              'then re-reads as one bold run with literal asterisks in it');
    });

    test('lights its toolbar button', () {
      if (!haveSqlite) return;
      edit('**bold *it|* end**');
      final marks = app.marksAtCaret();
      expect(marks, contains(MdInline.italic),
          reason: 'the italic read as OFF the instant it was applied');
      expect(marks, contains(MdInline.bold));
    });

    test('highlight inside bold reports both', () {
      if (!haveSqlite) return;
      edit('**a ==hi|gh== b**');
      final marks = app.marksAtCaret();
      expect(marks, containsAll([MdInline.bold, MdInline.highlight]));
    });
  });

  group('a code cell is not prose', () {
    test('Ctrl+B does not inject Markdown into source code', () {
      if (!haveSqlite) return;
      final code = Block(type: BlockType.code, x: 0, y: 0,
          content: {'language': 'js', 'source': 'let x = 2;'});
      app.addBlock(code, recordUndo: false);
      final cc = TextEditingController(text: 'let x = 2;');
      cc.selection = const TextSelection.collapsed(offset: 5);
      app.setActiveEditor(cc, code, 'source');
      app.wrapSelection('**');
      expect(cc.text, 'let x = 2;');
    });
  });

  group('the toolbar knows what is on at the caret', () {
    test('inside a bold run, Bold reads as active', () {
      if (!haveSqlite) return;
      edit('say **hel|lo** there');
      expect(app.marksAtCaret(), contains(MdInline.bold));
    });

    test('outside it, nothing is active', () {
      if (!haveSqlite) return;
      edit('say **hello** th|ere');
      expect(app.marksAtCaret(), isEmpty);
    });

    test('bold+italic lights BOTH buttons', () {
      if (!haveSqlite) return;
      edit('a ***wo|rd*** b');
      final marks = app.marksAtCaret();
      expect(marks, contains(MdInline.bold));
      expect(marks, contains(MdInline.italic));
    });

    test('each mark reports itself', () {
      if (!haveSqlite) return;
      edit('x ==hi|gh== y');
      expect(app.marksAtCaret(), contains(MdInline.highlight));
      edit('x `co|de` y');
      expect(app.marksAtCaret(), contains(MdInline.code));
    });
  });

  group('the list buttons', () {
    test('keep indentation instead of eating it', () {
      if (!haveSqlite) return;
      edit('  indented|');
      app.toggleList(ListKind.bullet);
      expect(c.text, '  - indented');
    });

    test('do not destroy a checkbox', () {
      if (!haveSqlite) return;
      edit('- [x] done|');
      app.toggleList(ListKind.bullet);
      expect(c.text, '- done');
    });

    test('number a new ordered list 1, 2, 3', () {
      if (!haveSqlite) return;
      edit('«a\nb\nc»');
      app.toggleList(ListKind.numbered);
      expect(c.text, '1. a\n2. b\n3. c');
    });
  });

  group('headings do not crash at the start of the block', () {
    test('a caret at offset 0 of text beginning with a newline', () {
      if (!haveSqlite) return;
      edit('|\nsecond line');
      // This threw a RangeError before: the computed line start landed after
      // the line end and `substring` blew up inside the toolbar handler.
      app.toggleLinePrefix('# ');
      expect(c.text.startsWith('# '), isTrue);
    });
  });

  group('blank-out commits its edit', () {
    test('the fill-in-the-blank reaches the block, not just the field', () {
      if (!haveSqlite) return;
      edit('the capital is «Paris» ok');
      expect(app.blankOutSelection(), isTrue);
      expect(c.text, contains('==Paris=='));
      // The bug: it wrote into the controller and never committed, so the
      // block still held the old text and the next rebuild reverted it.
      expect(block.content['text'], contains('==Paris=='));
    });
  });
}
