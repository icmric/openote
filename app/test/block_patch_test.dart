// `block.patch` — record the characters that changed, not the whole block.
//
// **The measurement that justifies it.** `block.set` carries the ENTIRE block,
// and an autosave fires 700 ms after you stop typing — so one character added
// to a 2,000-character paragraph cost ~2.5 KB of permanent, replicated log,
// and paid it again at the next pause in the sentence. On the author's own
// workspace, text `block.set` was **52.6% of the whole log** (913 KB of 1.69
// MB, over 1,042 saves). `test/oplog_composition_test.dart` prints that
// number; do not take it on faith, re-run it.
//
// Ink already had this treatment for the same reason. Text never did.
//
// ## The three things that make it safe rather than merely smaller
//
//  1. **A base fingerprint.** Logs from two devices merge as the union in a
//     total order, so a patch really can arrive to be applied on top of some
//     other device's `block.set`. Applied blind that is silent corruption of
//     somebody's prose. The op carries a fingerprint of the string it was
//     computed against and a reader that does not match it drops the patch —
//     which lands exactly on the last-writer-wins resolution this collision
//     has always had.
//  2. **Whole-character boundaries.** Dart strings are UTF-16, and the obvious
//     common-prefix loop will happily cut an emoji in half, leaving an
//     unpaired surrogate that is not a character at all.
//  3. **It falls back.** A patch that is not smaller than the block it
//     replaces is not worth an envelope bump, and a change it cannot express
//     exactly must not be expressed approximately.
//
// ## The cost, stated plainly
//
// A patch is written at `v: 2`, so **the first one written into a notebook
// makes that notebook read-only on every Openote older than 1.0.** That is
// deliberate and it is why this was spent now: the machinery to do the safe
// thing has shipped since v0.17, and the oldest build in the world is days
// old. It gets more expensive every week.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/materializer.dart';
import 'package:openote/sync/op.dart';
import 'package:openote/sync/op_log.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('the splice', () {
    void roundTrips(String before, String after) {
      final s = spliceBetween(before, after);
      expect(s, isNotNull, reason: '"$before" → "$after"');
      final applied = applyTextPatch(before, {
        'base': textFingerprint(before),
        'at': s!.at,
        'del': s.del,
        'ins': s.ins,
      });
      expect(applied, after, reason: 'the splice must reproduce it exactly');
    }

    test('a character typed into the middle', () {
      final s = spliceBetween('the cat sat', 'the cart sat')!;
      expect(s.at, 6);
      expect(s.del, 0);
      expect(s.ins, 'r');
      roundTrips('the cat sat', 'the cart sat');
    });

    test('a character deleted', () {
      final s = spliceBetween('the cart sat', 'the cat sat')!;
      expect(s.del, 1);
      expect(s.ins, isEmpty);
      roundTrips('the cart sat', 'the cat sat');
    });

    test('a selection typed over', () {
      roundTrips('the cat sat on the mat', 'the dog sat on the mat');
    });

    test('appended at the end, which is most of writing', () {
      final s = spliceBetween('Once upon a', 'Once upon a time')!;
      expect(s.at, 11);
      expect(s.del, 0);
      expect(s.ins, ' time');
    });

    test('everything removed', () => roundTrips('all of it', ''));
    test('from nothing', () => roundTrips('', 'first words'));

    test('two strings that are the same produce no splice', () {
      expect(spliceBetween('same', 'same'), isNull);
    });

    test('an emoji is never cut in half', () {
      // 😀 is a surrogate PAIR: two UTF-16 code units. A prefix loop that
      // stops between them leaves half a character on each side, and neither
      // half is a character — it is an unpaired surrogate, which is not even
      // valid text. Both ends have to snap back to a whole one.
      const before = 'hi 😀 there';
      const after = 'hi 😀😀 there';
      final s = spliceBetween(before, after)!;
      roundTrips(before, after);
      // Whatever it chose, both cut points sit on whole characters.
      for (final i in [s.at, s.at + s.del]) {
        expect(i, inInclusiveRange(0, before.length));
        if (i > 0 && i < before.length) {
          final u = before.codeUnitAt(i);
          expect(u >= 0xDC00 && u <= 0xDFFF, isFalse,
              reason: 'cut at $i lands on the low half of a pair');
        }
      }
      expect(applyTextPatch(before, {
        'base': textFingerprint(before),
        'at': s.at,
        'del': s.del,
        'ins': s.ins,
      })!.runes.length, after.runes.length);
    });

    test('and neither is a character deleted next to one', () {
      roundTrips('a😀b😀c', 'a😀😀c');
      roundTrips('😀', '');
      roundTrips('x😀y', 'xy');
    });
  });

  group('the guard that makes merging safe', () {
    test('a patch against the text it was computed from applies', () {
      final s = spliceBetween('hello', 'hello world')!;
      expect(
          applyTextPatch('hello', {
            'base': textFingerprint('hello'),
            'at': s.at,
            'del': s.del,
            'ins': s.ins
          }),
          'hello world');
    });

    test('a patch against DIFFERENT text is refused, not applied', () {
      // The one that matters. Device A patches "hello"→"hello world"; device B
      // set the same block to "goodbye" and its op sorts in between. Applying
      // the splice anyway would produce mangled prose that neither person
      // wrote. Refusing leaves B's text, which is the last-writer-wins answer
      // this collision has always had.
      final s = spliceBetween('hello', 'hello world')!;
      expect(
          applyTextPatch('goodbye', {
            'base': textFingerprint('hello'),
            'at': s.at,
            'del': s.del,
            'ins': s.ins
          }),
          isNull);
    });

    test('a range that does not fit the string is refused', () {
      expect(
          applyTextPatch('short', {
            'base': textFingerprint('short'),
            'at': 3,
            'del': 99,
            'ins': 'x'
          }),
          isNull);
    });

    test('a malformed payload is refused rather than guessed at', () {
      for (final d in <Map<String, dynamic>>[
        {'base': textFingerprint('abc'), 'at': 1, 'del': 1},
        {'base': textFingerprint('abc'), 'at': -1, 'del': 0, 'ins': 'x'},
        {'at': 1, 'del': 0, 'ins': 'x'},
      ]) {
        expect(applyTextPatch('abc', d), isNull, reason: '$d');
      }
    });
  });

  group('through the recorder, on a real notebook', () {
    Future<(Repository, AppState, Directory, String)> notebook(
        String prefix) async {
      final tmp = Directory.systemTemp.createTempSync(prefix);
      final repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Patch');
      final app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      final pageId = app.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
      app.pageId = pageId;
      return (repo, app, tmp, nb.id);
    }

    List<Op> newOps(Repository repo, String nbId, int from) {
      final ref = repo.notebooks.firstWhere((n) => n.id == nbId);
      return OpLogStore.forNotebook(ref.file).readAll().skip(from).toList();
    }

    int opCount(Repository repo, String nbId) {
      final ref = repo.notebooks.firstWhere((n) => n.id == nbId);
      return OpLogStore.forNotebook(ref.file).readAll().length;
    }

    /// The page as the log alone says it is.
    Map<String, dynamic> rebuilt(Repository repo, String nbId, String pageId) {
      final ref = repo.notebooks.firstWhere((n) => n.id == nbId);
      final m = Materializer()
        ..applyAll(OpLogStore.forNotebook(ref.file).readAll());
      expect(m.unsupported, isEmpty,
          reason: 'this build writes only envelopes it can read back');
      return m.pageMirror(pageId);
    }

    test('a paragraph edited is a patch, and a small one', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, tmp, nbId) = await notebook('onote_patch_small_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      // A real paragraph, the size the measurement was taken at.
      final prose = List.filled(40, 'the quick brown fox jumps over it. ').join();
      final b = Block(
          type: BlockType.text, x: 0, y: 0, w: 400, content: {'text': prose});
      app.blocks = [b];
      app.markDirty();
      await app.flushSave();
      final afterFirst = opCount(repo, nbId);

      // One character, at the end, the way typing actually arrives.
      b.content['text'] = '$prose!';
      b.updatedAt = nowMs() + 1;
      app.markDirty();
      await app.flushSave();

      final added = newOps(repo, nbId, afterFirst);
      expect(added, hasLength(1));
      final op = added.single;
      expect(op.kind, OpKind.blockPatch);
      expect(op.version, opPatchVersion,
          reason: 'an older build must go read-only rather than skip it');
      expect(op.map['ins'], '!');
      expect(op.map['del'], 0);

      // The point of the exercise, measured rather than asserted in prose.
      expect(op.encode().length, lessThan(prose.length ~/ 4),
          reason: 'a one-character edit used to cost the whole paragraph');
    });

    test('and the log still rebuilds the page exactly', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, tmp, nbId) = await notebook('onote_patch_rebuild_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final pageId = app.pageId!;

      final b = Block(
          type: BlockType.text,
          x: 0,
          y: 0,
          w: 400,
          content: {'text': 'Once upon a'});
      app.blocks = [b];
      app.markDirty();
      await app.flushSave();

      // Several edits in a row, of the kinds writing actually produces.
      for (final text in [
        'Once upon a time',
        'Once upon a time there',
        'Once upon a time, there',
        'Once upon a time, there was a 😀',
        'Once upon a time, there was a 😀 cat',
        'Once, there was a 😀 cat',
      ]) {
        b.content['text'] = text;
        b.updatedAt = nowMs() + 1;
        app.markDirty();
        await app.flushSave();
      }

      final page = rebuilt(repo, nbId, pageId);
      final blocks = (page['blocks'] as List).cast<Map<String, dynamic>>();
      final got = blocks.firstWhere((x) => x['id'] == b.id);
      expect((got['content'] as Map)['text'], 'Once, there was a 😀 cat',
          reason: 'the log is the record; it has to reproduce the page');
    });

    test('forty autosaves of one paragraph, weighed', () async {
      // **The number the whole change is for.** Writing a paragraph is not one
      // edit, it is dozens of autosaves at every pause in a sentence, and each
      // one used to append the entire paragraph again. This is that session,
      // and it weighs the log afterwards.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, tmp, nbId) = await notebook('onote_patch_weigh_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      var prose = List.filled(30, 'the quick brown fox jumps over it. ').join();
      final b = Block(
          type: BlockType.text, x: 0, y: 0, w: 400, content: {'text': prose});
      app.blocks = [b];
      app.markDirty();
      await app.flushSave();

      final ref = repo.notebooks.firstWhere((n) => n.id == nbId);
      final store = OpLogStore.forNotebook(ref.file);
      final before = store.readAll().fold<int>(0, (n, o) => n + o.encode().length);

      const saves = 40;
      for (var i = 0; i < saves; i++) {
        prose = '$prose and again. ';
        b.content['text'] = prose;
        b.updatedAt = nowMs() + 1 + i;
        app.markDirty();
        await app.flushSave();
      }
      final after = store.readAll().fold<int>(0, (n, o) => n + o.encode().length);
      final grew = after - before;

      // What the same session cost before: the whole paragraph, every time.
      final asBlocks = saves * prose.length;
      // ignore: avoid_print
      print('BLOCK.PATCH  $saves autosaves grew the log by $grew B; '
          'whole-block writes would have been about $asBlocks B '
          '(${(100 * grew / asBlocks).toStringAsFixed(1)}%)');
      expect(grew * 4, lessThan(asBlocks),
          reason: 'a quarter of the old cost is the bar this was worth doing '
              'for; it should be far better than that');
    });

    test('a rewritten paragraph falls back to the whole block', () async {
      // **A patch is not simply a smaller `block.set`.** It is a smaller one
      // that can be REFUSED: a patch whose base no longer matches is dropped
      // and the edit resolves to the other device's text, where a `block.set`
      // always wins its merge. That fragility is a real cost, so it is only
      // worth paying for a real saving.
      //
      // This test was written expecting the fallback to come from raw size,
      // and it failed: replacing thirty characters produces a splice that IS a
      // few bytes smaller than the block, because the block carries a uuid and
      // geometry too. Fewer bytes was the wrong bar. The rule is half the
      // bytes or better — what a paragraph edited at one point looks like, and
      // what one rewritten wholesale does not.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, tmp, nbId) = await notebook('onote_patch_fallback_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final b = Block(
          type: BlockType.text,
          x: 0,
          y: 0,
          w: 400,
          content: {'text': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'});
      app.blocks = [b];
      app.markDirty();
      await app.flushSave();
      final n = opCount(repo, nbId);

      b.content['text'] = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      b.updatedAt = nowMs() + 1;
      app.markDirty();
      await app.flushSave();

      expect(newOps(repo, nbId, n).single.kind, OpKind.blockSet);
    });

    test('a change it cannot express exactly is not expressed at all',
        () async {
      // Two values in `content` moving at once is not one splice, and half a
      // record is worse than a large one.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final (repo, app, tmp, nbId) = await notebook('onote_patch_two_');
      addTearDown(() {
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      final b = Block(
        type: BlockType.text,
        x: 0,
        y: 0,
        w: 400,
        content: {'text': 'hello there', 'fontSize': 15},
      );
      app.blocks = [b];
      app.markDirty();
      await app.flushSave();
      final n = opCount(repo, nbId);

      b.content['text'] = 'hello there!';
      b.content['fontSize'] = 18;
      b.updatedAt = nowMs() + 1;
      app.markDirty();
      await app.flushSave();

      expect(newOps(repo, nbId, n).single.kind, OpKind.blockSet);
    });
  });

  group('merging, where the guard earns its place', () {
    Op op(OpKind kind, Map<String, dynamic> d,
            {int seq = 1, int lamport = 1, String device = 'A', int? version}) =>
        Op(
          device: device,
          seq: seq,
          lamport: lamport,
          timestamp: 1,
          kind: kind,
          data: d,
          version: version ?? (kind == OpKind.blockPatch ? opPatchVersion : 1),
        );

    Map<String, dynamic> textBlock(String text) =>
        {'id': 'b1', 'type': 'text', 'content': {'text': text}};

    test('a patch on top of the text it expects', () {
      final s = spliceBetween('hello', 'hello world')!;
      final m = Materializer()
        ..apply(op(OpKind.blockSet, {'pageId': 'p', 'block': textBlock('hello')}))
        ..apply(op(
            OpKind.blockPatch,
            {
              'pageId': 'p',
              'blockId': 'b1',
              'k': 'text',
              'base': textFingerprint('hello'),
              'at': s.at,
              'del': s.del,
              'ins': s.ins,
            },
            seq: 2,
            lamport: 2));
      expect(
          ((m.pages['p']!.blocks['b1']!['content'] as Map)['text']),
          'hello world');
    });

    test('a patch on top of ANOTHER device\'s text leaves that text alone', () {
      // The corruption this exists to prevent, played out in the order the
      // total order can really produce.
      final s = spliceBetween('hello', 'hello world')!;
      final m = Materializer()
        ..apply(op(OpKind.blockSet, {'pageId': 'p', 'block': textBlock('hello')}))
        ..apply(op(OpKind.blockSet, {'pageId': 'p', 'block': textBlock('goodbye')},
            seq: 1, lamport: 2, device: 'B'))
        ..apply(op(
            OpKind.blockPatch,
            {
              'pageId': 'p',
              'blockId': 'b1',
              'k': 'text',
              'base': textFingerprint('hello'),
              'at': s.at,
              'del': s.del,
              'ins': s.ins,
            },
            seq: 2,
            lamport: 3));
      expect(((m.pages['p']!.blocks['b1']!['content'] as Map)['text']), 'goodbye',
          reason: 'last writer wins, exactly as it did before patches existed');
    });

    test('a patch to a block nobody has seen is dropped, not resurrected', () {
      final m = Materializer()
        ..apply(op(OpKind.blockPatch, {
          'pageId': 'p',
          'blockId': 'ghost',
          'k': 'text',
          'base': textFingerprint(''),
          'at': 0,
          'del': 0,
          'ins': 'x',
        }));
      expect(m.pages['p']?.blocks['ghost'], isNull);
    });
  });

  group('the envelope contract', () {
    test('this build reads a newer envelope than it writes', () {
      // The distinction a format bump lives or dies on. Writing the newer one
      // by default would take every older install offline the moment anybody
      // typed a character.
      expect(opWriteVersion, 1);
      expect(opFormatVersion, 2);
      expect(opPatchVersion, 2);
    });

    test('an op with no version at all is v1, whatever this build reads', () {
      // Every op on every disk in the world predates the field. Defaulting it
      // to "whatever this build reads" would silently promote all of them.
      final line = jsonEncode({
        'dev': 'd',
        'seq': 1,
        'lc': 1,
        'ts': 0,
        'op': 'block.set',
        'd': {'pageId': 'p', 'block': {'id': 'b'}},
      });
      expect(Op.decode(line)!.version, 1);
    });

    test('everything except a patch is still written at v1', () {
      expect(
          Op(
              device: 'd',
              seq: 1,
              lamport: 1,
              timestamp: 0,
              kind: OpKind.blockSet,
              data: const {}).version,
          1);
    });
  });
}
