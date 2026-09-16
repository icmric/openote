// **A picture in a SENTENCE can be saved out too.**
//
// The gap this closes, reported by the owner within an hour of the feature
// landing: *"Save image as doesnt come up as an option. If i right click while
// not editing it comes up with a bunch of options, all of which are just the
// regular right click on box options, if im editing and right click it, its
// just the options that appear when i right click text normally."*
//
// Both halves of that are explained by one fact. `pictureIn(Block)` — the
// question the block menu asks — can only see a `BlockType.image`, and a drop
// makes one of those ONLY when it misses every text box. Ctrl+V at the caret,
// a drop onto a box and Insert ▸ Image all splice `![](sha256:…)` into a
// paragraph's own Markdown instead, so three routes of four produce a picture
// the block menu cannot see at all. Right-clicking the box therefore offered
// the ordinary box menu, and right-clicking while editing handed the press to
// the field's own toolbar.
//
// So the fix is not a bigger `pictureIn`: a picture in a sentence is not a
// property of the block, it is a property of the OFFSET you right-clicked.
// `pictureRefAt` answers that, next to the line grammar that defines the
// shape, and the paragraph's own context menu asks it.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/editor/text_block_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/inline_atom.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/save_picture.dart';

class _NoopRepo implements Repository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  const hash = 'sha256:abc123';
  const ref = '![](sha256:abc123)';

  group('finding the picture the caret is on', () {
    test('a line that is nothing but a reference is one', () {
      final at = pictureRefAt('Notes:\n$ref\nmore', 7);
      expect(at, isNotNull);
      expect(at!.hash, hash);
      expect(at.start, 7);
      expect(at.end, 7 + ref.length);
    });

    test('and both of its edges count, because the caret is snapped to them',
        () {
      // A click on the picture resolves inside the run and
      // `_snapOutOfHiddenMarkers` then pushes the caret to one end or the
      // other. Neither end may lose the picture.
      final text = 'Notes:\n$ref\nmore';
      expect(pictureRefAt(text, 7)?.hash, hash, reason: 'the left edge');
      expect(pictureRefAt(text, 7 + ref.length)?.hash, hash,
          reason: 'the right edge');
      expect(pictureRefAt(text, 7 + 4)?.hash, hash, reason: 'and inside it');
    });

    test('prose is not a picture', () {
      expect(pictureRefAt('just some words', 4), isNull);
    });

    test('a reference sharing its line with prose is not one either', () {
      // The renderer is line-anchored, so this draws as literal source rather
      // than as a picture. Offering to save something that is not being drawn
      // as a picture would be offering to save nothing.
      expect(pictureRefAt('see $ref here', 6), isNull);
    });

    test("a TABLE's reference is not a picture, though it shares the shape",
        () {
      // `![alt](onote://atom/<id>)` and `![alt](sha256:…)` differ only in the
      // scheme, and a table on a line of its own has already been mistaken for
      // a picture once in this codebase.
      const atom = InlineAtom(id: 't1', type: 'table', content: {
        'cells': [
          ['a', 'b']
        ]
      });
      final line = atom.reference(TableData.referenceAlt);
      expect(pictureRefAt(line, 2), isNull);
    });

    test('nor is a picture that is not ours to write out', () {
      // An `http://` image is somebody else's file. Nothing in the blob store
      // answers for it, so there are no bytes to save.
      expect(pictureRefAt('![](https://a.test/x.png)', 3), isNull);
    });

    test('an offset past the end of the text finds nothing, and does not throw',
        () {
      expect(pictureRefAt(ref, 9999), isNull);
      expect(pictureRefAt(ref, -1), isNull);
      expect(pictureRefAt('', 0), isNull);
    });

    test('the right picture is found when a page holds several', () {
      const other = '![](sha256:def456)';
      final text = '$ref\n$other';
      expect(pictureRefAt(text, 0)?.hash, hash);
      expect(pictureRefAt(text, ref.length + 1)?.hash, 'sha256:def456');
    });
  });

  group('what the file is called', () {
    test('an in-flow reference carries no mime, so the bytes decide', () {
      // PNG magic. The reference is `![](sha256:…)` and nothing else — there
      // is no recorded mime to consult, which is exactly why this path sniffs.
      final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);
      expect(suggestedPictureName(png), 'image.png');
      final jpg = Uint8List.fromList([0xff, 0xd8, 0xff, 0, 0, 0, 0, 0]);
      expect(suggestedPictureName(jpg), 'image.jpg');
    });

    test('a caller that knows the mime is believed over the bytes', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);
      expect(suggestedPictureName(png, mime: 'image/webp'), 'image.webp');
    });

    test('and unknown bytes still get an extension, never none', () {
      // A file with no extension opens in nothing at all on Windows.
      expect(suggestedPictureName(Uint8List.fromList([1, 2, 3, 4])),
          'image.png');
    });
  });

  group('the paragraph offers it', () {
    late AppState app;
    late Block block;

    Future<void> openParagraph(WidgetTester t, String text) async {
      app = AppState(_NoopRepo())
        ..notebookId = 'nb'
        ..pageId = 'pg'
        ..spellCheckEnabled = false;
      block = Block(type: BlockType.text, x: 0, y: 0, w: 420, content: {
        'text': text,
        'autoWidth': false,
      });
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
                width: 420, child: TextBlockView(block: block, app: app)),
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    /// Put the caret at [offset] and open the field's own context menu the way
    /// a right-click does.
    Future<void> menuAt(WidgetTester t, int offset) async {
      final field = t.widget<TextField>(find.byType(TextField).first);
      field.controller!.selection = TextSelection.collapsed(offset: offset);
      await t.pumpAndSettle();
      final state = t.state<EditableTextState>(find.byType(EditableText).first);
      state.showToolbar();
      await t.pumpAndSettle();
    }

    testWidgets('when the caret is on a picture in the sentence', (t) async {
      await openParagraph(t, 'Notes:\n$ref\nmore');
      await menuAt(t, 7);
      expect(find.text('Save image as…'), findsOneWidget,
          reason: 'THE BUG: a pasted picture had no way back out at all');
    });

    testWidgets('and not when the caret is in ordinary prose', (t) async {
      await openParagraph(t, 'Notes:\n$ref\nmore');
      await menuAt(t, 2);
      expect(find.text('Save image as…'), findsNothing);
    });

    testWidgets('a paragraph with no picture in it is untouched', (t) async {
      await openParagraph(t, 'just some words');
      await menuAt(t, 4);
      expect(find.text('Save image as…'), findsNothing);
    });
  });
}
