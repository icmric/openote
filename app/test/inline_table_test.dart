// A table inside a paragraph: the same grid, in the same place, typed into
// where it sits.
//
// v0.19 Step 2. What this pins, in the order it matters:
//
//  * **Nothing moves.** The requirement was exact — "i want to be able to
//    just click in a cell and start editing it in place with nothing moving
//    or changing" — so the read and the written halves of a cell are measured
//    against each other, to the pixel. Two widgets draw a cell (a Text.rich
//    and a TextField, for reasons in inline_table.dart); this is what stops
//    them drifting.
//  * **The buffer is untouched.** An atom stands on ONE code unit with the
//    rest of its reference hidden behind it, so every caret offset in the
//    paragraph is exactly where it was. A table that quietly moved the text
//    around it would corrupt notes, not merely look wrong.
//  * **A table is one thing.** Backspace after it deletes the table, not the
//    last character of its id — a half-eaten reference spills forty
//    characters of URL into the sentence and strands the payload.
//  * **It is built once.** The performance property the whole feature rests
//    on: typing in the paragraph must not rebuild the table, and typing in a
//    cell must not rebuild it either.
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/inline_atom_view.dart';
import 'package:openote/editor/inline_table.dart';
import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/markdown/md_render.dart';
import 'package:openote/model/inline_atom.dart';
import 'package:openote/theme/onote_theme.dart';

