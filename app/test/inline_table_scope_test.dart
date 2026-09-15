// **A cell letting go of the caret must not let go of the TABLE.**
//
// The reported defect, after several rounds of fixes that each removed one
// way of losing the caret: *"when I press enter to make a new row it will
// create the row, put my cursor in there, but then kick the cursor out of the
// table. I can navigate back into it and type with no issues, it's just on
// creating a new row… I can create a column with no issues, just rows."*
//
// Eight tests reproduce the JOURNEY and pass, because in a harness the caret
// arrives and nothing takes it away again. The instrument on the owner's
// machine showed what those tests cannot: the new cell takes the caret and
// then goes quiet on its own a frame or two later — `anyFocused=false`,
// `leaveAtom` never called, the table never torn down.
//
// This file pins the property that makes that harmless, rather than any one
// theory about what releases the cell. A `FocusNode` that is detached,
// disposed, made unfocusable, or simply `unfocus()`ed does not leave the
// caret nowhere: Flutter hands it to the nearest enclosing `FocusScope`. The
// table now owns that scope, so the caret lands back in the table instead of
// out on the page — where the paragraph's post-build hook would find a block
// being edited with nothing focused inside it and claim the keyboard, which
// is the "beside the table" the owner sees.
//
// `unfocus()` stands in for the whole class here, because every one of those
// mechanisms ends in exactly that call inside the framework.
//
// **Why a row and not a column**, which is the clue that named the fix: the
// heading row's cells carry a `GlobalKey` (they are measured for the column
// drag handles), and a GlobalKey'd element survives a rebuild from above with
// its focus node intact. No other row has one. Same code path, same
// keystroke, different outcome — so the column half of the report is not a
// second bug, it is the control group.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/inline_atom_view.dart';
import 'package:openote/editor/inline_table.dart';
import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/inline_atom.dart';
import 'package:openote/theme/onote_theme.dart';

