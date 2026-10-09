// "Duplicate" on a page, which is what replaces page templates.
//
// The owner, on the templates it supersedes: *"at the moment they really
// arent that helpful at all, i havent personally used them beyond basic
// testing, and i think in their current format they arent actually useful to
// really anyone."* A layout you want again is a page you keep — and a copy
// needs no picker, no preview and no new noun, because you are looking at the
// thing you are about to copy.
//
// Most of what is checked here is what must NOT be shared with the original:
// a block id, a review schedule, a passcode. Those are the ways a copy stops
// being a copy and becomes a second claim on the same thing.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/state/page_protection.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/sidebar.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;
  late String nb;
  late String sectionId;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_duppage_');
    repo = await Repository.openAt(tmp);
    final ref = await repo.createNotebook('T');
    nb = ref.id;
    app = AppState(repo)
      ..notebookId = nb
      ..spellCheckEnabled = false;
    app.reloadNodes();
    sectionId = app.nodes.firstWhere((n) => n.kind == NodeKind.section).id;
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

  /// A page called [title] holding [blocks], filed in the one section.
  TreeNode page(String title, List<Block> blocks,
      {int level = 0, String position = 'b0'}) {
    final n = app.importNode(
        nb,
        TreeNode(
            kind: NodeKind.page,
            parentId: sectionId,
            title: title,
            level: level,
            position: position));
    app.importPage(nb, n.id, blocks, PageProps(background: 'grid'));
    app.reloadNodes();
    return n;
  }

  Block text(String t, {double y = 100}) =>
      Block(type: BlockType.text, x: 60, y: y, w: 400, content: {'text': t});

  testWidgets('the copy is a copy: same content, new ids, filed beneath',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final src = page(
        'Osmosis', [text('Water moves.'), text('Down a gradient.', y: 300)]);
    await app.selectPage(src.id);

    final copyId = await app.duplicatePage(src.id);
    expect(copyId, isNotNull);

    final copy = app.node(copyId!)!;
    expect(copy.title, 'Osmosis copy');
    expect(copy.parentId, sectionId, reason: 'same section');
    expect(copy.level, src.level, reason: 'same indent');

    // Relative, because `createNotebook` seeds a page of its own: what
    // matters is that the copy follows its source, not its absolute index.
    final order = app.pagesOf(sectionId).map((p) => p.id).toList();
    expect(order.indexOf(copy.id), order.indexOf(src.id) + 1,
        reason: 'directly beneath the page it came from');

    final before = repo.readPage(nb, src.id);
    final after = repo.readPage(nb, copyId);
    expect(after.blocks.map((b) => b.content['text']).toList(),
        before.blocks.map((b) => b.content['text']).toList(),
        reason: 'every word came across');
    expect(after.props.background, 'grid',
        reason: 'and the shape of the page with it');

    // **The one thing that must NOT be shared.** A block id is the handle a
    // reminder and a flashcard's review history hold a block by, so a reused
    // id would have two pages laying claim to one schedule.
    final ids = {...before.blocks.map((b) => b.id)};
    expect(after.blocks.any((b) => ids.contains(b.id)), isFalse,
        reason: 'no copied block may answer for the original');
    expect(after.blocks.map((b) => b.id).toSet(), hasLength(2),
        reason: 'and the new ids are distinct from each other');

    // The copy opens, with its title ready to be typed over.
    expect(app.pageId, copyId);
    expect(app.pendingTitleEdit, copyId);
    app.cancelPendingSave();
  });

  testWidgets('a picture is shared, not stored twice', (t) async {
    // A blob reference travels as `{hash, mime, size}` and the bytes are
    // content-addressed, so the right copy of an image block is the same hash
    // — not a second set of bytes on disk for the same picture.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final bytes = Uint8List.fromList(List<int>.generate(64, (i) => i));
    final hash = app.importBlob(nb, bytes, 'image/png');
    final src = page('Diagram', [
      Block(type: BlockType.image, x: 60, y: 100, w: 200, h: 120, content: {
        'hash': hash,
        'mime': 'image/png',
        'size': bytes.length,
      })
    ]);
    await app.selectPage(src.id);

    final copyId = (await app.duplicatePage(src.id))!;
    final img = repo.readPage(nb, copyId).blocks.single;
    expect(img.content['hash'], hash, reason: 'the same bytes, referenced');
    expect(img.content['size'], bytes.length);
    expect(repo.getBlob(nb, hash), isNotNull,
        reason: 'and those bytes are still there to be read');
    app.cancelPendingSave();
  });

  testWidgets('what is on the screen is what gets copied', (t) async {
    // The source is almost always the open page, and its last keystroke may
    // still be sat on the save debounce. Copying the version on disk would
    // quietly lose whatever was typed in the last second.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final src = page('Notes', [text('first')]);
    await app.selectPage(src.id);
    app.blocks.single.content['text'] = 'first, and then some more';
    app.updateBlock(app.blocks.single);

    final copyId = (await app.duplicatePage(src.id))!;
    expect(repo.readPage(nb, copyId).blocks.single.content['text'],
        'first, and then some more');
    app.cancelPendingSave();
  });

  testWidgets('sub-pages stay with the original, and the copy has none',
      (t) async {
    // One page, not a subtree. The copy must land after the WHOLE subtree, or
    // it would come between a page and its children.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final src = page('Chapter 1', [text('body')], position: 'b0');
    page('Part A', [text('a')], level: 1, position: 'b1');
    page('Part B', [text('b')], level: 1, position: 'b2');
    page('Chapter 2', [text('two')], position: 'b3');
    await app.selectPage(src.id);

    final was = app.pagesOf(sectionId).length;
    final copyId = (await app.duplicatePage(src.id))!;
    final titles = app.pagesOf(sectionId).map((p) => p.title).toList();
    expect(titles.sublist(titles.indexOf('Chapter 1')),
        ['Chapter 1', 'Part A', 'Part B', 'Chapter 1 copy', 'Chapter 2'],
        reason: 'after the subtree, and before the next chapter');
    expect(app.node(copyId)!.level, 0);
    // A sub-page is a sibling at a deeper level, not a child, so "no
    // sub-pages" is "exactly one page was added".
    expect(app.pagesOf(sectionId), hasLength(was + 1),
        reason: 'one page copied, not a subtree');
    app.cancelPendingSave();
  });

  testWidgets('A LOCKED PAGE DOES NOT LAUNDER INTO AN UNLOCKED COPY',
      (t) async {
    // The hole this closes: a passcode is stored against a node id, so a copy
    // with a new id carries none of it — duplicate the page and read it with
    // no passcode at all. A lock on the SECTION is inherited for free, because
    // locks resolve by walking up from the page, but one on the page itself
    // has to be brought along.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final src = page('Diary', [text('private')]);
    await app.selectPage(src.id);
    app.protectNode(src.id, '1234', UnlockPolicy.always);
    expect(app.protectionFor(src.id), isNotNull, reason: 'precondition');

    final copyId = (await app.duplicatePage(src.id))!;
    final lock = app.protectionFor(copyId);
    expect(lock, isNotNull, reason: 'the copy is locked too');
    expect(lock!.matches('1234'), isTrue,
        reason: 'by the same passcode as the page it came from');
    expect(lock.matches('4321'), isFalse);
    app.cancelPendingSave();
  });

  testWidgets('and it is offered on a page, but not on a section group',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final p = page('Osmosis', [text('x')]);
    app.importNode(
        nb,
        TreeNode(
            kind: NodeKind.sectionGroup, title: 'Year 12', position: 'd0'));
    app.reloadNodes();
    await app.selectPage(p.id);

    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: app,
          builder: (_, __) => Sidebar(app: app),
        ),
      ),
    ));
    await t.pumpAndSettle();

    Future<void> menuOn(String label) async {
      await t.tapAt(t.getCenter(find.text(label)), buttons: kSecondaryButton);
      await t.pumpAndSettle();
    }

    Future<void> dismiss() async {
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      app.cancelPendingSave();
    }

    await menuOn('Osmosis');
    expect(find.text('Duplicate'), findsOneWidget);
    // Beside Rename and above the move actions: these two are the things you
    // do to the page itself.
    expect(t.getCenter(find.text('Duplicate')).dy,
        greaterThan(t.getCenter(find.text('Rename')).dy));
    expect(t.getCenter(find.text('Duplicate')).dy,
        lessThan(t.getCenter(find.text('Move up')).dy));
    await dismiss();

    await menuOn('Year 12');
    expect(find.text('Rename'), findsOneWidget,
        reason: 'precondition: this is the node menu');
    expect(find.text('Duplicate'), findsNothing,
        reason: 'copying a section group would mean copying every page in it');
    await dismiss();
  });
}
