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

  group('a table on a line of its own', () {
    // **The shape every converted table actually has**, and the one that was
    // broken: `![2x2 table](onote://atom/t1)` alone on a line is matched by
    // the LINE grammar's picture pattern as well as by the inline atom
    // pattern, because the two dialects share a shape and only the scheme
    // tells them apart. The picture branch won, found no blob, and drew the
    // reference as dim text — so every table the converter produced would
    // have rendered as a line of punctuation.
    setUp(() => content['text'] = '![2x2 table](onote://atom/t1)');

    testWidgets('draws as a table in the live editor', (t) async {
      await editor(t);
      expect(find.byType(Table), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(5),
          reason: 'the paragraph, and one field per cell');
    });

    testWidgets('and as a table in the read view', (t) async {
      await reader(t);
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('Meaning', findRichText: true), findsOneWidget);
    });

    testWidgets('and the caret still crosses it in one step', (t) async {
      // The hidden run has to be registered for a line-anchored atom too, or
      // Left inside the paragraph gives thirty dead keystrokes.
      final c = await editor(t);
      c.value = TextEditingValue(
        text: c.text,
        selection: TextSelection.collapsed(offset: c.text.length),
      );
      c.value = c.value.copyWith(
          selection: TextSelection.collapsed(offset: c.text.length - 1));
      expect(c.selection.baseOffset, 0,
          reason: 'all the way over, to BEFORE it. This used to answer 1 - '
              'between the exclamation mark and the bracket - which is the '
              'one offset in the whole reference that must never hold a '
              'caret: the next keystroke there ends the table');
    });

    testWidgets('and text typed after it stays on the line after it',
        (t) async {
      final c = await editor(t);
      c.value = TextEditingValue(
        text: '${c.text}\nand then some words',
        selection: const TextSelection.collapsed(offset: 0),
      );
      await t.pumpAndSettle();
      expect(find.byType(Table), findsOneWidget);
      expect(find.textContaining('and then some words', findRichText: true),
          findsOneWidget);
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
      expect(c.selection.baseOffset, at.start,
          reason: 'one step over the whole atom — otherwise Left inside a '
              'sentence gives forty dead keystrokes');
    });
  });

  group('you cannot type inside it', () {
    // **The owner, and it is hard to put better:** *"if my cursor is right
    // next to the end of the table and i type or press space or anything, it
    // seems to insert it into the thing that renders the table so the hash
    // comes up and the table disapears. This is very bad, this should never be
    // able to ever happen"*.
    //
    // Every offset from the reference's first character to its last is drawn
    // in the SAME place — hard against the table's right edge — because the
    // table stands on the first one and the other forty trail behind it at a
    // hairline. So `start + 1` looks exactly like "after the table" and is in
    // fact between the `!` and the `[`. One space there and the reference
    // stops matching: the table is gone, its payload is stranded with nothing
    // pointing at it, and the URL is in the sentence.

    testWidgets('Left from just past it lands BEFORE it, not inside',
        (t) async {
      final c = await editor(t);
      final at = InlineAtom.rangeIn(c.text, 't1')!;
      c.value = TextEditingValue(
          text: c.text, selection: TextSelection.collapsed(offset: at.end));
      c.value = c.value.copyWith(
          selection: TextSelection.collapsed(offset: at.end - 1));
      final off = c.selection.baseOffset;
      expect(off > at.start && off < at.end, isFalse,
          reason: 'there are two legal places for a caret on an object, and '
              'both of them are outside it');
      expect(off, at.start);
    });

    testWidgets('and a tap on the table lands in a cell, not in the sentence',
        (t) async {
      final c = await editor(t);
      c.value = TextEditingValue(
          text: c.text, selection: const TextSelection.collapsed(offset: 0));
      final box = t.getRect(find.byType(Table));
      // The bottom border: not a cell, not the paragraph — table chrome,
      // which fell through to the paragraph's own tap handler and put its
      // caret at the nearest offset going, which is inside the reference.
      await t.tapAt(Offset(box.center.dx, box.bottom - 1));
      await t.pumpAndSettle();

      expect(c.selection.baseOffset, 0,
          reason: 'the paragraph never saw the tap at all');
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tableCell',
          reason: 'and clicking a table puts you in the table');
    });

    testWidgets('an edit aimed straight at the middle of it is moved out',
        (t) async {
      final c = await editor(t);
      final at = InlineAtom.rangeIn(c.text, 't1')!;
      // No caret ever goes here now, so this is what is left: a paste, an IME
      // composition, or a platform update against a selection one frame old.
      c.value = TextEditingValue(
        text: c.text.replaceRange(at.start + 1, at.start + 1, ' '),
        selection: TextSelection.collapsed(offset: at.start + 2),
      );
      await t.pumpAndSettle();

      expect(InlineAtom.rangeIn(c.text, 't1'), isNotNull,
          reason: 'the reference is whole');
      expect(find.byType(Table), findsOneWidget,
          reason: 'and the table is still a table');
      expect(c.text, contains(') and it holds.'.replaceFirst(') ', ')  ')),
          reason: 'the space went after the object, which is where it looked '
              'like it was going');
    });

    testWidgets('and an edit that would eat half of it takes all of it',
        (t) async {
      final c = await editor(t);
      final at = InlineAtom.rangeIn(c.text, 't1')!;
      // A selection dragged from the middle of the reference out into the
      // sentence, then typed over.
      c.value = TextEditingValue(
        text: c.text.replaceRange(at.start + 4, at.end + 4, 'X'),
        selection: TextSelection.collapsed(offset: at.start + 5),
      );
      await t.pumpAndSettle();

      expect(c.text.contains(InlineAtom.scheme), isFalse,
          reason: 'half a reference is worse than none: forty characters of '
              'URL in the sentence and a payload nothing points at');
      expect(c.text, 'Results: X it holds.');
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

    testWidgets('Tab in the last cell makes a new row', (t) async {
      // How a table gets filled in: type, Tab, type, Tab. OneNote does this,
      // Word does this, every spreadsheet does this — and it is the other
      // half of the gesture that MADE the table in the first place.
      String? left;
      await editor(t, h: host(onExit: (id) => left = id));
      await t.tap(find.byType(TextField).at(4)); // last cell, last row
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();

      expect(stored().rows, 3);
      expect(left, isNull, reason: 'Tab fills a table in; it does not leave');
      final fields = t.widgetList<TextField>(find.byType(TextField)).toList();
      expect(fields[5].focusNode?.hasFocus, isTrue,
          reason: 'and the caret is in the first cell of the new row');
    });

    testWidgets('but an arrow off the bottom leaves, because that is leaving',
        (t) async {
      String? left;
      await editor(t, h: host(onExit: (id) => left = id));
      await t.tap(find.byType(TextField).at(4));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      expect(left, 't1', reason: 'a table you cannot get out of is a trap');
      expect(stored().rows, 2, reason: 'and no row was added on the way');
    });

    testWidgets('and Shift+Tab out of the first cell leaves too', (t) async {
      String? left;
      await editor(t, h: host(onExit: (id) => left = id));
      await t.tap(find.byType(TextField).at(1)); // row 0, col 0
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.tab, character: null);
      await t.pumpAndSettle();
      expect(stored().rows, 2, reason: 'precondition: Tab moved, not added');
      await t.tap(find.byType(TextField).at(1));
      await t.pumpAndSettle();
      await t.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await t.pumpAndSettle();
      expect(left, 't1');
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

  group('a change of shape keeps the caret', () {
    // **The defect these exist for**, in the owner's words: *"it then puts my
    // cursor outside the table, so rather than typing into the newly created
    // table, its typing out of it"*.
    //
    // Every structural change goes through `_restructure`, which used to
    // throw the whole grid away and build a new one. That disposed the focus
    // node holding the caret, and a `FocusNode` detached while it has the
    // focus hands it to the enclosing SCOPE — which gives it to the
    // paragraph. The caret was then put back post-frame, racing a teardown
    // already in flight; the frame it lost, the next word went into the
    // sentence beside the table.
    //
    // So these do not assert where the caret IS. They type, and assert where
    // the characters land — which is the only question the owner asked.

    /// The cells, in reading order. Field 0 is the paragraph itself.
    Finder cell(int i) => find.byType(TextField).at(i + 1);

    testWidgets('Tab off the end adds a row and types into it', (t) async {
      await editor(t);
      await t.tap(cell(3)); // the last cell of the 2x2
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      expect(stored().cells, [
        ['Term', 'Meaning'],
        ['a', 'b'],
        ['', ''],
      ]);

      // Typed at NOBODY in particular: this goes to whichever field holds the
      // platform's text-input connection, which is the whole question.
      t.testTextInput.enterText('Third');
      await t.pumpAndSettle();
      expect(stored().cells[2][0], 'Third',
          reason: 'type, Tab, type, Tab is how a table gets filled in — the '
              'row Tab just made has to be the one that is typed into');
    });

    testWidgets('and the menu leaves the keyboard in the table too', (t) async {
      await editor(t);
      await t.tap(cell(0));
      await t.pumpAndSettle();
      await t.tapAt(t.getCenter(cell(0)), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      await t.tap(find.text('Insert row below'));
      await t.pumpAndSettle();

      t.testTextInput.enterText('Middle');
      await t.pumpAndSettle();
      expect(stored().cells, [
        ['Term', 'Meaning'],
        ['Middle', ''],
        ['a', 'b'],
      ], reason: 'the menu asked for the new row, so that is where the '
          'keyboard belongs');
    });

    testWidgets('a cell that survives keeps the objects it had', (t) async {
      await editor(t);
      TextField at(int i) => t.widget<TextField>(cell(i));
      final ctl = at(0).controller, node = at(0).focusNode;
      await t.tap(cell(3));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();

      expect(identical(at(0).controller, ctl), isTrue);
      expect(identical(at(0).focusNode, node), isTrue,
          reason: 'a row added at the end disturbs nothing above it — and a '
              'focus node that is never detached is a caret that never has '
              'to be put back');
    });

    testWidgets('and the host is never told the keyboard is free mid-move',
        (t) async {
      // **The gap.** Rebuilding a grid puts a frame between the cell that had
      // the caret and the cell that is about to have it, and in that frame
      // nothing in the table is focused. Saying so hands the paragraph its
      // keyboard back — and the paragraph, on its next frame, claims the caret
      // it has just been told is free. The owner: *"it created the new row
      // below me, but put my cursor out of the table"*, and *"my suspicion is
      // some kind of race condition"*, which is exactly what it is: two
      // post-frame callbacks and a focus change that lands in a microtask
      // between them.
      //
      // Deleting the row the caret is in is the one shape of this that a test
      // can force: that cell really is retired, so the gap is certain rather
      // than a matter of timing.
      final said = <bool>[];
      final c =
          LiveMarkdownController(text: content['text'] as String, dark: false)
            ..atomHost = InlineAtomHost(
              atoms: () => InlineAtom.allIn(content),
              write: (id, v, {required bool pushUndo}) {
                final was = InlineAtom.allIn(content)[id];
                InlineAtom.putIn(content,
                    InlineAtom(id: id, type: was?.type ?? 'table', content: v));
              },
              editable: true,
              revision: revision,
              onKeyboard: said.add,
            );
      addTearDown(c.dispose);
      await t.pumpWidget(frame(TextField(
          controller: c,
          maxLines: null,
          style: const TextStyle(fontSize: 14),
          strutStyle: StrutStyle.fromTextStyle(const TextStyle(fontSize: 14),
              forceStrutHeight: false))));
      await t.pumpAndSettle();

      await t.tap(cell(2)); // row 1, col 0 — the row about to go
      await t.pumpAndSettle();
      expect(said, [true], reason: 'the cell has the keyboard');
      said.clear();

      await t.tapAt(t.getCenter(cell(2)), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      await t.tap(find.text('Delete row'));
      await t.pumpAndSettle();

      expect(said, isNot(contains(false)),
          reason: 'the caret is moving from one of this table\'s cells to '
              'another. It never left, and the paragraph must not be told it '
              'did — being told is what lets it take the caret. (It holds '
              'here because a retired node loses its listener before it is '
              'disposed; the guard exists for the orderings where it does '
              'not, which a fake clock cannot produce.)');
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tableCell',
          reason: 'and it arrived');
    });

    testWidgets('and a cell that does not is not left wired to the keyboard',
        (t) async {
      await editor(t);
      await t.tap(cell(2)); // row 1, col 0 — the row about to go
      await t.pumpAndSettle();
      await t.tapAt(t.getCenter(cell(2)), buttons: kSecondaryButton);
      await t.pumpAndSettle();
      await t.tap(find.text('Delete row'));
      await t.pumpAndSettle();

      expect(stored().cells, [
        ['Term', 'Meaning']
      ]);
      // The fields at those positions are now different objects. Without a
      // key on the focus node, `EditableText` would keep the platform
      // connection it opened for the row that has just been deleted.
      t.testTextInput.enterText('Kept');
      await t.pumpAndSettle();
      expect(stored().cells, hasLength(1),
          reason: 'nothing may be typed back into a row that is gone');
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

  group('the awkward places it can sit', () {
    testWidgets('on a list line, where the bullet hangs', (t) async {
      content['text'] = '- ![2x2 table](onote://atom/t1)';
      await editor(t);
      expect(find.byType(Table), findsOneWidget,
          reason: 'a list line hands its body to the same inline builder; a '
              'table in a bulleted list is an ordinary thing to write');
    });

    testWidgets('in a box too narrow for it, without overflowing', (t) async {
      // A table wider than its box used to paint a debug stripe across the
      // note and clip its last column. It scales to fit instead, and asks
      // the box to grow.
      (content['atoms'] as Map)['t1'] = {
        'id': 't1',
        'type': 'table',
        'content': {
          'cells': [
            ['a', 'b', 'c']
          ],
          'colWidths': [400, 400, 400],
        }
      };
      var asked = 0.0;
      final c = LiveMarkdownController(
          text: content['text'] as String, dark: false)
        ..atomHost = InlineAtomHost(
          atoms: () => InlineAtom.allIn(content),
          write: (id, v, {required bool pushUndo}) {},
          editable: true,
          revision: revision,
          onNeedWidth: (w) => asked = w,
        )
        ..layoutWidth = 300;
      addTearDown(c.dispose);
      await t.pumpWidget(frame(TextField(
          controller: c,
          maxLines: null,
          style: const TextStyle(fontSize: 14),
          strutStyle: StrutStyle.fromTextStyle(const TextStyle(fontSize: 14),
              forceStrutHeight: false))));
      await t.pumpAndSettle();

      expect(t.takeException(), isNull);
      expect(t.getSize(find.byType(Table)).width, lessThanOrEqualTo(300),
          reason: 'it fits the room it has');
      expect(asked, greaterThan(1000),
          reason: 'and says how much room it actually wanted, so the box can '
              'grow and give it back');
    });

    testWidgets('in a box too narrow for it while READ, which is worse',
        (t) async {
      // Worse because it is silent. A `RenderTable` given less room than its
      // fixed columns add up to does not complain and does not clip — it
      // draws the cells where they would have gone, over whatever is beside
      // the box. Measured before the read path knew its own width: three
      // 400px columns in a 300px box put cells at x=8, 408 and 808.
      (content['atoms'] as Map)['t1'] = {
        'id': 't1',
        'type': 'table',
        'content': {
          'cells': [
            ['a', 'b', 'c']
          ],
          'colWidths': [400, 400, 400],
        }
      };
      content['text'] = '![1x3 table](onote://atom/t1)';
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        theme: onoteTheme(Brightness.light),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              child: MarkdownView(
                text: content['text'] as String,
                baseStyle: const TextStyle(fontSize: 14),
                atomHost: host(editable: false),
              ),
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();

      expect(t.takeException(), isNull);
      final cells = find.byType(Text);
      for (var i = 0; i < cells.evaluate().length; i++) {
        expect(t.getTopLeft(cells.at(i)).dx, lessThan(300),
            reason: 'every cell inside the box it is drawn in');
      }
    });

    testWidgets('in the dark, drawn dark', (t) async {
      final c = await editor(t);
      final light = t.widget<Table>(find.byType(Table));
      // What a theme change does: the engine sets this on every build
      // (live_markdown_engine.dart:1127) and the field rebuilds around it.
      c.dark = true;
      c.refreshSpans();
      await t.pumpAndSettle();
      final dark = t.widget<Table>(find.byType(Table));
      expect(dark.border, isNot(light.border),
          reason: 'the style an atom is drawn in is not in the text, so the '
              'cache has to be cleared when the theme changes — without it '
              'every table stayed light until its line happened to move');
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
