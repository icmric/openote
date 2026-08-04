// Edit/view vertical parity: entering a text box must not change where lines
// sit.
//
// The two renderers are different machines — read is a Column of per-line
// widgets, edit is one TextField — but the user experiences them as ONE text
// box, and "the text slightly compresses when I click in" is what it feels
// like when their line boxes disagree. These tests measure both renderers on
// identical text and hold them to near-identical total heights.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/markdown/md_render.dart';

/// The exact TextField shape _LiveMarkdownSession.build produces, minus focus
/// and spell-check (neither affects geometry). The strut and contentPadding
/// here MUST mirror live_markdown_engine.dart — they are two thirds of the
/// fix these tests pin (a forced strut discards per-span line metrics; the
/// dense InputDecorator default added 8px read mode doesn't have).
Widget editField(String text, TextStyle style) => TextField(
      controller: LiveMarkdownController(text: text, dark: false),
      maxLines: null,
      style: style,
      strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: false),
      inputFormatters: [WrapSelectionFormatter()],
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
      ),
    );

Widget readView(String text, TextStyle style) =>
    MarkdownView(text: text, baseStyle: style);

Future<double> heightOf(WidgetTester t, Widget w) async {
  final key = GlobalKey();
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 420,
          child: KeyedSubtree(key: key, child: w),
        ),
      ),
    ),
  ));
  return t.getSize(find.byKey(key)).height;
}

void main() {
  // Both the hand-authored shape and the imported-notebook shape (an explicit
  // fontSize + the measured OneNote line pitch), because the line-height
  // multiplier is where the two renderers used to diverge.
  const handStyle = TextStyle(fontSize: 15, height: 1.5);
  const importedStyle = TextStyle(fontSize: 14.67, height: 1.32);

  for (final (label, style) in [('hand-authored', handStyle), ('imported', importedStyle)]) {
    group('edit matches view ($label)', () {
      Future<void> expectParity(WidgetTester t, String text,
          {double within = 1.0}) async {
        final read = await heightOf(t, readView(text, style));
        final edit = await heightOf(t, editField(text, style));
        expect(
          (read - edit).abs(),
          lessThanOrEqualTo(within),
          reason: 'read=$read edit=$edit for ${text.split('\n').length} '
              'line(s): ${text.replaceAll('\n', r'\n')}',
        );
      }

      testWidgets('plain paragraphs', (t) async {
        await expectParity(t, 'alpha\nbeta\ngamma');
      });

      testWidgets('empty lines keep their height', (t) async {
        await expectParity(t, 'alpha\n\ngamma');
      });

      testWidgets('headings', (t) async {
        // The report was clearest here: read renders H1 at 22px with 6+2px of
        // breathing room; edit rendered it at 23px with a hardcoded 1.3 height
        // and no padding — ~11px shorter per heading, every heading.
        await expectParity(t, '# Heading\nbody text');
        await expectParity(t, 'intro\n## Section\nbody');
        await expectParity(t, '### Third\nbody');
      });

      testWidgets('bulleted lists', (t) async {
        // Numbered lists are excluded: the test font's square glyphs make the
        // '1.' marker wider than the 22px hanging gutter, so it wraps in READ
        // — an artifact real fonts don't have (a real '1.' is ~11px wide).
        await expectParity(t, '- one\n- two\n- three');
      });

      testWidgets('checkboxes', (t) async {
        // Read draws a 17px icon with 3px top padding in the row; for small
        // fonts that governs the row height, so edit must reserve the same.
        await expectParity(t, '- [ ] task one\n- [x] task two\nplain');
      });

      testWidgets('quotes', (t) async {
        await expectParity(t, '> quoted line\nplain');
      });

      testWidgets('a real note shape', (t) async {
        await expectParity(
          t,
          '# Lecture 3\n'
          'Natural language is how people speak\n'
          '- context matters\n'
          '- [ ] revise this\n'
          '\n'
          '## Truth tables\n'
          'Each statement is T or F',
          within: 2.0,
        );
      });
    });
  }
}