void main() {
  /// A block's content, standing in for the real one. The host reads and
  /// writes it exactly as `blockAtomHost` reads and writes a Block's.
  late Map<String, dynamic> content;
  late ValueNotifier<int> revision;
  var writes = 0;
  var undoSteps = 0;

  setUp(() {
    writes = 0;
    undoSteps = 0;
    revision = ValueNotifier(0);
    content = <String, dynamic>{
      'text': 'Results: ![2x2 table](onote://atom/t1) and it holds.',
      'atoms': {
        't1': {
          'id': 't1',
          'type': 'table',
          'content': {
            'cells': [
              ['Term', 'Meaning'],
              ['a', 'b'],
            ]
          }
        }
      },
    };
  });

  tearDown(() => revision.dispose());

  InlineAtomHost host({bool editable = true, void Function(String)? onExit}) =>
      InlineAtomHost(
        atoms: () => InlineAtom.allIn(content),
        write: (id, c, {required bool pushUndo}) {
          writes++;
          if (pushUndo) undoSteps++;
          final was = InlineAtom.allIn(content)[id];
          InlineAtom.putIn(content,
              InlineAtom(id: id, type: was?.type ?? 'table', content: c));
        },
        editable: editable,
        revision: revision,
        onExit: onExit,
      );

  TableData stored() =>
      TableData.from(InlineAtom.allIn(content)['t1']!.content);

  Widget frame(Widget child) => MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        // **On a desktop platform, because the shipped app is one.**
        // `AdaptiveTextSelectionToolbar` is adaptive: the Android form
        // paginates into a "more" button, so half of the table's own menu
        // would sit behind an overflow that nobody on Windows, macOS or
        // Linux ever sees — and the test would be asserting about a menu
        // no user has.
        theme: onoteTheme(Brightness.light)
            .copyWith(platform: TargetPlatform.windows),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 600, child: child),
          ),
        ),
      );

  /// The paragraph, live, with the table in it.
  Future<LiveMarkdownController> editor(WidgetTester t,
      {InlineAtomHost? h}) async {
    final c = LiveMarkdownController(text: content['text'] as String, dark: false)
      ..atomHost = h ?? host();
    addTearDown(c.dispose);
    await t.pumpWidget(frame(TextField(
                  controller: c,
                  maxLines: null,
                  style: const TextStyle(fontSize: 14),
                  // The engine's own strut. NON-forced is load-bearing: a
                  // forced strut makes every line box exactly the base
                  // height, so a 68px table is drawn outside the field.
                  strutStyle: StrutStyle.fromTextStyle(
                      const TextStyle(fontSize: 14),
                      forceStrutHeight: false))));
    await t.pumpAndSettle();
    return c;
  }

  /// The same paragraph, read.
  Future<void> reader(WidgetTester t, {InlineAtomHost? h}) async {
    await t.pumpWidget(frame(MarkdownView(
      text: content['text'] as String,
      baseStyle: const TextStyle(fontSize: 14),
      atomHost: h ?? host(editable: false),
    )));
    await t.pumpAndSettle();
  }

  group('the table is drawn where the reference is', () {
    testWidgets('in the live editor, as a table and not as a URL', (t) async {
      final c = await editor(t);
      expect(find.byType(Table), findsOneWidget);
      // The buffer still holds the reference — that is the point — so what
      // is asserted is that it is not DRAWN: every character of it beyond
      // the one the table stands on is laid out at a hairline.
      final hidden = <double>[];
      c
          .buildTextSpan(
              context: t.element(find.byType(TextField).first),
              style: const TextStyle(fontSize: 14),
              withComposing: false)
          .visitChildren((sp) {
        if (sp is TextSpan && (sp.text ?? '').contains('onote://atom')) {
          hidden.add(sp.style?.fontSize ?? 14);
        }
        return true;
      });
      expect(hidden, [0.01],
          reason: 'the reference is drawn behind the table it stands for, '
              'not beside it');
    });

    testWidgets('and in the read view, from the same call', (t) async {
      await reader(t);
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('Meaning', findRichText: true), findsOneWidget);
    });

    testWidgets('the paragraph around it still reads as prose', (t) async {
      await editor(t);
      // The words before and after the table are untouched — an atom is a
      // word in the sentence, not a replacement for it.
      expect(find.textContaining('Results:', findRichText: true),
          findsOneWidget);
    });

    testWidgets('a reference with no payload falls back to its alt text',
        (t) async {
      content.remove('atoms');
      await editor(t);
      expect(find.byType(Table), findsNothing);
      expect(find.text('2x2 table', findRichText: true), findsOneWidget,
          reason: 'which is what an older build, an export or somebody '
              'else\'s Markdown viewer shows, and why the alt text says what '
              'the thing IS');
    });

    testWidgets('an atom type this build never heard of draws a box, not a gap',
        (t) async {
      (content['atoms'] as Map)['t1'] = {
        'id': 't1',
        'type': 'hologram',
        'content': {'madeIn': '9.9.9', 'spin': 3},
      };
      await editor(t);
      expect(find.textContaining('9.9.9'), findsOneWidget,
          reason: 'a newer version made it, and the box says so');
      expect(find.byType(Table), findsNothing);
      // And nothing about looking at it may damage it.
      expect(InlineAtom.allIn(content)['t1']!.content['spin'], 3);
      expect(writes, 0);
    });
  });

  group('the paragraph underneath is untouched', () {
    testWidgets('every code unit of the reference is still in the buffer',
        (t) async {
      final c = await editor(t);
      expect(c.text, content['text'],
          reason: 'drawing a table must not rewrite the note');
    });

    testWidgets('the spans cover the raw text exactly', (t) async {
      // The invariant everything rests on: N code units of source, N laid
      // out. The controller re-proves it on every keystroke and silently
      // falls back to unstyled text if it fails — so a broken atom would
      // show up as "the styling just stopped", not as a crash.
      final c = await editor(t);
      final span = c.buildTextSpan(
        context: t.element(find.byType(TextField).first),
        style: const TextStyle(fontSize: 14),
        withComposing: false,
      );
      final buf = StringBuffer();
      void walk(InlineSpan s) {
        if (s is TextSpan) {
          if (s.text != null) buf.write(s.text);
          s.children?.forEach(walk);
        }
      }

      // A placeholder stands for one character of source; the rest trails as
      // hidden text, and the two together must be the reference.
      var placeholders = 0;
      span.visitChildren((s) {
        if (s is WidgetSpan) placeholders++;
        return true;
      });
      walk(span);
      expect(placeholders, 1);
      expect(buf.length + placeholders, c.text.length,
          reason: 'one code unit per placeholder, and every other character '
              'accounted for');
    });

    testWidgets('the caret crosses the whole reference in one step', (t) async {
      final c = await editor(t);
      final at = InlineAtom.rangeIn(c.text, 't1')!;
      // Sitting just past the table, moving left: the caret must land at the
      // reference's first character, not inside forty invisible ones.
      c.value = TextEditingValue(
        text: c.text,
        selection: TextSelection.collapsed(offset: at.end),
      );
      c.value = c.value.copyWith(
          selection: TextSelection.collapsed(offset: at.end - 1));
      expect(c.selection.baseOffset, at.start + 1,
          reason: 'one step over the whole atom — otherwise Left inside a '
              'sentence gives forty dead keystrokes');
    });
  });

  group('deleting it', () {
    testWidgets('Backspace just after a table deletes the table', (t) async {
      final c = await editor(t);
      final at = InlineAtom.rangeIn(c.text, 't1')!;
      final next = c.markerAwareDelete(
        TextEditingValue(
            text: c.text,
            selection: TextSelection.collapsed(offset: at.end)),
        forward: false,
      );
      expect(next, isNotNull,
          reason: 'the platform default would eat the closing bracket and '
              'spill the URL into the sentence');
      expect(next!.text, 'Results:  and it holds.');
      expect(InlineAtom.idsIn(next.text), isEmpty);
    });

    testWidgets('Delete just before it takes the whole thing too', (t) async {
      final c = await editor(t);
      final at = InlineAtom.rangeIn(c.text, 't1')!;
      final next = c.markerAwareDelete(
        TextEditingValue(
            text: c.text,
            selection: TextSelection.collapsed(offset: at.start)),
        forward: true,
      );
      expect(next!.text, 'Results:  and it holds.');
    });

    testWidgets('and the payload is remembered, so a paste brings it back',
        (t) async {
      // Cut-and-paste is the reason pruning cannot simply drop a payload the
      // moment its reference goes: the clipboard carries the text and
      // nothing else.
      final c = await editor(t);
      final at = InlineAtom.rangeIn(c.text, 't1')!;
      final cut = c.markerAwareDelete(
        TextEditingValue(
            text: c.text,
            selection: TextSelection.collapsed(offset: at.end)),
        forward: false,
      )!;

      final morgue = <String, InlineAtom>{};
      reconcileAtoms(content, cut.text, remember: (a) => morgue[a.id] = a);
      expect(content.containsKey('atoms'), isFalse);
      expect(morgue['t1']!.content['cells'], isNotNull);

      // …and pasted back, into this block or another one.
      final pasted = <String, dynamic>{'text': 'later: ${at.start >= 0 ? '' : ''}'
          '![2x2 table](onote://atom/t1)'};
      reconcileAtoms(pasted, pasted['text'] as String,
          recall: (id) => morgue[id]);
      expect(TableData.from(InlineAtom.allIn(pasted)['t1']!.content).cells, [
        ['Term', 'Meaning'],
        ['a', 'b'],
      ]);
    });
  });

  group('typing in a cell', () {
    testWidgets('writes to the payload and leaves the paragraph alone',
        (t) async {
      final c = await editor(t);
      final before = c.text;
      await t.tap(find.byType(TextField).at(1)); // the paragraph is .at(0)
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).at(1), 'Ampere');
      await t.pumpAndSettle();

      expect(stored().cells[0][0], 'Ampere');
      expect(c.text, before,
          reason: 'a cell edit changes the payload, never the buffer — the '
              'reference and every offset after it must not move');
    });

    testWidgets('a burst of typing is ONE undo step', (t) async {
      await editor(t);
      final field = find.byType(TextField).at(1);
      await t.tap(field);
      await t.pumpAndSettle();
      for (final s in ['A', 'Am', 'Amp']) {
        await t.enterText(field, s);
        await t.pump();
      }
      expect(writes, 3);
      expect(undoSteps, 1,
          reason: 'forty undo steps for a typed sentence is not an undo '
              'stack, it is a transcript');
    });

    testWidgets('a cell tells the host it has the keyboard', (t) async {
      var holding = false;
      final c = LiveMarkdownController(
          text: content['text'] as String, dark: false)
        ..atomHost = InlineAtomHost(
          atoms: () => InlineAtom.allIn(content),
          write: (id, c, {required bool pushUndo}) {},
          editable: true,
          revision: revision,
          onKeyboard: (v) => holding = v,
        );
      addTearDown(c.dispose);
      await t.pumpWidget(frame(TextField(
                  controller: c,
                  maxLines: null,
                  style: const TextStyle(fontSize: 14),
                  // The engine's own strut. NON-forced is load-bearing: a
                  // forced strut makes every line box exactly the base
                  // height, so a 68px table is drawn outside the field.
                  strutStyle: StrutStyle.fromTextStyle(
                      const TextStyle(fontSize: 14),
                      forceStrutHeight: false))));
      await t.pumpAndSettle();

      await t.tap(find.byType(TextField).at(1));
      await t.pumpAndSettle();
      expect(holding, isTrue,
          reason: 'the host stands its caret, its key handling and its '
              'context menu down while a cell has the keyboard');
    });

    testWidgets('Escape hands the keyboard back', (t) async {
      String? left;
      await editor(t, h: host(onExit: (id) => left = id));
      await t.tap(find.byType(TextField).at(1));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(left, 't1');
    });

    testWidgets('Tab moves to the next cell, and off the end it leaves',
        (t) async {
      String? left;
      await editor(t, h: host(onExit: (id) => left = id));
      // Last cell of the last row: Tab wraps forward, finds no row, and
      // gives the paragraph its keyboard back rather than trapping it.
      await t.tap(find.byType(TextField).at(4));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      expect(left, 't1', reason: 'a table you cannot Tab out of is a trap');
    });
  });

  group('the right-click menu', () {
    testWidgets('inserts a row below the cell that was clicked', (t) async {
      await editor(t);
      final cell = find.byType(TextField).at(1); // row 0, col 0
      await t.tapAt(t.getCenter(cell), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      expect(find.text('Insert row below'), findsOneWidget);
      await t.tap(find.text('Insert row below'));
      await t.pumpAndSettle();

      expect(stored().cells, [
        ['Term', 'Meaning'],
        ['', ''],
        ['a', 'b'],
      ], reason: 'below the CLICKED cell — the old buttons could only append, '
          'so inserting in the middle meant retyping everything under it');
    });

    testWidgets('inserts a column to the right of it', (t) async {
      await editor(t);
      await t.tapAt(t.getCenter(find.byType(TextField).at(1)),
          buttons: kSecondaryButton);
      await t.pumpAndSettle();
      await t.tap(find.text('Insert column right'));
      await t.pumpAndSettle();
      expect(stored().cells, [
        ['Term', '', 'Meaning'],
        ['a', '', 'b'],
      ]);
    });

    testWidgets('the last row and the last column cannot be deleted',
        (t) async {
      (content['atoms'] as Map)['t1'] = {
        'id': 't1',
        'type': 'table',
        'content': {
          'cells': [
            ['only']
          ]
        }
      };
      await editor(t);
      await t.tapAt(t.getCenter(find.byType(TextField).at(1)),
          buttons: kSecondaryButton);
      await t.pumpAndSettle();
      final bar = t.widget<AdaptiveTextSelectionToolbar>(
          find.byType(AdaptiveTextSelectionToolbar));
      final del =
          bar.buttonItems!.firstWhere((b) => b.label == 'Delete row');
      expect(del.onPressed, isNull,
          reason: 'a table with no rows cannot be typed into, so removing '
              'the last one would be a one-way door');
    });
  });

  group('nothing moves when you click into it', () {
    // **The requirement, measured.** Two widgets draw a cell — a Text.rich
    // and a TextField — so the only way to know they agree is to build the
    // same table both ways and compare.
    //
    // The case that drove the design is the empty one. A field carrying no
    // glyphs lays out at its strut's full box (22px for 13px text) while the
    // same cell read as text lays out at 18, so an empty row used to grow by
    // 4px under the pointer that opened it; a cell holding nothing but an
    // equation grew by 1. Both are fixed by taking that measured number as
    // the row's minimum height, and both would come straight back the moment
    // somebody "tidied" it into a constant — hence the cases below.
    Future<Size> measure(
        WidgetTester t, List<List<String>> cells, bool editable) async {
      final data = TableData.from({
        'cells': cells,
        'colWidths': [140, 200],
      });
      await t.pumpWidget(frame(InlineTable(
        binding: TableBinding(
            read: () => data, write: (_, {required bool pushUndo}) {}),
        editable: editable,
        style: const TextStyle(fontSize: 13),
        dark: false,
      )));
      await t.pumpAndSettle();
      return t.getSize(find.byType(Table));
    }

    final cases = <String, List<List<String>>>{
      'plain text': [
        ['a']
      ],
      'an empty cell': [
        ['']
      ],
      'an equation alone in a cell': [
        [r'$x^2$']
      ],
      'bold, whose markers are hidden on both sides': [
        ['**bold**']
      ],
      'a line long enough to wrap': [
        ['a rather longer line that will certainly wrap more than once here']
      ],
      'a real table of all of them': [
        ['Term', 'Meaning'],
        [r'$x^2$', ''],
        ['**b**', 'plain words'],
      ],
    };

    cases.forEach((name, cells) {
      testWidgets('$name is the same size read and written', (t) async {
        final read = await measure(t, cells, false);
        final written = await measure(t, cells, true);
        expect(written, read,
            reason: 'clicking into a cell may not move one pixel of the '
                'table, the box it is in, or the text below it');
      });
    });
  });

  group('it is built once', () {
    /// Every widget the controller put in the paragraph.
    List<Widget> atomsOf(WidgetTester t, LiveMarkdownController c) {
      final span = c.buildTextSpan(
        context: t.element(find.byType(TextField).first),
        style: const TextStyle(fontSize: 14),
        withComposing: false,
      );
      final out = <Widget>[];
      span.visitChildren((s) {
        if (s is WidgetSpan) out.add(s.child);
        return true;
      });
      return out;
    }

    testWidgets('typing after the table does not rebuild the table',
        (t) async {
      final c = await editor(t);
      final before = atomsOf(t, c).single;
      c.value = TextEditingValue(
        text: '${c.text}!',
        selection: TextSelection.collapsed(offset: c.text.length + 1),
      );
      await t.pump();
      expect(identical(atomsOf(t, c).single, before), isTrue,
          reason: 'the whole performance property: a keystroke in the '
              'sentence must not rebuild a widget holding a dozen fields');
    });

    testWidgets('and neither does typing INSIDE the table', (t) async {
      final c = await editor(t);
      final before = atomsOf(t, c).single;
      await t.tap(find.byType(TextField).at(1));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).at(1), 'Ampere');
      await t.pumpAndSettle();
      expect(identical(atomsOf(t, c).single, before), isTrue,
          reason: 'the cache is keyed on the atom id, not its contents — '
              'keying on the cells would destroy the field being typed into '
              'on every keystroke');
    });

    testWidgets('typing BEFORE it keeps it too, because nothing moved',
        (t) async {
      // Unlike an equation, whose callbacks capture offsets, a table writes
      // to its payload by id. Text above it moving is not a reason to throw
      // it away — and throwing it away would lose the cell being typed in.
      final c = await editor(t);
      final before = atomsOf(t, c).single;
      c.value = TextEditingValue(
        text: 'XX${c.text}',
        selection: const TextSelection.collapsed(offset: 2),
      );
      await t.pump();
      expect(identical(atomsOf(t, c).single, before), isTrue);
    });
  });

  group('column widths', () {
    testWidgets('a stored width is used exactly, uncapped', (t) async {
      (content['atoms'] as Map)['t1'] = {
        'id': 't1',
        'type': 'table',
        'content': {
          'cells': [
            ['a', 'b']
          ],
          'colWidths': [kTableColumnCap + 180, 0],
        }
      };
      await editor(t);
      final table = t.widget<Table>(find.byType(Table));
      final w = table.columnWidths![0] as FixedColumnWidth;
      expect(w.value, kTableColumnCap + 180,
          reason: 'a width somebody dragged is chosen; the cap is only for '
              'the width nobody chose');
    });

    testWidgets('an unset column fits its contents, up to the cap', (t) async {
      (content['atoms'] as Map)['t1'] = {
        'id': 't1',
        'type': 'table',
        'content': {
          'cells': [
            ['x', 'a sentence long enough to run past the cap several times '
                'over, on and on and on and on and on'],
          ]
        }
      };
      await editor(t);
      final table = t.widget<Table>(find.byType(Table));
      expect((table.columnWidths![0] as FixedColumnWidth).value,
          kTableColumnMin);
      expect((table.columnWidths![1] as FixedColumnWidth).value,
          kTableColumnCap);
    });
  });
}
