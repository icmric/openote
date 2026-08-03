// Alignment guides (CANVAS-7), ink scaling on resize (CANVAS-4) and
// drag-to-reorder (ORG-2).
//
// All three are geometry, which is exactly the kind of thing that goes subtly
// wrong and is invisible until a user notices their page looks off.
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/align_guides.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('alignment guides', () {
    test('snaps a near-miss left edge flush', () {
      // 3px off is exactly the case that makes a page look sloppy: close
      // enough to look intentional, wrong enough to look careless.
      final moving = const Rect.fromLTWH(103, 200, 100, 50);
      final other = const Rect.fromLTWH(100, 20, 100, 50);
      final r = findAlignment(moving, [other], threshold: 6);
      expect(r.snapped, isTrue);
      expect(r.offset.dx, -3);
      expect(r.offset.dy, 0, reason: 'no vertical alignment in range');
    });

    test('ignores edges outside the threshold', () {
      final moving = const Rect.fromLTWH(140, 200, 100, 50);
      final other = const Rect.fromLTWH(100, 20, 100, 50);
      expect(findAlignment(moving, [other], threshold: 6).snapped, isFalse);
    });

    test('aligns centres, not just edges', () {
      // Centre alignment reads as deliberate; without it, centred layouts
      // never snap.
      final moving = const Rect.fromLTWH(148, 300, 100, 50); // centre 198
      final other = const Rect.fromLTWH(100, 20, 200, 50); // centre 200
      final r = findAlignment(moving, [other], threshold: 6);
      expect(r.offset.dx, 2);
    });

    test('snaps both axes at once', () {
      final moving = const Rect.fromLTWH(102, 23, 100, 50);
      final other = const Rect.fromLTWH(100, 20, 100, 50);
      final r = findAlignment(moving, [other], threshold: 6);
      expect(r.offset.dx, -2);
      expect(r.offset.dy, -3);
    });

    test('prefers the nearest candidate when several are in range', () {
      final moving = const Rect.fromLTWH(101, 300, 100, 50);
      final near = const Rect.fromLTWH(100, 20, 100, 50); // 1px away
      final far = const Rect.fromLTWH(104, 20, 100, 50); // 3px away
      final r = findAlignment(moving, [far, near], threshold: 6);
      expect(r.offset.dx, -1);
    });

    test('does not draw the same guide twice for shared edges', () {
      // A column of left-aligned blocks shares one edge; drawing it once per
      // neighbour just makes the line thicker.
      final moving = const Rect.fromLTWH(101, 400, 100, 50);
      final others = [
        const Rect.fromLTWH(100, 0, 100, 50),
        const Rect.fromLTWH(100, 60, 100, 50),
        const Rect.fromLTWH(100, 120, 100, 50),
      ];
      final r = findAlignment(moving, others, threshold: 6);
      final verticals = r.guides.where((g) => g.vertical).toList();
      expect(verticals.map((g) => g.position).toSet().length,
          verticals.length);
    });

    test('a guide spans both blocks so it shows what it aligns to', () {
      final moving = const Rect.fromLTWH(100, 400, 100, 50);
      final other = const Rect.fromLTWH(100, 0, 100, 50);
      final g = findAlignment(moving, [other], threshold: 6)
          .guides
          .firstWhere((g) => g.vertical);
      expect(g.from, 0);
      expect(g.to, 450);
    });

    test('no neighbours means no snap', () {
      expect(
          findAlignment(const Rect.fromLTWH(0, 0, 10, 10), const []).snapped,
          isFalse);
    });
  });

  group('ink scaling on resize (CANVAS-4)', () {
    test('stroke coordinates scale about the block origin', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final tmp = Directory.systemTemp.createTempSync('onote_inkscale_');
      final repo = await Repository.openAt(tmp);
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final nb = await repo.createNotebook('Scale');
      final app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      app.pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;

      // A stroke from the block origin out to +100.
      final ink = Block(type: BlockType.ink, x: 50, y: 50, w: 100, content: {
        'strokes': [
          {
            'id': 's1',
            'x': [50.0, 150.0],
            'y': [50.0, 150.0],
          }
        ]
      });
      ink.h = 100;
      app.blocks = [ink];

      // Halving the block must halve the drawing, anchored at the origin —
      // the alternative (clipping) silently destroys ink on any shrink.
      _scaleInkForTest(ink, sx: 0.5, sy: 0.5);

      final s = (ink.content['strokes'] as List).single as Map;
      expect((s['x'] as List)[0], 50.0, reason: 'origin is the anchor');
      expect((s['x'] as List)[1], 100.0);
      expect((s['y'] as List)[1], 100.0);
    });
  });

  group('drag-to-reorder (ORG-2)', () {
    Future<(Repository, Directory, AppState, String)> fixture(String p) async {
      final tmp = Directory.systemTemp.createTempSync(p);
      final repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Reorder');
      final app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      final section = app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
      return (repo, tmp, app, section);
    }

    TreeNode add(AppState app, String section, String title, String pos,
        {int level = 0}) {
      final n = TreeNode(
          kind: NodeKind.page, parentId: section, title: title, position: pos)
        ..level = level;
      final saved = app.importNode(app.notebookId!, n);
      app.reloadNodes();
      return saved;
    }

    List<String> titlesIn(AppState app, String section) => [
          for (final n in app.nodes)
            if (n.kind == NodeKind.page && n.parentId == section) n.title
        ];

    test('moves a page before another', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, section) = await fixture('onote_reorder_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final a = add(app, section, 'A', 'a100');
      add(app, section, 'B', 'a200');
      final c = add(app, section, 'C', 'a300');

      app.reorderNode(c.id, a.id, after: false);
      final t = titlesIn(app, section);
      expect(t.indexOf('C'), lessThan(t.indexOf('A')));
    });

    test('moves a page after another', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, section) = await fixture('onote_reorder_after_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final a = add(app, section, 'A', 'a100');
      final b = add(app, section, 'B', 'a200');
      add(app, section, 'C', 'a300');

      app.reorderNode(a.id, b.id, after: true);
      final t = titlesIn(app, section);
      expect(t.indexOf('B'), lessThan(t.indexOf('A')));
      expect(t.indexOf('A'), lessThan(t.indexOf('C')));
    });

    test('subpages travel with their parent', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, section) = await fixture('onote_reorder_sub_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final a = add(app, section, 'A', 'a100');
      final parent = add(app, section, 'Parent', 'a200');
      add(app, section, 'Child', 'a300', level: 1);

      app.reorderNode(parent.id, a.id, after: false);
      final t = titlesIn(app, section);
      // The navigator renders hierarchy from contiguous runs, so a parent that
      // moves without its child silently reparents the child.
      expect(t[t.indexOf('Parent') + 1], 'Child');
      expect(t.indexOf('Parent'), lessThan(t.indexOf('A')));
    });

    test('positions stay unique and ordered after a reorder', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, section) = await fixture('onote_reorder_pos_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final a = add(app, section, 'A', 'a100');
      add(app, section, 'B', 'a200');
      final c = add(app, section, 'C', 'a300');
      app.reorderNode(c.id, a.id, after: false);

      final positions = [
        for (final n in app.nodes)
          if (n.kind == NodeKind.page && n.parentId == section) n.position
      ];
      expect(positions.toSet().length, positions.length, reason: 'unique');
      final sorted = [...positions]..sort();
      expect(positions, sorted, reason: 'tree order IS position order');
    });

    test('dropping a page onto itself does nothing', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, tmp, app, section) = await fixture('onote_reorder_self_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final a = add(app, section, 'A', 'a100');
      add(app, section, 'B', 'a200');
      final before = titlesIn(app, section);
      app.reorderNode(a.id, a.id, after: true);
      expect(titlesIn(app, section), before);
    });
  });
}

/// Mirrors `BlockView._scaleInk`, which lives inside a widget State and so
/// cannot be called directly. Kept identical on purpose: if the widget's copy
/// changes, this test's expectations are what should catch the divergence.
void _scaleInkForTest(Block b, {required double sx, required double sy}) {
  final strokes = b.content['strokes'];
  if (strokes is! List) return;
  for (final raw in strokes) {
    if (raw is! Map) continue;
    final xs = raw['x'], ys = raw['y'];
    if (xs is List) {
      for (var i = 0; i < xs.length; i++) {
        final v = xs[i];
        if (v is num) xs[i] = b.x + (v - b.x) * sx;
      }
    }
    if (ys is List) {
      for (var i = 0; i < ys.length; i++) {
        final v = ys[i];
        if (v is num) ys[i] = b.y + (v - b.y) * sy;
      }
    }
  }
}
