// What an import says arrived (P5).
//
// The failure half has been surfaced since the Tier-1 pass — skipped sections,
// dropped strokes. This is the other half, and the reason it matters is
// conversion, not symmetry: someone who has just handed over five years of
// OneNote notes cannot tell whether it worked, and a bare page count followed
// by silence reads as "it probably lost something".

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/export/onenote_import.dart';

void main() {
  group('the arrival note', () {
    test('names everything that came in', () {
      expect(importArrivalNote(324, 372, 64616),
          '324 pages, 372 images and 64,616 ink strokes');
    });

    test('groups thousands, because 64616 is a number you count digits on', () {
      expect(importArrivalNote(1000, 0, 0), '1,000 pages');
      expect(importArrivalNote(1234567, 0, 0), '1,234,567 pages');
      expect(importArrivalNote(999, 0, 0), '999 pages');
    });

    test('names imported tags too', () {
      expect(importArrivalNote(12, 0, 0, 40),
          '12 pages and 40 tags');
      expect(importArrivalNote(324, 372, 64616, 811),
          '324 pages, 372 images, 64,616 ink strokes and 811 tags');
    });

    test('singulars', () {
      expect(importArrivalNote(1, 1, 1), '1 page, 1 image and 1 ink stroke');
    });

    // A notebook of typed notes should not be told it imported no ink; a clause
    // that is always present stops being information.
    test('omits what a notebook does not have', () {
      expect(importArrivalNote(12, 0, 0), '12 pages');
      expect(importArrivalNote(12, 3, 0), '12 pages and 3 images');
      expect(importArrivalNote(12, 0, 9), '12 pages and 9 ink strokes');
    });
  });
}
