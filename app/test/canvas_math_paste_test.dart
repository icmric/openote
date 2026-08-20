// Canvas paste parity for maths (v0.20 plan, D.3 and D.4).
//
// Two defects pinned here, both of which put raw LaTeX source in front of a
// student — the one thing the equation editor exists to prevent:
//
// * D.3 — pasting `$\frac{1}{2}$` onto the canvas made a TEXT block showing
//   the source, not an equation. `insertPastedText` now routes anything
//   `MathClipboard.looksLikeMaths` accepts into a maths block.
//
// * D.4 — cutting a block and pressing Ctrl+V resurrected whatever older
//   text the SYSTEM clipboard held (an equation's own Ctrl+C leaves `$…$`
//   there), instead of the block just cut. `blockClipboardIsNewer` compares
//   the system text at paste time with a snapshot taken at copy time: the
//   same text means nothing arrived since, so the blocks are the newer of
//   the two and win — while text copied AFTER the cut still pastes as text.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/media_drop.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  Future<AppState> fixture() async {
    final tmp = Directory.systemTemp.createTempSync('onote_mathpaste_');
    final repo = await Repository.openAt(tmp);
    late AppState created;
    addTearDown(() async {
      created.cancelPendingSave();
      await created.settleBackgroundWork();
      await repo.flushWorkspace();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final nb = await repo.createNotebook('MathPaste');
    final app = created = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    // The real clipboard does not exist under the test harness, and the
    // copy-time snapshot must not try to read it.
    app.readSystemClipboardText = () async => null;
    app.reloadNodes();
    await app.selectPage(
        app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
    await app.settleBackgroundWork();
    return app;
  }

  test('pasting maths onto the canvas makes an equation, not LaTeX text',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await fixture();

    final b = insertPastedText(app, r'$\frac{1}{2}$', const Offset(120, 80));

    expect(b.type, BlockType.math,
        reason: r'pasting $\frac{1}{2}$ used to land as a TEXT block showing '
            'raw LaTeX source — the one thing the equation editor exists '
            'to keep off the page');
    expect(b.content['latex'], r'\frac{1}{2}',
        reason: 'the dollars are delimiters, not content: stored latex must '
            'be exactly what typing it into the equation editor stores');
    expect(b.content['display'], isTrue);
    expect(app.selectedIds, contains(b.id),
        reason: 'a paste that lands something you then have to hunt for is '
            'barely better than no paste');
  });

  test('pasting ordinary words still makes a text block', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await fixture();

    final b = insertPastedText(app, 'notes from the lecture',
        const Offset(40, 40));

    expect(b.type, BlockType.text,
        reason: 'the maths detour must never widen: plain prose pasted onto '
            'the canvas is a note, and turning it into an equation would be '
            'a worse bug than the one D.3 fixed');
    expect(b.content['text'], 'notes from the lecture');
  });

  test('a sentence with prices in it stays prose', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await fixture();

    final b = insertPastedText(
        app, r'coffee is $5 and lunch is $10 today', const Offset(40, 40));

    expect(b.type, BlockType.text,
        reason: 'a false positive turns someone\'s prose into an equation, '
            'which is worse than a false negative leaving them to press '
            'the button — the narrowness rule looksLikeMaths lives by');
  });

  test('cut a block, Ctrl+V brings THAT block back, not older system text',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await fixture();

    // The equation's own Ctrl+C left its source on the system clipboard
    // BEFORE the block was cut — the exact state that used to resurrect a
    // text block full of LaTeX instead of the cut block.
    const stale = r'$\frac{1}{2}$';
    app.readSystemClipboardText = () async => stale;

    final eq = app.insertEquation(at: const Offset(200, 150));
    eq.content['latex'] = r'\frac{1}{2}';
    app.updateBlock(eq);
    app.select(eq.id);
    app.cutSelectedBlocks();
    expect(app.blocks.where((b) => b.id == eq.id), isEmpty,
        reason: 'a cut block leaves the page — that half always worked');

    expect(await app.blockClipboardIsNewer(stale), isTrue,
        reason: 'the system still holds the very text it held when the '
            'block was cut, so nothing was copied since — pasting must '
            'restore the block just cut, not resurrect its old source');

    app.pasteBlocks();
    final restored =
        app.blocks.where((b) => b.type == BlockType.math).toList();
    expect(restored, hasLength(1));
    expect(restored.single.content['latex'], r'\frac{1}{2}',
        reason: 'the paste is the block that was cut, equation and all');
  });

  test('text copied AFTER the cut still wins the paste', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await fixture();

    app.readSystemClipboardText = () async => 'old clipboard text';
    final eq = app.insertEquation(at: const Offset(200, 150));
    app.select(eq.id);
    app.cutSelectedBlocks();

    expect(await app.blockClipboardIsNewer('pasted from a website'), isFalse,
        reason: 'text that differs from the copy-time snapshot arrived '
            'after the cut, and what was copied most recently is what a '
            'paste means — the same rule that keeps a fresh screenshot '
            'beating a stale block copy');
  });

  test('nothing copied means the block clipboard never claims the paste',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await fixture();

    expect(await app.blockClipboardIsNewer('any text'), isFalse,
        reason: 'with no blocks ever copied there is nothing to prefer, '
            'and claiming the paste would make Ctrl+V do nothing at all');
  });
}
