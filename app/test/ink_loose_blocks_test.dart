// A stroke is its own object on the canvas and not its own envelope on disk.
//
// One stroke per block is what issue #20 asked for, twice. Measured, it cost
// 4.7x the storage: 200 strokes of 40 points went from 26 KB as one block to
// 123 KB as 200, and almost all of the difference was envelope — 380 bytes per
// block, of which 80 are fields that are null or zero for every stroke anybody
// has ever drawn. The owner: *"that is considerably less space efficient than
// i was expecting it to be, surley there has to be a way to provide more
// control over ink strokes without an almost 5x increase in storage use."*
//
// So selection granularity and storage granularity are separated. Loose
// strokes travel as one block and come back as one block each; a block with
// several strokes and no `loose` flag is a GROUP, which is what the lasso
// makes, and it is stored and read exactly as before.
//
// This file is where the dangerous half lives. Every test here is about not
// losing handwriting across the boundary.
import 'dart:convert';
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

  Map<String, dynamic> strokeAt(double x, double y) => Stroke(
        tool: 'pen',
        colorHex: '#211F1B',
        size: 2,
        x: [x, x + 10, x + 20],
        y: [y, y + 5, y + 10],
        p: const [1, 1, 1],
        t: const [0, 1, 2],
      ).toJson();

  /// One stroke, one block: what the canvas makes while somebody writes.
  Block loose(double x, double y, {int rev = 100}) {
    final b = Block(type: BlockType.ink, x: 0, y: 0, content: {
      'strokes': [strokeAt(x, y)]
    });
    b.updatedAt = rev;
    return b;
  }

  /// Several strokes in one block: what the lasso makes.
  Block grouped(List<Offset2> at, {int rev = 100}) {
    final b = Block(type: BlockType.ink, x: 0, y: 0, content: {
      'strokes': [for (final p in at) strokeAt(p.x, p.y)]
    });
    b.updatedAt = rev;
    return b;
  }

  List<Map<String, dynamic>> strokesOf(Block b) => [
        for (final s in InkStorage.strokesOf(b.content))
          (s as Map).cast<String, dynamic>()
      ];

  List<double> firstXs(Block b) =>
      [for (final v in strokesOf(b).first['x'] as List) (v as num).toDouble()];

  group('the round trip', () {
    test('TWENTY STROKES GO AS ONE BLOCK AND COME BACK AS TWENTY', () {
      final page = [for (var i = 0; i < 20; i++) loose(i * 30.0, 0)];

      final saved = InkStorage.persistAll(page, put);
      expect(saved, hasLength(1), reason: 'one envelope, one blob');
      expect(written, hasLength(1));
      expect(InkStorage.strokeCount(saved.single.content), 20);

      final back = InkStorage.workingAll(saved, get);
      expect(back, hasLength(20), reason: 'and twenty objects to select');
      for (var i = 0; i < 20; i++) {
        expect(strokesOf(back[i]), hasLength(1));
        expect(firstXs(back[i]).first, i * 30.0,
            reason: 'in the order they were drawn, which is the order they '
                'are painted in');
      }
    });

    test('AND THE IDS ARE THE SAME ON THE WAY BACK IN', () {
      final saved = InkStorage.persistAll(
          [for (var i = 0; i < 5; i++) loose(i * 30.0, 0)], put);
      final once = InkStorage.workingAll(saved, get).map((b) => b.id).toList();
      final twice =
          InkStorage.workingAll(InkStorage.persistAll(saved, put), get)
              .map((b) => b.id)
              .toList();
      expect(twice, once,
          reason: 'a derived id has to be stable, or an undo snapshot taken '
              'before a save would restore blocks nothing can find');
      expect(once.first, contains(kLooseSep));
    });

    test('each one gets its own rectangle, and the stored one the union', () {
      final saved =
          InkStorage.persistAll([loose(0, 0), loose(100, 50)], put);
      expect(saved.single.x, 0);
      expect(saved.single.w, 120, reason: 'the union of the two');

      final back = InkStorage.workingAll(saved, get);
      expect(back.first.w, 20, reason: 'and each stroke only its own');
      expect(back.last.x, 100);
    });
  });

  group('a group is not loose', () {
    test('A LASSOED GROUP STAYS ONE BLOCK THROUGH A ROUND TRIP', () {
      final page = [
        grouped(const [Offset2(0, 0), Offset2(40, 0), Offset2(80, 0)])
      ];
      final saved = InkStorage.persistAll(page, put);
      expect(saved, hasLength(1));
      expect(saved.single.content[kLooseKey], isNull,
          reason: 'it is not a bag of loose strokes, it is one object');

      final back = InkStorage.workingAll(saved, get);
      expect(back, hasLength(1), reason: 'and it comes back as one object');
      expect(strokesOf(back.single), hasLength(3));
    });

    test('a page with both keeps them apart', () {
      final page = [
        loose(0, 0),
        grouped(const [Offset2(200, 0), Offset2(240, 0)]),
        loose(400, 0),
      ];
      final saved = InkStorage.persistAll(page, put);
      expect(saved, hasLength(2), reason: 'the two loose ones, and the group');

      final back = InkStorage.workingAll(saved, get);
      expect(back, hasLength(3));
      expect(back.map((b) => strokesOf(b).length), [1, 1, 2],
          reason: 'the loose pair land where the first of them was');
    });

    test('one loose stroke on its own is left exactly as it is', () {
      final only = loose(0, 0);
      final saved = InkStorage.persistAll([only], put);
      expect(saved.single.id, only.id, reason: 'nothing to gather');
      expect(saved.single.content[kLooseKey], isNull);
      expect(InkStorage.workingAll(saved, get), hasLength(1));
    });
  });

  group('edits survive the save that follows them', () {
    test('MOVING ONE STROKE MOVES THAT STROKE', () {
      final saved =
          InkStorage.persistAll([for (var i = 0; i < 4; i++) loose(i * 30.0, 0)], put);
      final back = InkStorage.workingAll(saved, get);

      // What moveSelectedBy does to the third one, and the revision bump that
      // comes with any change to a block.
      final moved = back[2];
      for (final sj in InkStorage.strokesOf(moved.content)) {
        final m = sj as Map;
        m['x'] = [for (final v in (m['x'] as List)) (v as num) + 7];
      }
      moved.updatedAt += 1;

      final again = InkStorage.workingAll(InkStorage.persistAll(back, put), get);
      expect(again, hasLength(4));
      expect(firstXs(again[2]).first, 67, reason: '60 + 7');
      expect(firstXs(again[1]).first, 30, reason: 'and nothing else moved');
    });

    test('RUBBING ONE OUT DOES NOT BRING IT BACK', () {
      // The dangerous case. An erase leaves every surviving stroke untouched,
      // so the revision stamps all still match — and a save that trusted them
      // alone would put the old reference back and resurrect the stroke on
      // the next page load. The stroke COUNT is the other half of the test.
      final saved =
          InkStorage.persistAll([for (var i = 0; i < 3; i++) loose(i * 30.0, 0)], put);
      final back = InkStorage.workingAll(saved, get);
      back.removeAt(1);

      final again = InkStorage.workingAll(InkStorage.persistAll(back, put), get);
      expect(again, hasLength(2));
      expect(again.map((b) => firstXs(b).first), [0, 60]);
    });

    test('a stroke added beside loaded ones keeps both', () {
      final saved =
          InkStorage.persistAll([loose(0, 0), loose(30, 0)], put);
      final back = InkStorage.workingAll(saved, get)..add(loose(300, 300));

      final again = InkStorage.workingAll(InkStorage.persistAll(back, put), get);
      expect(again, hasLength(3));
      expect(again.map((b) => firstXs(b).first), [0, 30, 300]);
    });

    test('and a recolour, which no count or rectangle would notice', () {
      final saved = InkStorage.persistAll([loose(0, 0), loose(30, 0)], put);
      final back = InkStorage.workingAll(saved, get);
      (strokesOf(back.first).first['brush'] as Map)['color'] = '#FF0000';
      back.first.updatedAt += 1;

      final again = InkStorage.workingAll(InkStorage.persistAll(back, put), get);
      expect((strokesOf(again.first).first['brush'] as Map)['color'],
          '#FF0000');
    });
  });

  group('what it costs', () {
    test('STROKES NOBODY TOUCHED ARE NOT RE-ENCODED', () {
      final saved =
          InkStorage.persistAll([for (var i = 0; i < 8; i++) loose(i * 30.0, 0)], put);
      final back = InkStorage.workingAll(saved, get);
      final before = written.length;

      final again = InkStorage.persistAll(back, put);

      expect(written.length, before, reason: 'no blob was written');
      expect(again.single.content[kInkKey], saved.single.content[kInkKey],
          reason: 'and the identical reference went back');
    });

    test('and the stroke list never reaches the page JSON', () {
      final saved =
          InkStorage.persistAll([loose(0, 0), loose(30, 0)], put);
      final json = jsonEncode(saved.single.toJson());
      expect(json, isNot(contains('"strokes"')));
      expect(json.length, lessThan(600),
          reason: 'the whole point: one envelope, not one per stroke');
    });
  });

  group('when the bytes are not there', () {
    test('A LOOSE BLOCK WITH NO BLOB KEEPS ITS REFERENCE', () {
      final saved =
          InkStorage.persistAll([loose(0, 0), loose(30, 0)], put);
      final ref = saved.single.content[kInkKey];
      store.clear(); // not synced down yet

      final back = InkStorage.workingAll(saved, get);
      expect(back, hasLength(1),
          reason: 'nothing to split, so it stays whole rather than vanishing');
      expect(InkStorage.strokesOf(back.single.content), isEmpty,
          reason: 'and draws nothing rather than failing to open');

      // Something edits the page anyway.
      back.single.updatedAt += 1;
      final again = InkStorage.persistAll(back, put);
      expect(again.single.content[kInkKey], ref,
          reason: 'an empty decode must not overwrite real handwriting');
    });
  });
}

/// A point, named so the test reads as points rather than records.
class Offset2 {
  const Offset2(this.x, this.y);
  final double x;
  final double y;
}
