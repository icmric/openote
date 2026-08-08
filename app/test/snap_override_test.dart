// Holding a modifier mid-drag flips one block out of the grid, and back.
//
// The ask: "if im in grid mode, holding down ctrl while moving puts that one
// in free form and leaves the rest in their grid pattern, but as soon as i
// release it it goes back to grid, and vice versa."
//
// Two properties matter and neither is about the key itself. It has to be read
// PER MOVE, so pressing or releasing part way through a drag takes effect
// there and then rather than at the moment the drag began. And it has to apply
// to the block being dragged and nothing else — "leaves the rest in their grid
// pattern" is the whole point of doing this per drag instead of toggling the
// mode.
//
// `snapOverride` is a plain flag rather than a keyboard read inside AppState:
// the state layer has no business knowing about hardware, and a settable flag
// is what lets these run without simulating key events. The canvas sets it
// from the real keyboard (block_view._modeOverrideHeld).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Repository repo;
  late Directory tmp;
  late AppState app;
  late Block dragged, other;

  setUp(() async {
    if (!haveSqlite) return;
    tmp = Directory.systemTemp.createTempSync('onote_snap_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Snap');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    final section = app.importNode(
        nb.id, TreeNode(kind: NodeKind.section, title: 'S', position: 'a0'));
    final page = app.importNode(
        nb.id,
        TreeNode(
            kind: NodeKind.page,
            parentId: section.id,
            title: 'P',
            position: 'a1'));
    app.reloadNodes();
    await app.selectPage(page.id);
    // Well clear of the left margin, which has its own tuck-to-margin rule.
    dragged = Block(type: BlockType.image, x: 300, y: 300, w: 100, h: 100);
    other = Block(type: BlockType.image, x: 600, y: 600, w: 100, h: 100);
    app.blocks = [dragged, other];
  });

  tearDown(() {
    if (!haveSqlite) return;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Land [b] on a deliberately off-grid position and settle it, the way a
  /// drag ends.
  void dropAt(Block b, double x, double y) {
    app.select(b.id);
    b
      ..x = x
      ..y = y;
    app.settleSelected();
  }

  test('the grid is on by default', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    expect(app.snapToGrid, isTrue);
    expect(app.effectiveSnap, isTrue);
  });

  group('in grid mode', () {
    test('a normal drop lands on the grid', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      dropAt(dragged, 307, 411);
      expect(dragged.x % app.gridSize, 0);
      expect(dragged.y % app.gridSize, 0);
      expect(dragged.placement, 'snapped');
    });

    test('holding the modifier drops it exactly where it was let go', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.snapOverride = true;
      expect(app.effectiveSnap, isFalse);
      dropAt(dragged, 307, 411);
      expect(dragged.x, 307, reason: 'not rounded to the grid');
      expect(dragged.y, 411);
      expect(dragged.placement, 'free');
    });

    test('and leaves every other block in the grid', () {
      // "leaves the rest in their grid pattern" — the reason this is a
      // per-drag override and not a mode toggle.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.snapOverride = true;
      dropAt(dragged, 307, 411);
      app.snapOverride = false;
      dropAt(other, 613, 717);

      expect(dragged.placement, 'free');
      expect(dragged.x, 307);
      expect(other.placement, 'snapped');
      expect(other.x % app.gridSize, 0);
      expect(app.snapToGrid, isTrue, reason: 'the MODE never changed');
    });
  });

  group('with the grid off', () {
    setUp(() => app.snapToGrid = false);

    test('a normal drop is free', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      dropAt(dragged, 307, 411);
      expect(dragged.x, 307);
      expect(dragged.placement, 'free');
    });

    test('holding the modifier snaps that one to the grid — "and vice versa"',
        () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.snapOverride = true;
      expect(app.effectiveSnap, isTrue);
      dropAt(dragged, 307, 411);
      expect(dragged.x % app.gridSize, 0);
      expect(dragged.y % app.gridSize, 0);
      expect(dragged.placement, 'snapped');
      expect(app.snapToGrid, isFalse, reason: 'the MODE never changed');
    });
  });

  test('releasing the key before the mouse settles into the grid', () {
    // The reading of "as soon as i release it it goes back to grid" that lets
    // you change your mind without starting the drag over: the mode in force
    // at the moment of RELEASE is the one that decides where it lands.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.snapOverride = true; // held for most of the drag…
    app.select(dragged.id);
    dragged
      ..x = 307
      ..y = 411;
    app.snapOverride = false; // …and let go just before the drop
    app.settleSelected();
    expect(dragged.x % app.gridSize, 0);
    expect(dragged.placement, 'snapped');
  });

  test('creating a block ignores the override', () {
    // A modifier held while typing must not change where a NEW box lands:
    // this is a drag-time override, and creation is not a drag.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    app.snapOverride = true;
    final made = app.addBlock(Block(type: BlockType.image, x: 307, y: 411));
    expect(made.placement, 'snapped');
  });
}
