// An edit to handwriting that lives in a blob has to survive the next save.
//
// From issue #20: *"Sometimes dragging only moves the selection box without
// moving the actual content … I've also seen objects suddenly jump to
// different positions after deleting something else, as if their displayed
// positions and selection boxes aren't updating together."*
//
// That is this. A block's x/y are envelope fields and go to disk every time;
// its strokes were going to disk only on the way INTO blob form, and a block
// already in blob form had its working strokes dropped on the way out and the
// old reference put straight back. So a move wrote the new rectangle and the
// old handwriting, and one reload later the two disagreed by exactly the
// distance dragged.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/ink/ink_storage.dart';
import 'package:openote/model/models.dart';

void main() {
  late Map<String, Uint8List> store;
  late List<int> written;

  setUp(() {
    store = {};
    written = [];
  });

  String put(Uint8List bytes) {
    final hash = 'sha256:${bytes.length}:'
        '${bytes.fold<int>(7, (a, v) => (a * 31 + v) & 0xffffff)}';
    store[hash] = bytes;
    written.add(bytes.length);
    return hash;
  }

  Uint8List? get(String hash) => store[hash];

  Map<String, dynamic> inlineInk({double at = 10}) => {
        'strokes': [
          Stroke(
            tool: 'pen',
            colorHex: '#101010',
            size: 2,
            x: [at, at + 10, at + 20],
            y: [at, at + 10, at + 20],
            p: [1, 1, 1],
            t: [0, 1, 2],
          ).toJson(),
        ],
      };

  /// Inline strokes → blob → back to the working shape the canvas edits, as a
  /// save and a page load do it.
  Map<String, dynamic> roundTripped(Map<String, dynamic> inline, int rev) =>
      InkStorage.toWorking(InkStorage.toPersisted(inline, put), get, rev: rev);

  List<double> xsOf(Map<String, dynamic> content) => [
        for (final v
            in ((InkStorage.strokesOf(content).first as Map)['x'] as List))
          (v as num).toDouble()
      ];

  test('a move of blob-backed ink is still there after the next save', () {
    final working = roundTripped(inlineInk(), 100);
    expect(xsOf(working), [10, 20, 30], reason: 'the round trip itself is fine');

    // What moveSelectedBy does to the strokes, and the revision bump that
    // comes with any change to a block.
    for (final sj in InkStorage.strokesOf(working)) {
      final m = sj as Map;
      m['x'] = [for (final v in (m['x'] as List)) (v as num) + 100];
      m['y'] = [for (final v in (m['y'] as List)) (v as num) + 100];
    }

    final saved = InkStorage.toPersisted(working, put, rev: 101);
    expect(xsOf(InkStorage.toWorking(saved, get, rev: 101)), [110, 120, 130]);
  });

  test('an erase is not undone by the save that follows it', () {
    final two = inlineInk();
    (two['strokes'] as List).add(Stroke(
      tool: 'pen',
      colorHex: '#101010',
      size: 2,
      x: [200, 210],
      y: [200, 210],
      p: [1, 1],
      t: [0, 1],
    ).toJson());
    final working = roundTripped(two, 100);
    expect(InkStorage.strokesOf(working), hasLength(2));

    working['strokes'] = [InkStorage.strokesOf(working).first];
    final saved = InkStorage.toPersisted(working, put, rev: 101);
    expect(InkStorage.strokeCount(saved), 1,
        reason: 'the rubbed-out stroke did not come back');
  });

  test('a recolour survives, which no count or bounding box would notice', () {
    final working = roundTripped(inlineInk(), 100);
    ((InkStorage.strokesOf(working).first as Map)['brush'] as Map)['color'] = '#FF0000';

    final saved = InkStorage.toPersisted(working, put, rev: 101);
    final back = InkStorage.toWorking(saved, get, rev: 101);
    expect(((InkStorage.strokesOf(back).first as Map)['brush'] as Map)['color'], '#FF0000');
  });

  test('ink nobody touched is not re-encoded', () {
    final working = roundTripped(inlineInk(), 100);
    final before = written.length;

    final saved = InkStorage.toPersisted(working, put, rev: 100);

    expect(written.length, before, reason: 'no blob was written');
    expect(saved[kInkKey], working[kInkKey],
        reason: 'and the identical reference went back');
    expect(saved.containsKey(kStrokesKey), isFalse,
        reason: 'the working strokes are still dropped on the way out');
  });

  test('the working form carries nothing extra to disk', () {
    final working = roundTripped(inlineInk(), 100);
    expect(working.containsKey(kInkFromKey), isTrue,
        reason: 'the decode stamps what it decoded');
    for (final rev in [100, 101]) {
      expect(InkStorage.toPersisted(working, put, rev: rev).keys,
          isNot(contains(kInkFromKey)),
          reason: 'changed or not, the stamp does not reach the file');
    }
  });

  test('a caller that cannot say re-encodes rather than guess', () {
    // Undo restores a block from a snapshot, and a copied map carries no
    // revision anybody can trust. Spending an encode is the cheap end of that
    // choice; dropping somebody's edit is not.
    final working = roundTripped(inlineInk(), 100);
    ((InkStorage.strokesOf(working).first as Map)['brush'] as Map)['color'] = '#00FF00';
    final saved = InkStorage.toPersisted(working, put);
    final back = InkStorage.toWorking(saved, get);
    expect(((InkStorage.strokesOf(back).first as Map)['brush'] as Map)['color'], '#00FF00');
  });

  group('when the bytes are not there', () {
    test('the reference stands, however the working list was edited', () {
      final persisted = InkStorage.toPersisted(inlineInk(), put);
      final ref = persisted[kInkKey];
      store.clear(); // the blob has not synced down yet

      final working = InkStorage.toWorking(persisted, get, rev: 100);
      expect(InkStorage.strokesOf(working), isEmpty,
          reason: 'it draws nothing rather than failing to open');

      // Something edits the block anyway — a drag, or a stroke added to it.
      final saved = InkStorage.toPersisted(working, put, rev: 101);
      expect(saved[kInkKey], ref,
          reason: 'an empty decode must not overwrite real handwriting');
    });

    test('and a block that really is empty keeps its empty reference', () {
      final empty = InkStorage.toPersisted({'strokes': const []}, put);
      expect(InkStorage.strokeCount(empty), 0);
      final working = InkStorage.toWorking(empty, get, rev: 100);
      final saved = InkStorage.toPersisted(working, put, rev: 101);
      expect(InkStorage.strokeCount(saved), 0);
    });
  });

  test('a whole page of blocks goes through with its revisions', () {
    final ink = Block(type: BlockType.ink, x: 0, y: 0, content: inlineInk());
    final text = Block(type: BlockType.text, x: 0, y: 0, content: {'text': 'x'});
    final persisted = InkStorage.persistAll([ink, text], put);
    final working = InkStorage.workingAll(persisted, get);

    for (final sj in InkStorage.strokesOf(working.first.content)) {
      (sj as Map)['x'] = [for (final v in (sj['x'] as List)) (v as num) + 5];
    }
    working.first.updatedAt += 1;

    final again = InkStorage.persistAll(working, put);
    final back = InkStorage.workingAll(again, get);
    expect(xsOf(back.first.content), [15, 25, 35]);
  });
}
