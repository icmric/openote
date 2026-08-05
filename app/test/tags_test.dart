// Note tags (TEXT-5) — the model and the state operations behind the Home-tab
// picker, the gutter markers and the find-tags rollup.
//
// Two properties matter most. First, an unrecognised tag becomes 'custom'
// rather than vanishing: the whole point of importing OneNote tags is that
// nothing is silently dropped. Second, the `tags` key is REMOVED when empty,
// so an untagged block doesn't carry a dead field into every save and every
// sync op.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/export/md_common.dart';
import 'package:openote/model/tags.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('model', () {
    test('round-trips through JSON', () {
      final t = NoteTag(kind: TagKind.todo, line: 3, checked: true);
      final back = NoteTag.fromJson(t.toJson())!;
      expect(back.kind, TagKind.todo);
      expect(back.line, 3);
      expect(back.checked, isTrue);
    });

    test('an unknown kind becomes custom, never nothing', () {
      final t = NoteTag.fromJson({'kind': 'wingding-42', 'line': 0})!;
      expect(t.kind, TagKind.custom);
      // The label falls back to the kind's, so it still renders as something.
      expect(t.displayLabel, isNotEmpty);
    });

    test('an imported custom tag keeps its own label', () {
      final t = NoteTag.fromJson(
          {'kind': 'custom', 'line': 0, 'label': 'Client follow-up'})!;
      expect(t.displayLabel, 'Client follow-up');
    });

    test('a malformed entry is skipped without costing the block', () {
      final content = <String, dynamic>{
        'tags': [
          {'kind': 'todo', 'line': 0},
          'not a map',
          {'kind': 'todo'}, // no line
        ]
      };
      expect(NoteTag.listFrom(content), hasLength(1));
    });

    test('writing an empty list removes the key entirely', () {
      // A dead `tags: []` on every untagged block would ride along in every
      // save and every op for the life of the notebook.
      final content = <String, dynamic>{'text': 'x', 'tags': []};
      NoteTag.writeInto(content, []);
      expect(content.containsKey('tags'), isFalse);
    });

    test('groups by line for the renderer', () {
      final content = <String, dynamic>{
        'tags': [
          {'kind': 'todo', 'line': 0},
          {'kind': 'important', 'line': 0},
          {'kind': 'question', 'line': 2},
        ]
      };
      final byLine = NoteTag.byLine(content);
      expect(byLine[0], hasLength(2));
      expect(byLine[2], hasLength(1));
      expect(byLine.containsKey(1), isFalse);
    });

    test('custom is not offered in the picker', () {
      // It exists for imports; a user picks a real tag by name.
      expect(TagKind.pickable, isNot(contains(TagKind.custom)));
      expect(TagKind.pickable, contains(TagKind.todo));
    });
  });

  group('applying tags', () {
    Future<(Repository, Directory, AppState, Block)> fixture(String p) async {
      final tmp = Directory.systemTemp.createTempSync(p);
      final repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Tags');
      final app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      app.pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
      final b = Block(
          type: BlockType.text,
          x: 0,
          y: 0,
          content: {'text': 'line one\nline two'});
      app.blocks = [b];
      app.selectedBlockId = b.id;
      return (repo, tmp, app, b);
    }

    test('toggles on and off for the same line and kind', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, b) = await fixture('onote_tag_toggle_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      app.toggleTagOnSelection(TagKind.important);
      expect(NoteTag.listFrom(b.content).single.kind, TagKind.important);
      expect(app.tagsAtCaret(), contains(TagKind.important));

      app.toggleTagOnSelection(TagKind.important);
      expect(NoteTag.listFrom(b.content), isEmpty);
      expect(b.content.containsKey('tags'), isFalse);
    });

    test('a to-do starts unchecked and can be completed', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, b) = await fixture('onote_tag_todo_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      app.toggleTagOnSelection(TagKind.todo);
      expect(NoteTag.listFrom(b.content).single.checked, isFalse);

      app.setTagChecked(b.id, 0, true);
      expect(NoteTag.listFrom(b.content).single.checked, isTrue);
    });

    test('a non-checkable kind carries no checked state', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, b) = await fixture('onote_tag_nocheck_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      app.toggleTagOnSelection(TagKind.question);
      // Null, not false: "not a to-do" and "an unfinished to-do" render
      // differently and must stay distinguishable.
      expect(NoteTag.listFrom(b.content).single.checked, isNull);
    });

    test('different kinds coexist on one line', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, b) = await fixture('onote_tag_multi_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      app.toggleTagOnSelection(TagKind.todo);
      app.toggleTagOnSelection(TagKind.important);
      expect(NoteTag.listFrom(b.content), hasLength(2));
      expect(app.tagsAtCaret(), {TagKind.todo, TagKind.important});
    });

    test('tagging is undoable', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, b) = await fixture('onote_tag_undo_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      app.toggleTagOnSelection(TagKind.critical);
      expect(NoteTag.listFrom(app.blocks.single.content), hasLength(1));
      app.undo();
      expect(NoteTag.listFrom(app.blocks.single.content), isEmpty);
    });
  });

  group('find tags rollup', () {
    test('collects tagged lines with their text and page', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final tmp = Directory.systemTemp.createTempSync('onote_tag_rollup_');
      final repo = await Repository.openAt(tmp);
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final nb = await repo.createNotebook('Rollup');
      final app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
      app.pageId = page.id;
      final b = Block(
          type: BlockType.text,
          x: 0,
          y: 0,
          content: {'text': 'buy milk\nsomething else\nask about the bill'});
      NoteTag.writeInto(b.content, [
        NoteTag(kind: TagKind.todo, line: 0, checked: false),
        NoteTag(kind: TagKind.question, line: 2),
      ]);
      app.blocks = [b];

      final all = app.allTags();
      expect(all, hasLength(2));
      final todo = all.firstWhere((e) => e.tag.kind == TagKind.todo);
      expect(todo.text, 'buy milk');
      expect(todo.pageTitle, page.title);
      final q = all.firstWhere((e) => e.tag.kind == TagKind.question);
      expect(q.text, 'ask about the bill');
    });

    test('a tag pointing past the end of the text degrades to empty', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final tmp = Directory.systemTemp.createTempSync('onote_tag_stale_');
      final repo = await Repository.openAt(tmp);
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final nb = await repo.createNotebook('Stale');
      final app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      app.pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
      final b = Block(
          type: BlockType.text, x: 0, y: 0, content: {'text': 'one line'});
      // Lines were deleted under the tag — it must not throw.
      NoteTag.writeInto(b.content, [NoteTag(kind: TagKind.todo, line: 9)]);
      app.blocks = [b];

      expect(app.allTags().single.text, '');
    });
  });

  group('a rollup line reads as prose, not as source', () {
    // The planner and the find-tags panel both quote a line of a note without
    // running the renderer that understands it, so a to-do written as a bullet
    // showed up as "- Finish tutorial 4" and an emphasised phrase carried its
    // asterisks.
    test('leading block markers come off', () {
      expect(plainLine('- Finish tutorial 4'), 'Finish tutorial 4');
      expect(plainLine('* Finish tutorial 4'), 'Finish tutorial 4');
      expect(plainLine('1. Finish tutorial 4'), 'Finish tutorial 4');
      expect(plainLine('  ## Propositional logic'), 'Propositional logic');
      expect(plainLine('> quoted'), 'quoted');
      expect(plainLine('- [ ] a task'), 'a task');
      expect(plainLine('- [x] a done task'), 'a done task');
    });

    test('paired emphasis comes off, unpaired punctuation does not', () {
      expect(plainLine('**bold** and *italic*'), 'bold and italic');
      expect(plainLine('~~struck~~ and ==marked=='), 'struck and marked');
      expect(plainLine('`code`'), 'code');
      // The reason this is not a Markdown parser: notes are full of maths.
      expect(plainLine('2 * 3 * 4'), '2 * 3 * 4');
      expect(plainLine('a_1 and b_2'), 'a_1 and b_2');
      expect(plainLine('5 - 3'), '5 - 3');
    });

    test('links and colour spans degrade to what they show', () {
      expect(plainLine('see [[Week 1|abc-123]] first'), 'see Week 1 first');
      expect(plainLine('see [[Week 1]]'), 'see Week 1');
      expect(plainLine('{{#FF0000 urgent}}'), 'urgent');
    });

    test('a line that is only a marker survives as empty, not as junk', () {
      expect(plainLine('- '), '');
      expect(plainLine('   '), '');
    });
  });
}
