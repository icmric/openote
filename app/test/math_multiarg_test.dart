// Functions that need more than one thing (owner, v0.23).
//
// *"id like you to fill out the format by default when inserting it, so \gcd
// will add gcd( , ), with the spaces being the boxes we already have
// elsewhere, this should be the case for anything that REQUIRES multiple
// arguments, stuff like sin and whatever shouldnt do that as they have only a
// single argument."*
//
// And the owner's own bug report: *"I also noticed that mod didnt work."*
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/math/evaluate.dart';
import 'package:openote/math/math_editor.dart';
import 'package:openote/math/math_inventory.dart';
import 'package:openote/math/math_linear_projection.dart';
import 'package:openote/math/math_parse.dart';
import 'package:openote/math/math_tree.dart';
import 'package:openote/math/math_view.dart';

/// One backslash, so the expectations read as what a student types.
final bs = String.fromCharCode(92);

MathEditor typed(String chars) {
  final e = MathEditor.empty();
  for (final ch in chars.split('')) {
    e.insertChar(ch);
  }
  return e;
}

String answerOf(String linear) => evaluateLinear(linear).display;

void main() {
  group('the calculator learned a comma', () {
    test('the greatest common divisor and the lowest common multiple', () {
      expect(answerOf('gcd(12,18)'), '6');
      expect(answerOf('gcd(12, 18)'), '6', reason: 'spaces are allowed');
      expect(answerOf('lcm(4,6)'), '12');
      expect(answerOf('gcd(-12,18)'), '6', reason: 'a sign is not a factor');
      expect(answerOf('lcm(3,5)'), '15');
    });

    test('more than two, because gcd of three numbers is a real question', () {
      expect(answerOf('gcd(12,18,30)'), '6');
      expect(answerOf('lcm(2,3,4)'), '12');
      expect(answerOf('max(3,9,4)'), '9');
      expect(answerOf('min(3,9,4)'), '3');
    });

    test('combinations and arrangements, as a Casio spells them', () {
      expect(answerOf('nCr(5,2)'), '10');
      expect(answerOf('nCr(52,5)'), '2598960');
      expect(answerOf('nPr(5,2)'), '20');
      expect(answerOf('nCr(5,0)'), '1');
      expect(answerOf('nCr(5,5)'), '1');
    });

    test('an argument can be a sum, and the answer can be worked on', () {
      expect(answerOf('gcd(6*2,18)'), '6');
      expect(answerOf('max(1,2)+10'), '12');
      expect(answerOf('gcd(12,18)*2'), '12');
    });

    test('and a comma is still just a comma everywhere else', () {
      // Nothing else in the grammar takes one, so this must READ as a
      // failure rather than quietly meaning something.
      expect(evaluateLinear('1,2').isOk, isFalse);
      expect(evaluateLinear('sin(30,2)').isOk, isFalse);
    });

    test('too few arguments says so rather than guessing', () {
      final r = evaluateLinear('gcd(12)');
      expect(r.isOk, isFalse);
      expect(r.error, contains('2'));
    });
  });

  group('a remainder is written between its two numbers', () {
    test('which is what the owner reported did not work', () {
      expect(answerOf('17 mod 5'), '2');
      expect(answerOf('20 mod 3'), '2');
      expect(answerOf('10 mod 2'), '0');
    });

    test('and it binds like a multiplication', () {
      expect(answerOf('10 + 17 mod 5'), '12',
          reason: '10 + (17 mod 5), not (10 + 17) mod 5');
    });

    test('the sign follows the divisor, as every language a student meets '
        'next does', () {
      expect(answerOf('-7 mod 3'), '2');
      expect(answerOf('7 mod -3'), '-2');
    });

    test('the function spelling works too, for anyone who types it', () {
      expect(answerOf('mod(17,5)'), '2');
    });

    test('but a variable called `mode` is still a variable', () {
      expect(evaluateLinear('4 mode').isOk, isFalse,
          reason: 'the word is only taken whole');
    });

    test('and the palette button projects to it', () {
      final e = MathEditor.open(r'17\bmod 5')!;
      expect(rowToLinear(e.root).trim(), '17 mod 5');
      expect(evaluateLinear(rowToLinear(e.root)).display, '2');
    });
  });

  group('a log with a base', () {
    test('works out, whatever the base', () {
      expect(answerOf('log2(8)'), '3');
      expect(answerOf('log10(1000)'), '3');
      expect(answerOf('log5(125)'), '3');
      expect(answerOf('log3(81)'), '4');
    });

    test('and the subscript form a student writes projects to it', () {
      final e = MathEditor.open(r'\log_{2}\left( 8\right) ')!;
      expect(evaluateLinear(rowToLinear(e.root)).display, '3');
    });
  });

  group('the template you get when you ask for one', () {
    test('the palette builds gcd with two empty boxes', () {
      final e = MathEditor.empty();
      e.insertItem(mathItemsById['fn-gcd']!);
      expect(e.latex, r'\mathrm{gcd}\left( ,\right) ');
      final call = e.root.children.single as MCall;
      expect(call.args.length, 2);
      expect(identical(e.caretRow, call.args.first), isTrue,
          reason: 'the caret lands in the first box');
    });

    test('Tab walks from one box to the next', () {
      final e = MathEditor.empty();
      e.insertItem(mathItemsById['fn-gcd']!);
      e.insertChar('1');
      e.insertChar('2');
      expect(e.tab(), isTrue);
      e.insertChar('1');
      e.insertChar('8');
      expect(e.latex, r'\mathrm{gcd}\left( 12,18\right) ');
      expect(evaluateLinear(rowToLinear(e.root)).display, '6');
    });

    test(r'typing \gcd then a space gives the same thing', () {
      final e = typed(bs + 'gcd ');
      expect(e.latex, r'\mathrm{gcd}\left( ,\right) ');
    });

    test(r'and typing gcd( gives it too, with no stray bracket after', () {
      final e = typed('gcd(');
      expect(e.latex, r'\mathrm{gcd}\left( ,\right) ',
          reason: 'the template brings its own brackets; a second empty pair '
              'used to be left sitting after it');
    });

    test('every template survives a save and a reopen, boxes and all', () {
      for (final id in kCallFunctions.keys) {
        final e = MathEditor.empty();
        e.insertItem(mathItemsById['fn-$id']!);
        final saved = e.latex;
        final reopened = MathEditor.open(saved);
        expect(reopened, isNotNull, reason: id);
        expect(reopened!.latex, saved, reason: 'byte for byte: $id');
        expect(reopened.root.children.single, isA<MCall>(),
            reason: '$id came back as one node, not a name beside a bracket');
      }
    });

    test('a filled one round-trips too', () {
      final e = MathEditor.open(r'\mathrm{nCr}\left( 5,2\right) ')!;
      expect(e.latex, r'\mathrm{nCr}\left( 5,2\right) ');
      expect(evaluateLinear(rowToLinear(e.root)).display, '10');
    });

    test('a hand-typed sin is NOT turned into a template', () {
      // Only the names that require more than one argument, and only where a
      // bracket follows.
      final e = MathEditor.open(r'\sin \left( x \right) ')!;
      expect(e.root.children.any((n) => n is MCall), isFalse);
      expect(mathItemsById['fn-sin']!.build().first, isA<MSym>());
    });
  });

  group('what is on the list, and what is not', () {
    test('only functions that genuinely need more than one thing', () {
      expect(kCallFunctions.keys.toSet(),
          {'gcd', 'lcm', 'max', 'min', 'nCr', 'nPr'});
      expect(kCallFunctions.containsKey('sin'), isFalse);
      expect(kCallFunctions.containsKey('log'), isFalse);
      expect(kCallFunctions.containsKey('sqrt'), isFalse);
      expect(kCallFunctions.containsKey('mod'), isFalse,
          reason: 'a remainder is written between its two numbers');
    });

    test('each one has a button that draws the shape you will get', () {
      for (final id in kCallFunctions.keys) {
        final item = mathItemsById['fn-$id'];
        expect(item, isNotNull, reason: id);
        expect(item!.preview, contains('square'),
            reason: '$id should show its boxes on the button');
        expect(item.typeIt, bs + id);
      }
    });

    test('and a plain-words search finds it', () {
      expect(searchMathItems('highest common factor').first.id, 'fn-gcd');
      expect(searchMathItems('combinations').first.id, 'fn-nCr');
      expect(searchMathItems('remainder').first.id, 'fn-mod');
    });
  });

  group('it draws', () {
    testWidgets('every template, filled and empty', (tester) async {
      final cases = <String>[
        for (final id in kCallFunctions.keys)
          (MathEditor.empty()..insertItem(mathItemsById['fn-$id']!)).latex,
        r'\mathrm{gcd}\left( 12,18\right) ',
        r'\mathrm{nCr}\left( \frac{1}{2},2\right) ',
      ];
      for (final tex in cases) {
        await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: OnoteMath(tex,
                  textStyle: const TextStyle(fontSize: 22)),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.byType(MathSourceFallback), findsNothing,
            reason: 'the renderer could not draw $tex');
      }
    });
  });

  group('the number of boxes is the number the function takes', () {
    // A comma typed inside the first box of `gcd( , )` used to grow a THIRD
    // box on reopen — one the template never promised, that nothing can
    // remove, and that either changes the answer (gcd, lcm, max and min
    // reduce over all of them) or is quietly ignored (nCr, nPr).
    test('an extra comma does not grow a box', () {
      final r = parseLatex(r'\mathrm{gcd}\left( 1,2,3\right) ');
      expect(r.supported, isTrue, reason: 'it still reads as something');
      expect(r.root!.children.whereType<MCall>(), isEmpty,
          reason: 'as the plain symbols it looks like, not as a call');
    });

    test('one argument short is not a call either', () {
      final r = parseLatex(r'\mathrm{gcd}\left( 12\right) ');
      expect(r.supported, isTrue);
      expect(r.root!.children.whereType<MCall>(), isEmpty);
    });

    test('and the right number still reads as the call it is', () {
      for (final entry in kCallFunctions.entries) {
        final args = List.filled(entry.value, '1').join(',');
        final r = parseLatex(
            r'\mathrm{' + entry.key + r'}\left( ' + args + r'\right) ');
        final call = r.root!.children.whereType<MCall>().singleOrNull;
        expect(call, isNotNull, reason: entry.key);
        expect(call!.args.length, entry.value, reason: entry.key);
      }
    });
  });

}
