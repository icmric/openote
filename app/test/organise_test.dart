// Favourites, recents, section sorting (ORG-8/ORG-10) and the page outline
// (TEXT-10) — the state logic behind the navigator and the outline panel.
//
// The property that matters most here is that sorting keeps subpages attached
// to their parent: pages carry a level, the navigator renders hierarchy from
// contiguous runs, so a sort that reorders pages individually silently
// reparents every subpage in the section.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<(Repository, Directory, AppState, String)> fixture(String prefix) async {
    final tmp = Directory.systemTemp.createTempSync(prefix);
    final repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Organise');
    final app = AppState(repo)..notebookId = nb.id;
    app.reloadNodes();
    final section =
        app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
    return (repo, tmp, app, section);
  }

  /// Add a page under [section]; `level > 0` makes it a subpage of whatever
  /// precedes it.
  TreeNode addPage(AppState app, String section, String title, String pos,
      {int level = 0, int? updatedAt}) {
    final n = TreeNode(
        kind: NodeKind.page, parentId: section, title: title, position: pos)
      ..level = level;
    if (updatedAt != null) n.updatedAt = updatedAt;
    final saved = app.importNode(app.notebookId!, n);
    app.reloadNodes();
    return saved;
  }

  group('section sorting (ORG-8)', () {
    test('sorts pages by title and keeps subpages with their parent', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, section) = await fixture('onote_sort_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      // Zebra owns a subpage; Apple comes last in tree order but first A→Z.
      addPage(app, section, 'Zebra', 'a100');
      addPage(app, section, 'Zebra child', 'a200', level: 1);
      addPage(app, section, 'Apple', 'a300');

      app.sortSection(section, byTitle: true);

      final titles = [
        for (final n in app.nodes)
          if (n.kind == NodeKind.page && n.parentId == section) n.title
      ];
      // The starter page created with the notebook sorts in too; assert the
      // relative order of ours and, crucially, the parent/child adjacency.
      final z = titles.indexOf('Zebra');
      expect(titles.indexOf('Apple'), lessThan(z));
      expect(titles[z + 1], 'Zebra child',
          reason: 'a subpage must move with its parent, not sort separately');
    });

    test('sorts by last edited, newest first', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, section) = await fixture('onote_sortdate_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      addPage(app, section, 'Old', 'a100', updatedAt: 1000);
      addPage(app, section, 'New', 'a200', updatedAt: 9000);
      app.sortSection(section, byTitle: false);

      final titles = [
        for (final n in app.nodes)
          if (n.kind == NodeKind.page && n.parentId == section) n.title
      ];
      expect(titles.indexOf('New'), lessThan(titles.indexOf('Old')));
    });

    test('positions stay unique and lexicographically ordered', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, section) = await fixture('onote_sortpos_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      for (final t in ['c', 'a', 'b']) {
        addPage(app, section, t, 'a${t.codeUnitAt(0)}00');
      }
      app.sortSection(section, byTitle: true);

      final positions = [
        for (final n in app.nodes)
          if (n.kind == NodeKind.page && n.parentId == section) n.position
      ];
      expect(positions.toSet().length, positions.length, reason: 'unique');
      final sorted = [...positions]..sort();
      expect(positions, sorted, reason: 'tree order IS position order');
    });
  });

  group('favourites & recents (ORG-10)', () {
    test('favourites toggle and survive by notebook-scoped key', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, section) = await fixture('onote_fav_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final p = addPage(app, section, 'Starred', 'a900');
      expect(app.isFavourite(p.id), isFalse);
      app.toggleFavourite(p.id);
      expect(app.isFavourite(p.id), isTrue);
      expect(app.favouritePages().map((n) => n.id), contains(p.id));
      app.toggleFavourite(p.id);
      expect(app.isFavourite(p.id), isFalse);
    });

    test('recents record most-recent-first and de-duplicate', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, section) = await fixture('onote_recent_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final a = addPage(app, section, 'A', 'a100');
      final b = addPage(app, section, 'B', 'a200');
      await app.selectPage(a.id);
      await app.selectPage(b.id);
      await app.selectPage(a.id); // revisit

      final recent = app.recentPages().map((n) => n.id).toList();
      expect(recent.first, a.id, reason: 'most recent first');
      expect(recent.where((id) => id == a.id).length, 1,
          reason: 'a revisit moves the entry, it does not duplicate it');
      expect(recent, contains(b.id));
    });
  });

  group('page outline (TEXT-10)', () {
    test('lists headings in reading order with their levels', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, section) = await fixture('onote_toc_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final page = addPage(app, section, 'Outlined', 'a100');
      await app.selectPage(page.id);
      // Deliberately added out of vertical order: reading order is y, not
      // insertion order.
      app.blocks = [
        Block(
            type: BlockType.text,
            x: 0,
            y: 200,
            content: {'text': '## Second\nbody'}),
        Block(
            type: BlockType.text,
            x: 0,
            y: 10,
            content: {'text': '# First\nnot a heading\n### Third'}),
      ];
      app.docRevision++;

      final items = app.pageOutline();
      expect(items.map((i) => i.text).toList(), ['First', 'Third', 'Second']);
      expect(items.map((i) => i.level).toList(), [1, 3, 2]);
    });

    test('a page with no headings yields an empty outline', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, section) = await fixture('onote_toc_empty_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final page = addPage(app, section, 'Plain', 'a100');
      await app.selectPage(page.id);
      app.blocks = [
        Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'just prose'})
      ];
      app.docRevision++;
      expect(app.pageOutline(), isEmpty);
    });
  });
}
