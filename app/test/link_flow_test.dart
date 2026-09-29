// **Ctrl+K, wherever the keyboard is — and what it refuses.**
//
// `link_site_test.dart` proves the rules; this proves they are actually the
// rules that run, through the widgets, in the two places somebody types: a
// paragraph, and a table cell. The second is not a formality. The shell's
// formatting chords deliberately stand down while a cell holds the keyboard
// (`canFormatText`), which is right for Ctrl+B — it would style the sentence
// OUTSIDE the table — and would have been wrong for a link, because a link
// belongs to whichever field is being typed into.
//
// The refusals are asserted by their consequence: the buffer is unchanged and
// the person is told why. A refusal that silently did nothing would be
// indistinguishable from a broken shortcut.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/editor/text_block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/inline_atom.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/link_dialog.dart';

class _NoopRepo implements Repository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('the address is read as generously as is still safe', () {
    test('a bare host becomes https, which is what people mean', () {
      expect(normaliseLinkTarget('example.com'), 'https://example.com');
      expect(normaliseLinkTarget('  example.com/a  '), 'https://example.com/a');
    });

    test('anything already carrying a scheme is left exactly as typed', () {
      expect(normaliseLinkTarget('http://a.test'), 'http://a.test');
      expect(normaliseLinkTarget('mailto:me@a.test'), 'mailto:me@a.test');
    });

    test('and nothing openable is refused rather than written into the note',
        () {
      expect(normaliseLinkTarget(''), isNull);
      expect(normaliseLinkTarget('   '), isNull);
      expect(normaliseLinkTarget('javascript:alert(1)'), isNull,
          reason: 'the allow-list that opens a link decides what may be one');
    });
  });

  group('every refusal says something', () {
    // A shortcut that does nothing is reported as broken; a shortcut that
    // explains itself is a rule somebody can work with.
    for (final why in LinkBlocked.values) {
      test('${why.name} has words', () {
        final said = linkRefusal(why);
        expect(said, isNotEmpty);
        expect(said.trim(), said);
        // The words of the note, not of the format.
        for (final jargon in ['atom', 'inline run', 'MdInline', 'buffer']) {
          expect(said.toLowerCase(), isNot(contains(jargon.toLowerCase())),
              reason: 'nobody typing a link needs to hear "$jargon"');
        }
      });
    }
  });

  group('in a paragraph', () {
    late AppState app;
    late Block block;

    Future<TextField> open(WidgetTester t, String text) async {
      app = AppState(_NoopRepo())
        ..notebookId = 'nb'
        ..pageId = 'pg'
        ..spellCheckEnabled = false;
      block = Block(
          type: BlockType.text,
          x: 0,
          y: 0,
          w: 460,
          content: {'text': text, 'autoWidth': false});
      app.blocks = [block];
      app.editingBlockId = block.id;
      addTearDown(app.cancelPendingSave);
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        theme: onoteTheme(Brightness.light)
            .copyWith(platform: TargetPlatform.windows),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
                width: 460, child: TextBlockView(block: block, app: app)),
          ),
        ),
      ));
      await t.pumpAndSettle();
      return t.widget<TextField>(find.byType(TextField).first);
    }

    Future<void> ctrlK(WidgetTester t) async {
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyK);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pumpAndSettle();
      app.cancelPendingSave();
    }

    testWidgets('Ctrl+K opens the dialog with the word already in it',
        (t) async {
      final field = await open(t, 'see docs now');
      await t.tap(find.byType(TextField).first);
      await t.pumpAndSettle();
      field.controller!.selection = const TextSelection.collapsed(offset: 8);
      await t.pumpAndSettle();

      await ctrlK(t);

      expect(find.text('Link'), findsOneWidget, reason: 'the dialog is up');
      final words = t.widget<TextField>(find.ancestor(
          of: find.text('Text to show'),
          matching: find.byType(TextField)));
      expect(words.controller!.text, 'docs',
          reason: 'the word the caret was pressed against');
    });

    testWidgets('and writing an address turns those words into a link',
        (t) async {
      final field = await open(t, 'see docs now');
      await t.tap(find.byType(TextField).first);
      await t.pumpAndSettle();
      field.controller!.selection = const TextSelection.collapsed(offset: 8);
      await t.pumpAndSettle();
      await ctrlK(t);

      await t.enterText(
          find.widgetWithText(TextField, 'Address'), 'example.com');
      await t.tap(find.text('Insert'));
      await t.pumpAndSettle();
      app.cancelPendingSave();

      expect(block.content['text'], 'see [docs](https://example.com) now');
    });

    testWidgets('a refusal leaves the note exactly as it was', (t) async {
      // The table's own reference: the case where a stray bracket costs a
      // payload nothing can reach again.
      const atom = InlineAtom(id: 't1', type: 'table', content: {
        'cells': [
          ['a', 'b']
        ]
      });
      final content = <String, dynamic>{
        'text': atom.reference(TableData.referenceAlt),
        'autoWidth': false,
      };
      InlineAtom.putIn(content, atom);
      app = AppState(_NoopRepo())
        ..notebookId = 'nb'
        ..pageId = 'pg'
        ..spellCheckEnabled = false;
      block = Block(type: BlockType.text, x: 0, y: 0, w: 460, content: content);
      app.blocks = [block];
      app.editingBlockId = block.id;
      addTearDown(app.cancelPendingSave);
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        theme: onoteTheme(Brightness.light)
            .copyWith(platform: TargetPlatform.windows),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
                width: 460, child: TextBlockView(block: block, app: app)),
          ),
        ),
      ));
      await t.pumpAndSettle();
      final before = block.content['text'] as String;

      await t.tap(find.byType(TextField).first);
      await t.pumpAndSettle();
      await ctrlK(t);

      expect(find.text('Link'), findsNothing, reason: 'no dialog was opened');
      expect(block.content['text'], before,
          reason: "the table's reference is untouched, which is the point");
      expect(find.byType(SnackBar), findsOneWidget,
          reason: 'and the person is told why, rather than nothing happening');
    });
  });

  group('in a table cell', () {
    testWidgets('Ctrl+K reaches the cell, not the sentence around it',
        (t) async {
      const atom = InlineAtom(id: 't1', type: 'table', content: {
        'cells': [
          ['Term', 'Meaning'],
          ['a', 'docs'],
        ]
      });
      final content = <String, dynamic>{
        'text': 'Results: ${atom.reference(TableData.referenceAlt)}',
        'autoWidth': false,
      };
      InlineAtom.putIn(content, atom);
      final app = AppState(_NoopRepo())
        ..notebookId = 'nb'
        ..pageId = 'pg'
        ..spellCheckEnabled = false;
      final block =
          Block(type: BlockType.text, x: 0, y: 0, w: 520, content: content);
      app.blocks = [block];
      app.editingBlockId = block.id;
      addTearDown(app.cancelPendingSave);
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        theme: onoteTheme(Brightness.light)
            .copyWith(platform: TargetPlatform.windows),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
                width: 520, child: TextBlockView(block: block, app: app)),
          ),
        ),
      ));
      await t.pumpAndSettle();

      // The last cell, which holds "docs".
      final cells = find.byWidgetPredicate(
          (w) => w is TextField && w.focusNode?.debugLabel == 'tableCell');
      expect(cells, findsNWidgets(4));
      await t.tap(cells.at(3));
      await t.pumpAndSettle();
      app.cancelPendingSave();
      final cell = t.widget<TextField>(cells.at(3));
      cell.controller!.selection = const TextSelection.collapsed(offset: 4);
      await t.pumpAndSettle();

      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyK);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pumpAndSettle();

      expect(find.text('Link'), findsOneWidget,
          reason: 'the cell answered for itself; the shell stands its own '
              'chords down here and would have swallowed this');

      await t.enterText(
          find.widgetWithText(TextField, 'Address'), 'example.com');
      await t.tap(find.text('Insert'));
      await t.pumpAndSettle();
      app.cancelPendingSave();

      final table = tablesIn(block.content).single;
      expect(table.cells.last.last, '[docs](https://example.com)',
          reason: 'the link is in the CELL');
      expect(block.content['text'], isNot(contains('example.com')),
          reason: 'and not one character of it in the sentence beside it');
    });
  });
}
