// Colouring text that is already coloured replaces the colour.
//
// The owner: *"trying to change the colour of text after it has already been
// assigned a colour will not remove the old colour tag but just insert it
// inside the old one which makes it visible and coloured in the old colour."*
//
// It did, because the command worked by cases — swap the hex when the
// selection is exactly the inside of a wrapper, rewrite when it is exactly
// the whole wrapper, otherwise wrap what was selected — and the third case is
// the one every ordinary gesture reaches. A `{{#…}}` inside another one is
// not expressible: the grammar's inner is lazy, so the outer run ends at the
// first `}}` and the rest shows up as characters.
//
// `recolourSelection` reads the line as a colour per character instead, so
// replacing is the only thing it can do and clearing is the same operation
// with no colour.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/markdown/colour_spans.dart';

void main() {
  /// Colour `«…»` with [hex] (null clears), and return the new source.
  String? colour(String spec, String? hex) {
    final a = spec.indexOf('«');
    final b = spec.indexOf('»') - 1;
    final text = spec.replaceAll('«', '').replaceAll('»', '');
    return recolourSelection(text, a, b, hex)?.text;
  }

  group('replacing a colour', () {
    test('THE WHOLE OF A COLOURED WORD TAKES THE NEW COLOUR', () {
      expect(colour('{{#FF0000 «word»}}', '00FF00'), '{{#00FF00 word}}');
    });

    test('AND SO DOES PART OF ONE, BY SPLITTING THE RUN', () {
      expect(colour('{{#FF0000 «one» two}}', '00FF00'),
          '{{#00FF00 one}}{{#FF0000  two}}');
    });

    test('the middle of a run splits it in three', () {
      expect(colour('{{#FF0000 a «b» c}}', '00FF00'),
          '{{#FF0000 a }}{{#00FF00 b}}{{#FF0000  c}}');
    });

    test('a selection across two colours comes out as one', () {
      // Through the end of the red word and into the blue one: what was
      // selected is one run of the new colour, and the tail of the blue word
      // keeps its own.
      expect(colour('{{#FF0000 on«e}} {{#0000FF t»wo}}', '00FF00'),
          '{{#FF0000 on}}{{#00FF00 e t}}{{#0000FF wo}}');
    });

    test('plain text beside a coloured run is coloured too', () {
      expect(colour('a «b {{#FF0000 c»}} d', '00FF00'),
          'a {{#00FF00 b c}} d');
    });

    test('nothing nests, at any depth', () {
      final once = colour('«word»', 'FF0000')!;
      expect(once, '{{#FF0000 word}}');
      final twice = recolourSelection(once, 10, 14, '00FF00')!.text;
      expect(twice, '{{#00FF00 word}}');
      expect(twice, isNot(contains('{{#FF0000')));
    });
  });

  group('clearing it', () {
    test('A COLOURED WORD GOES BACK TO NO MARKUP AT ALL', () {
      expect(colour('{{#FF0000 «word»}}', null), 'word');
    });

    test('and part of one leaves the rest coloured', () {
      expect(colour('{{#FF0000 «one» two}}', null), 'one{{#FF0000  two}}');
    });

    test('clearing text that has no colour changes nothing', () {
      expect(colour('«word»', null), isNull,
          reason: 'and a null result is what stops an undo step being pushed');
    });

    test('setting the colour it already has changes nothing', () {
      expect(colour('{{#FF0000 «word»}}', 'FF0000'), isNull);
    });
  });

  group('what it must not disturb', () {
    test('OTHER MARKUP INSIDE THE RUN IS LEFT ALONE', () {
      expect(colour('{{#FF0000 «**word**»}}', '00FF00'),
          '{{#00FF00 **word**}}');
    });

    test('a colour inside bold stays inside the bold', () {
      expect(colour('**{{#FF0000 «word»}}**', '00FF00'),
          '**{{#00FF00 word}}**');
    });

    test('a run cannot span a newline, so each line is its own', () {
      expect(colour('«one\ntwo»', 'FF0000'),
          '{{#FF0000 one}}\n{{#FF0000 two}}');
    });

    test('a line the selection does not reach is untouched', () {
      expect(colour('{{#FF0000 keep}}\n«this»', '00FF00'),
          '{{#FF0000 keep}}\n{{#00FF00 this}}');
    });

    test('a selection of markers only does nothing', () {
      // `{{#FF0000 ` is ten characters; selecting them is not selecting text.
      expect(recolourSelection('{{#FF0000 word}}', 0, 10, '00FF00'), isNull);
    });
  });

  group('where the selection lands afterwards', () {
    test('IT STILL COVERS THE SAME CHARACTERS', () {
      final e = recolourSelection('{{#FF0000 one two}}', 10, 13, '00FF00')!;
      expect(e.text, '{{#00FF00 one}}{{#FF0000  two}}');
      expect(e.text.substring(e.base, e.extent), 'one');
    });

    test('including when the text before it grew', () {
      final e = recolourSelection('hello there', 6, 11, 'FF0000')!;
      expect(e.text, 'hello {{#FF0000 there}}');
      expect(e.text.substring(e.base, e.extent), 'there');
    });

    test('and when a colour was taken off', () {
      final e = recolourSelection('a {{#FF0000 b}} c', 12, 13, null)!;
      expect(e.text, 'a b c');
      expect(e.text.substring(e.base, e.extent), 'b');
    });
  });

  group('what colour is this already', () {
    test('one colour all through', () {
      expect(colourOfSelection('{{#FF0000 word}}', 10, 14), 'FF0000');
    });

    test('two colours is no answer', () {
      // Through the `a` and the `b`: everything between them is markers.
      expect(
          colourOfSelection('{{#FF0000 a}}{{#0000FF b}}', 10, 24), isNull);
    });

    test('part of it uncoloured is no answer either', () {
      expect(colourOfSelection('{{#FF0000 a}} b', 10, 15), isNull);
    });

    test('plain text has none', () {
      expect(colourOfSelection('word', 0, 4), isNull);
    });
  });
}
