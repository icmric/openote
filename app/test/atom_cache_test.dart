// An atom widget is built once per identity, never once per keystroke.
//
// `buildTextSpan` runs on every keystroke and rebuilds the whole span tree.
// The spans themselves are cheap — under a millisecond — but the WIDGETS
// inside them are not. Measured on one machine before the cache, per
// keystroke in a single block: 20 equations 129.6 ms, 40 equations 227.0 ms,
// 100 equations 561.7 ms, against 16.5 ms for the same block with none.
// After: 16.3, 17.9 and 25.6 ms. Forty equations is an ordinary page of maths
// notes, and a fifth of a second per character is not typing.
//
// **These tests assert identity, not milliseconds.** A wall-clock assertion
// would fail on a loaded CI box and pass on a fast one while saying nothing
// about whether the cache works; `identical()` is the property the speed is
// made of, and it is exact. CONTRIBUTING.md's rule about timing meters is the
// same rule.
//
// The other half of what is tested here is the DANGER of a cache: an atom
// whose callbacks captured an offset must not survive that offset moving, or
// it writes to the wrong place in the note. Every key carries the offsets for
// that reason, and the tests below pin both directions of it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/theme/onote_theme.dart';

void main() {
  /// Every widget the controller put in the paragraph, in order.
  List<Widget> atomsOf(WidgetTester t, LiveMarkdownController c) {
    final span = c.buildTextSpan(
      context: t.element(find.byType(TextField)),
      style: const TextStyle(fontSize: 15),
      withComposing: false,
    );
    final out = <Widget>[];
    span.visitChildren((s) {
      if (s is WidgetSpan) out.add(s.child);
      return true;
    });
    return out;
  }

  Future<LiveMarkdownController> pump(WidgetTester t, String text) async {
    final c = LiveMarkdownController(text: text, dark: false);
    addTearDown(c.dispose);
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox(
          width: 600,
          child: TextField(controller: c, maxLines: null),
        ),
      ),
    ));
    await t.pumpAndSettle();
    return c;
  }

  /// The equation atom, which is the one every block of maths notes has a
  /// hundred of. Identified by position rather than type so the test does not
  /// need the library's private widget classes.
  Widget mathAtom(List<Widget> atoms) => atoms.first;

  group('the same atom comes back', () {
    testWidgets('two builds with nothing changed hand back one instance',
        (t) async {
      final c = await pump(t, r'Energy $E=mc^2$ is the claim');
      final first = atomsOf(t, c);
      final second = atomsOf(t, c);
      expect(first, hasLength(1), reason: 'precondition: one equation');
      expect(identical(mathAtom(first), mathAtom(second)), isTrue,
          reason: 'rebuilding the paragraph must not rebuild the equation');
    });

    testWidgets('typing AFTER an atom keeps it — the common case', (t) async {
      // Writing at the end of a block is what writing normally is, and it
      // leaves every atom above the caret exactly where it was.
      final c = await pump(t, r'Energy $E=mc^2$ is the claim');
      final before = mathAtom(atomsOf(t, c));

      c.value = TextEditingValue(
        text: '${c.text}!',
        selection: TextSelection.collapsed(offset: c.text.length + 1),
      );
      await t.pump();

      expect(identical(mathAtom(atomsOf(t, c)), before), isTrue,
          reason: 'this is the whole performance property: a keystroke after '
              'the maths must not rebuild the maths');
    });

    testWidgets('a hundred equations survive a keystroke at the end',
        (t) async {
      final eqs = List.generate(100, (i) => r'$x_' '$i' r'$').join(' ');
      final c = await pump(t, 'Notes $eqs tail');
      final before = atomsOf(t, c);
      expect(before, hasLength(100), reason: 'precondition');

      c.value = TextEditingValue(
        text: '${c.text}x',
        selection: TextSelection.collapsed(offset: c.text.length + 1),
      );
      await t.pump();

      final after = atomsOf(t, c);
      expect(after, hasLength(100));
      var kept = 0;
      for (var i = 0; i < 100; i++) {
        if (identical(before[i], after[i])) kept++;
      }
      expect(kept, 100,
          reason: 'every one of them, or the cost comes straight back');
    });
  });

  group('and a stale atom never does', () {
    testWidgets('typing BEFORE an atom rebuilds it, because it moved',
        (t) async {
      // The dangerous half. The atom's callbacks captured the offsets it was
      // built at; if the text above it grows and the widget survives, those
      // callbacks write to the wrong place — a corrupted note, not a slow
      // one. Correctness beats the cache here, every time.
      final c = await pump(t, r'Energy $E=mc^2$ is the claim');
      final before = mathAtom(atomsOf(t, c));

      c.value = const TextEditingValue(
        text: r'XXEnergy $E=mc^2$ is the claim',
        selection: TextSelection.collapsed(offset: 2),
      );
      await t.pump();

      expect(identical(mathAtom(atomsOf(t, c)), before), isFalse,
          reason: 'it sits at a different offset now, so the one holding the '
              'old offsets must not be reused');
    });

    testWidgets('changing the equation itself rebuilds it', (t) async {
      final c = await pump(t, r'Energy $E=mc^2$ is the claim');
      final before = mathAtom(atomsOf(t, c));

      c.value = const TextEditingValue(
        text: r'Energy $E=mc^3$ is the claim',
        selection: TextSelection.collapsed(offset: 13),
      );
      await t.pump();

      expect(identical(mathAtom(atomsOf(t, c)), before), isFalse,
          reason: 'a cached atom that ignored its own content would draw the '
              'old equation for ever');
    });

    testWidgets('switching theme rebuilds every atom', (t) async {
      // The style an atom is drawn in is not in the text, so nothing about
      // the buffer changes when the theme does. Without the clear, every
      // picture and equation stayed in the old theme until its text moved.
      final c = await pump(t, r'Energy $E=mc^2$ is the claim');
      final before = mathAtom(atomsOf(t, c));

      c.dark = true;
      await t.pump();

      expect(identical(mathAtom(atomsOf(t, c)), before), isFalse);
    });

    testWidgets('setting the same theme again changes nothing', (t) async {
      final c = await pump(t, r'Energy $E=mc^2$ is the claim');
      final before = mathAtom(atomsOf(t, c));
      c.dark = false; // already false
      await t.pump();
      expect(identical(mathAtom(atomsOf(t, c)), before), isTrue,
          reason: 'a no-op setter must not throw the cache away');
    });
  });

  group('the cache cannot grow without limit', () {
    testWidgets('a long edit in a block full of atoms stays bounded',
        (t) async {
      // Keys move with the text, so an entry becomes garbage the moment its
      // offset changes. Typing at the START of a block full of equations
      // makes a fresh key for every atom on every keystroke — the worst case
      // there is, and the one that would grow for ever unbounded.
      final eqs = List.generate(20, (i) => r'$y_' '$i' r'$').join(' ');
      final c = await pump(t, 'head $eqs tail');
      for (var i = 0; i < 40; i++) {
        c.value = TextEditingValue(
          text: 'z${c.text}',
          selection: const TextSelection.collapsed(offset: 1),
        );
        await t.pump();
        atomsOf(t, c);
      }
      expect(c.debugAtomCacheSize, lessThanOrEqualTo(257),
          reason: '20 atoms x 40 keystrokes is 800 distinct keys; unbounded '
              'this would hold all of them');
      // And it still works after a clear.
      expect(atomsOf(t, c), hasLength(20));
    });
  });
}