void main() {
  late Map<String, dynamic> content;
  late ValueNotifier<int> revision;
  late FocusNode paragraph;
  late List<bool> keyboard;
  late List<String> exits;

  setUp(() {
    revision = ValueNotifier(0);
    paragraph = FocusNode(debugLabel: 'paragraph');
    keyboard = [];
    exits = [];
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

  tearDown(() {
    revision.dispose();
    paragraph.dispose();
  });

  InlineAtomHost host({bool editable = true}) => InlineAtomHost(
        atoms: () => InlineAtom.allIn(content),
        write: (id, c, {required bool pushUndo}) {
          final was = InlineAtom.allIn(content)[id];
          InlineAtom.putIn(content,
              InlineAtom(id: id, type: was?.type ?? 'table', content: c));
        },
        editable: editable,
        revision: revision,
        onKeyboard: keyboard.add,
        // What the real host does with an exit: puts the caret back in the
        // sentence. Recorded as well, so a test can tell an exit that was
        // ASKED for from a caret that merely went missing.
        onExit: (id) {
          exits.add(id);
          paragraph.requestFocus();
        },
      );

  TableData stored() =>
      TableData.from(InlineAtom.allIn(content)['t1']!.content);

  Widget frame(Widget child) => MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        theme: onoteTheme(Brightness.light)
            .copyWith(platform: TargetPlatform.windows),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 600, child: child),
          ),
        ),
      );

  /// The paragraph the table sits in, live — a real `TextField` over a real
  /// `LiveMarkdownController`, which is the arrangement that makes a cell a
  /// field nested inside a field.
  Future<LiveMarkdownController> editor(WidgetTester t,
      {bool editable = true}) async {
    final c =
        LiveMarkdownController(text: content['text'] as String, dark: false)
          ..atomHost = host(editable: editable);
    addTearDown(c.dispose);
    await t.pumpWidget(frame(TextField(
      controller: c,
      focusNode: paragraph,
      maxLines: null,
      style: const TextStyle(fontSize: 14),
      // The engine's own answer to "a tap on the sentence is a tap OUT of the
      // table" (live_markdown_engine.dart). A host's node reports `hasFocus`
      // the whole time a cell holds the keyboard, so `EditableText` never
      // asks for focus on its own and the click would do nothing at all.
      onTap: () {
        if (paragraph.hasFocus && !paragraph.hasPrimaryFocus) {
          paragraph.requestFocus();
        }
      },
      strutStyle: StrutStyle.fromTextStyle(const TextStyle(fontSize: 14),
          forceStrutHeight: false),
    )));
    await t.pumpAndSettle();
    return c;
  }

  /// Every cell, in reading order. The paragraph's own field is excluded by
  /// the focus node's label, which only a cell carries.
  Finder cells() => find.byWidgetPredicate(
      (w) => w is TextField && w.focusNode?.debugLabel == 'tableCell');

  bool caretInACell() =>
      FocusManager.instance.primaryFocus?.debugLabel == 'tableCell';

  /// Whatever released the cell, the caret must not have left the paragraph:
  /// that is the condition `live_markdown_engine.dart`'s post-build hook
  /// tests before it claims the keyboard, and the whole of why the letters
  /// end up in the sentence.
  bool stillInsideTheParagraph() => paragraph.hasFocus;

  group('a cell that lets go of the caret', () {
    testWidgets('hands it back to the TABLE, not out to the page', (t) async {
      await editor(t);
      await t.tap(cells().at(3)); // the last cell: row 1, column 1
      await t.pumpAndSettle();
      expect(caretInACell(), isTrue, reason: 'precondition: clicking in works');

      // THE FAILURE, forced. On the owner's machine something inside the
      // framework does this a frame or two after a row is made; here it is
      // done outright, because the property is about the CONSEQUENCE.
      FocusManager.instance.primaryFocus!.unfocus();
      await t.pumpAndSettle();

      expect(caretInACell(), isTrue,
          reason: 'the caret must come back to the cell it was in, rather '
              'than be handed to the enclosing page scope');
      expect(stillInsideTheParagraph(), isTrue);
      expect(exits, isEmpty, reason: 'and nobody asked to leave the table');
    });

    testWidgets('never tells the host the keyboard is free on the way',
        (t) async {
      await editor(t);
      await t.tap(cells().at(3));
      await t.pumpAndSettle();
      expect(keyboard.last, isTrue, reason: 'precondition: the table has it');
      final before = keyboard.length;

      FocusManager.instance.primaryFocus!.unfocus();
      await t.pumpAndSettle();

      expect(keyboard.skip(before), isNot(contains(false)),
          reason: 'one frame of a stale "the keyboard is free" is all the '
              'paragraph needs to take the caret back');
      expect(keyboard.last, isTrue);
    });

    testWidgets('and the row Enter just made is where it comes back to',
        (t) async {
      await editor(t);
      await t.tap(cells().at(3));
      await t.pumpAndSettle();

      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(stored().rows, 3, reason: 'precondition: the row was made');
      expect(caretInACell(), isTrue);

      FocusManager.instance.primaryFocus!.unfocus();
      await t.pumpAndSettle();

      expect(caretInACell(), isTrue);
      expect(cells(), findsNWidgets(6));
      // The LAST cell, which is the one Enter asked for — not merely some
      // cell. "It put my cursor in there and then kicked it out" is only
      // fixed if what comes back is the row that was just made.
      final back = t.widgetList<TextField>(cells()).last.focusNode!;
      expect(back.hasPrimaryFocus, isTrue,
          reason: 'the caret belongs in the new row, not wherever the '
              'framework happened to leave it');
    });
  });

  group('but the scope never traps a keyboard it was not given', () {
    testWidgets('Escape still hands the caret back to the paragraph',
        (t) async {
      await editor(t);
      await t.tap(cells().at(3));
      await t.pumpAndSettle();
      expect(caretInACell(), isTrue);

      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();

      expect(exits, ['t1'], reason: 'the table asked to be left');
      expect(caretInACell(), isFalse,
          reason: 'a deliberate exit is not a cell letting go by accident, '
              'and the scope must not drag the caret back');
      expect(paragraph.hasPrimaryFocus, isTrue);
      expect(keyboard.last, isFalse,
          reason: 'the host has to learn the keyboard is its own again, or a '
              'paragraph that cannot be typed into is the next bug');
    });

    testWidgets('clicking into the sentence takes the caret out', (t) async {
      await editor(t);
      await t.tap(cells().at(3));
      await t.pumpAndSettle();
      expect(caretInACell(), isTrue);

      // The words before the table: a click there is the person choosing the
      // paragraph, and it has to win.
      await t.tapAt(
          t.getTopLeft(find.byType(TextField).first) + const Offset(12, 10));
      await t.pumpAndSettle();

      expect(caretInACell(), isFalse);
      expect(paragraph.hasPrimaryFocus, isTrue);
      expect(keyboard.last, isFalse);
    });

    testWidgets('a table being READ holds no scope at all', (t) async {
      // A read-only table has no cells to put a caret in, so a scope around
      // one could only ever swallow a keyboard nobody meant it to have.
      await editor(t, editable: false);

      expect(find.byType(Table), findsOneWidget, reason: 'it is still drawn');
      expect(cells(), findsNothing);
      expect(
          find.descendant(
              of: find.byType(InlineTable), matching: find.byType(FocusScope)),
          findsNothing);
    });
  });
}
