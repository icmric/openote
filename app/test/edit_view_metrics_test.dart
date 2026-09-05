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
import 'package:openote/editor/text_block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/markdown/md_render.dart';
import 'package:openote/model/models.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/theme/tokens.dart';

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
      // The SHARED token, not a hand-copy: this decoration and the engine's
      // must be the same object or this test measures something the app does
      // not render. `OnoteInput.bare` turns every border off in every state,
      // which matters because the themed `InputDecorationTheme.enabledBorder`
      // overrides a decoration's own `border` — the exact 8px regression this
      // test caught when inputs were first themed.
      decoration: OnoteInput.bare,
    );

Widget readView(String text, TextStyle style) =>
    MarkdownView(text: text, baseStyle: style);

/// Intrinsic width of a renderer, for the horizontal half of parity.
Future<double> widthOf(WidgetTester t, Widget w) async {
  final key = GlobalKey();
  await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
    theme: onoteTheme(Brightness.light),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: IntrinsicWidth(child: KeyedSubtree(key: key, child: w)),
      ),
    ),
  ));
  return t.getSize(find.byKey(key)).width;
}

Future<double> heightOf(WidgetTester t, Widget w) async {
  final key = GlobalKey();
  await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
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
  group('letters are spaced the same in both modes', () {
    // The three paths that render or measure a box each merged onto a
    // DIFFERENT Material default — Text inherits bodyMedium (0.25), TextField
    // merges onto bodyLarge (0.5), and the width measurement uses a bare
    // TextPainter (0). So letters visibly spread on entering edit, and the box
    // was measured narrower than the field it had to hold, which made lines
    // wrap that had no business wrapping.
    const style = TextStyle(
        fontSize: 15, height: 1.5, letterSpacing: TextBlockView.letterSpacing);

    testWidgets('the same sentence is the same width', (t) async {
      for (final text in [
        'plain',
        'alpha beta gamma',
        'The quick brown fox jumps over the lazy dog',
      ]) {
        final read = await widthOf(t, readView(text, style));
        final edit = await widthOf(t, editField(text, style));
        // The remainder is RenderEditable's caret reservation (cursor width +
        // gap) — a constant, not a per-character drift. Anything that scales
        // with length is a spacing mismatch and is the bug.
        expect(edit - read, closeTo(3.0, 1.0),
            reason: 'read=$read edit=$edit for ${text.length} chars');
      }
    });

    // ── Horizontal parity for LISTS ──────────────────────────────────────
    //
    // The reported bug: "editing mode still has a large amount of content
    // movement with dot points — when editing they are much closer to the
    // left than when viewing". Only vertical height and the width of PLAIN
    // sentences were pinned before, which is exactly why a 10px jump on
    // every bullet and 28px per nesting level went unnoticed.
    //
    // Width is the measurable proxy: both renderers lay out the same body
    // text, so if their intrinsic widths agree, the body starts at the same
    // x. Read mode hangs its marker in a gutter; edit mode now does too.
    group('a list line does not move sideways on click-in', () {
      const style = TextStyle(fontSize: 15, height: 1.5, letterSpacing: 0.25);

      Future<void> sameWidth(WidgetTester t, String text,
          {required String why}) async {
        final read = await widthOf(t, readView(text, style));
        final edit = await widthOf(t, editField(text, style));
        // Same 3px caret reservation the plain-text case allows for.
        expect(edit - read, closeTo(3.0, 2.5),
            reason: '$why — read=$read edit=$edit for "$text"');
      }

      testWidgets('a top-level bullet', (t) async {
        await sameWidth(t, '- milk', why: 'the 22px hanging gutter');
      });

      testWidgets('every bullet character lands identically', (t) async {
        for (final m in ['-', '*', '+']) {
          await sameWidth(t, '$m milk', why: '"$m " must hang like "- "');
        }
      });

      testWidgets('nesting steps by the same amount in both', (t) async {
        await sameWidth(t, '  - one level', why: 'indentPx per level');
        await sameWidth(t, '    - two levels', why: 'error compounds');
        await sameWidth(t, '      - three levels', why: 'error compounds');
      });

      testWidgets('numbered items and tasks hang too', (t) async {
        await sameWidth(t, '1. first', why: 'the number hangs');
        await sameWidth(t, '- [ ] a task', why: 'the box hangs');
        await sameWidth(t, '- [x] done', why: 'a ticked box hangs');
      });

      testWidgets('a NESTED task lands where a nested bullet does', (t) async {
        // The hole the top-level cases left: read used to add its 17+6px icon
        // column on top of the FULL indent, so a nested task sat 23px right
        // of a nested bullet and jumped that far left on click-in.
        await sameWidth(t, '  - [ ] nested task', why: 'one level');
        await sameWidth(t, '    - [x] deeper', why: 'two levels, ticked');
      });

      testWidgets('a task body starts where a bullet body does', (t) async {
        // Same depth, same left edge — a mixed list must not look ragged.
        final bullet = await widthOf(t, readView('  - xx', style));
        final task = await widthOf(t, readView('  - [ ] xx', style));
        expect(task - bullet, closeTo(0.0, 1.0),
            reason: 'bullet=$bullet task=$task — the box and the bullet '
                'share one gutter');
      });
    });

    testWidgets('baseStyle pins it rather than inheriting', (t) async {
      // If this ever goes back to null, all three paths diverge again.
      final b = Block(
          type: BlockType.text, x: 0, y: 0, content: {'text': 'x'});
      expect(TextBlockView.baseStyle(b, dark: false).letterSpacing,
          TextBlockView.letterSpacing);
    });
  });

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
