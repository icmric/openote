// A page whose handwriting cannot be found must still open.
//
// Found on the owner's own demo notebook, 2026-10-07: *"my maths page has
// become corrupted and just shows grey over the canvas."* It was not
// corruption. The page held eight ink blocks in the persisted blob-ref form,
// and the blobs were no longer on disk — so `InkStorage.toWorking` could not
// hydrate them and returned the content untouched, leaving no `strokes` key.
// Every reader on the canvas then cast `content['strokes'] as List`
// unchecked, `_strokesOf` threw a TypeError during build, and the whole page
// became an `ErrorWidget` — which in a release build is a plain grey
// rectangle with nothing said and no way back in.
//
// The behaviour asserted here was already promised in `toWorking`'s own doc
// comment: *"an ink block that draws nothing rather than a page that fails to
// open."* These tests are what makes that true rather than aspirational.
//
// Two halves, and the second matters as much as the first: the page must
// open, AND the unresolvable reference must survive a save. Returning an
// empty stroke list to the canvas is only safe because `toPersisted` puts the
// identical descriptor back; if that ever changed, this would be a fix that
// quietly deletes handwriting the moment a blob is slow to sync.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/ink/ink_storage.dart';
import 'package:openote/model/models.dart';

/// Content exactly as the owner's container held it: a v1 descriptor naming a
/// blob, 20 strokes, and no inline geometry.
Map<String, dynamic> refForm({String? base, int n = 20}) => {
      kInkKey: {
        'v': 1,
        'base': base ?? ('a' * 64),
        'add': const <String>[],
        'gone': '',
        'n': n,
        'o': const [568.4, 141.4],
      },
    };

void main() {
  group('an ink blob that cannot be found', () {
    test('still yields a working form the canvas can read', () {
      final out = InkStorage.toWorking(refForm(), (_) => null);

      // The key must EXIST. Its absence was the bug: `as List` on null.
      expect(out.containsKey(kStrokesKey), isTrue,
          reason: 'the canvas casts this key unchecked');
      expect(out[kStrokesKey], isEmpty);
      expect(InkStorage.strokesOf(out), isEmpty);
    });

    test('keeps the reference, so a save cannot destroy the ink', () {
      final working = InkStorage.toWorking(refForm(), (_) => null);

      // A save of the untouched page. If this re-encoded the empty stroke
      // list into a new blob, the handwriting would be gone the first time
      // the page was opened on a machine that had not synced yet.
      var encoded = 0;
      final saved = InkStorage.toPersisted(working, (bytes) {
        encoded++;
        return 'should never happen';
      });

      expect(encoded, 0, reason: 'nothing should have been re-encoded');
      expect(saved[kInkKey], refForm()[kInkKey],
          reason: 'the identical descriptor must go back');
      expect(saved.containsKey(kStrokesKey), isFalse,
          reason: 'the working list does not belong on disk');
    });

    test('still reports how much handwriting is there', () {
      // The count comes from the descriptor, not the strokes, so the rest of
      // the app can still tell the difference between "an empty ink block"
      // and "twenty strokes we cannot reach".
      final working = InkStorage.toWorking(refForm(n: 20), (_) => null);
      expect(InkStorage.strokeCount(working), 20);
    });

    test('bytes that will not decode are treated the same way', () {
      final junk = Uint8List.fromList([0, 1, 2, 3]);
      final out = InkStorage.toWorking(refForm(), (_) => junk);
      expect(out.containsKey(kStrokesKey), isTrue);
      expect(out[kStrokesKey], isEmpty);
      expect(out[kInkKey], refForm()[kInkKey], reason: 'ref untouched');
    });

    test('a blob that IS there still hydrates normally', () {
      // The negative control. Without it, "returns an empty list" would pass
      // just as well on a build that never loads any ink at all.
      final strokes = [
        Stroke(
            id: 's1',
            tool: 'pen',
            colorHex: '#000000',
            size: 2.0,
            x: [1, 2, 3],
            y: [4, 5, 6]),
      ];
      final persisted = InkStorage.toPersisted(
          {kStrokesKey: [for (final s in strokes) s.toJson()]},
          (bytes) {
        store = bytes;
        return 'hash';
      });
      final back = InkStorage.toWorking(persisted, (h) => store);
      expect(InkStorage.strokesOf(back), hasLength(1));
    });
  });
}

Uint8List? store;
