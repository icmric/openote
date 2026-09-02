// A picture stays a picture while you are typing next to it.
//
// The ask: "At the moment its got the hash in editing mode and renders when
// not editing, Id like the image to be displayed even while editing. Ideally
// too id like to be able to resize the image to be not based on the box (based
// on the box for max, but to be able to make it smaller)."
//
// The interesting part is not that a WidgetSpan can draw an image — it is that
// doing so inside a live-editing TextField is where carets go wrong. A
// placeholder occupies exactly ONE code unit in the laid-out paragraph, so
// swapping N characters of reference for one widget shortens the paragraph and
// every offset after it points at the wrong character. These tests pin the
// arithmetic that avoids that (N-1 hairline characters + 1 placeholder), and
// pin it through the two passes that walk the finished span tree, because both
// of them used to assume every span was a TextSpan.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/editor/flashcard_view.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/markdown/md_render.dart';
import 'package:openote/theme/tokens.dart';

void main() {
  // A real 1x1 transparent PNG — Flutter resolves the codec for real, and an
  // undecodable one throws into the test.
  final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwACh'
      'wGA60e6kgAAAABJRU5ErkJggg==');

  const style = TextStyle(fontSize: 14, height: 1.5);
  late LiveMarkdownController controller;

  /// How wide the host has made the box. Starts at the requested width and
  /// grows exactly as `TextBlockView` grows `Block.w` — by the deficit the
  /// engine asks for — so growth is exercised end to end rather than asserted
  /// against a stub that always says yes.
  late ValueNotifier<double> boxWidth;

  /// The editor, in a box that can grow, with the blob store stubbed.
  Future<void> edit(WidgetTester t, String text,
      {Uint8List? Function(String)? resolver,
      double width = 400,
      bool growable = true}) async {
    boxWidth = ValueNotifier<double>(width);
    addTearDown(boxWidth.dispose);
    controller = LiveMarkdownController(text: text, dark: false);
    // Separate statements, not a cascade: `..imageResolver = resolver ?? (_) => png`
    // parses the arrow body as swallowing everything after it.
    controller.imageResolver = resolver ?? (_) => png;
    controller.requestExtraWidth = growable
        ? (extra) =>
            boxWidth.value = (boxWidth.value + extra).clamp(80.0, 4000.0)
        : null;
    addTearDown(controller.dispose);
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: ValueListenableBuilder<double>(
            valueListenable: boxWidth,
            builder: (_, w, child) => SizedBox(width: w, child: child),
            child: TextField(
              controller: controller,
              maxLines: null,
              style: style,
              // The engine's shape, and NON-FORCED is load-bearing here: a
              // forced strut pins every line box to the base height, so the
              // picture is laid out and then drawn outside the field, where
              // nothing can be clicked. See live_markdown_engine.dart.
              strutStyle:
                  StrutStyle.fromTextStyle(style, forceStrutHeight: false),
              decoration: OnoteInput.bare,
            ),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
  }

  /// What the paragraph actually laid out, placeholders included (each as the
  /// single U+FFFC code unit it really occupies).
  String laidOut(WidgetTester t) =>
      t.widget<EditableText>(find.byType(EditableText)).controller.buildTextSpan(
            context: t.element(find.byType(EditableText)),
            style: style,
            withComposing: false,
          ).toPlainText();

  group('the picture is there while editing', () {
    testWidgets('an in-flow reference draws as the image, not as its hash',
        (t) async {
      await edit(t, 'Before\n![](sha256:abc123)\nAfter');
      expect(find.byType(Image), findsOneWidget);
      // And the hash is not ALSO printed beside it. (It is still laid out, at
      // a hairline size — this asserts it is not legible text, by asserting the
      // characters that carry it are the hidden ones.)
      final span = t.widget<EditableText>(find.byType(EditableText))
          .controller
          .buildTextSpan(
              context: t.element(find.byType(EditableText)),
              style: style,
              withComposing: false);
      var visibleHashChars = 0;
      void walk(InlineSpan s) {
        if (s is TextSpan) {
          final txt = s.text;
          if (txt != null &&
              txt.contains('sha256') &&
              (s.style?.fontSize ?? 99) > 1) {
            visibleHashChars += txt.length;
          }
          s.children?.forEach(walk);
        }
      }

      walk(span);
      expect(visibleHashChars, 0,
          reason: 'the reference must not be readable next to the picture');
    });

    testWidgets('the paragraph is exactly as long as the raw text', (t) async {
      // The invariant the whole design exists to hold. One code unit out and
      // every caret, selection and misspelling below the picture is wrong.
      await edit(t, 'Before\n![alt](sha256:abc123 =200x100)\nAfter');
      expect(laidOut(t).length, controller.text.length);
    });

    testWidgets('the placeholder leads the line, and the rest trails hidden',
        (t) async {
      // Order matters for where the picture is DRAWN. With the hidden
      // characters first, all ~25 of them sat between the left edge and the
      // picture — about one character of gap, and enough phantom width to
      // push a full-width picture onto the next line.
      await edit(t, '![](sha256:abc123)');
      final out = laidOut(t);
      expect(out.codeUnitAt(0), 0xFFFC, reason: 'the picture comes first');
      expect(out.substring(1), '![](sha256:abc123)'.substring(1));
    });

    testWidgets('the picture starts hard against the left edge', (t) async {
      // The bug, measured: "they all sit about 1 char width from the left
      // edge". letterSpacing is added per character in logical pixels and is
      // not scaled by fontSize, so the hidden run kept its full 0.25px each
      // however small the font was made.
      await edit(t, '![](sha256:abc123 =120x60)');
      expect(t.getRect(find.byType(Image)).left,
          closeTo(t.getRect(find.byType(EditableText)).left, 1.5));
    });

    testWidgets('a picture as wide as the box stays on its own line', (t) async {
      // The other half of the same phantom width: a full-width picture plus a
      // few pixels of invisible text does not fit, so it wrapped and "jumped
      // down a line".
      await edit(t, '![](sha256:abc123 =400x200)', width: 400, growable: false);
      final img = t.getRect(find.byType(Image));
      final field = t.getRect(find.byType(EditableText));
      // Against a LINE HEIGHT, not a hand-picked tolerance: the question is
      // "did it wrap", and a wrap costs a whole line. The few pixels that do
      // remain are the strut's half-leading, which is documented and pinned
      // separately by the read/edit parity test.
      const lineHeight = 14 * 1.5;
      expect(img.top - field.top, lessThan(lineHeight),
          reason: 'still on the first line, not pushed below one');
    });

    testWidgets('the caret still lands where the character is', (t) async {
      // The direct form of the same claim, asked of the real render object:
      // the word after the picture starts at the left edge of its own line.
      await edit(t, '![](sha256:abc123)\nhello');
      final st = tester(t);
      final at = controller.text.indexOf('hello');
      final caret = st.renderEditable
          .getLocalRectForCaret(TextPosition(offset: at));
      expect(caret.left, lessThan(2.0),
          reason: 'a shortened paragraph would push this caret rightwards');
      final end = st.renderEditable.getLocalRectForCaret(
          TextPosition(offset: controller.text.length));
      expect(end.top, greaterThan(caret.top - 1),
          reason: 'the last offset is still on the last line');
    });

    testWidgets('a reference whose blob is missing stays readable text',
        (t) async {
      // Still syncing, or gone. Printing the source is what lets it be seen,
      // fixed or cut out — a blank space would just look like data loss.
      await edit(t, '![](sha256:missing)', resolver: (_) => null);
      expect(find.byType(Image), findsNothing);
      expect(laidOut(t), '![](sha256:missing)');
    });

    testWidgets('bytes that are not a picture fall back to the reference',
        (t) async {
      // A truncated sync, a bad import, a blob that was never an image. Once
      // the editor draws pictures, a failed decode would otherwise be a blank
      // gap where the reference used to be — nothing to see and nothing to fix.
      await edit(t, '![](sha256:corrupt)',
          resolver: (_) => Uint8List.fromList(List.filled(64, 9)));
      await t.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(
          find.byWidgetPredicate(
              (w) => w is Text && w.data == '![](sha256:corrupt)'),
          findsOneWidget);
      expect(laidOut(t).length, controller.text.length,
          reason: 'and the placeholder still stands for its own character');
    });

    testWidgets('a reference sharing a line with words is left alone',
        (t) async {
      // Line-anchored, exactly like the read renderer, so the two agree.
      await edit(t, 'see ![](sha256:abc123) here');
      expect(find.byType(Image), findsNothing);
    });
  });

  group('a flashcard in the same box as the writing', () {
    // "Ideally id like to be able to have everything in a single box at once."
    // Same placeholder arithmetic as the picture, so the same invariant has to
    // hold: the laid-out paragraph must have exactly as many code units as the
    // raw text, or every caret offset after the card is wrong.
    testWidgets('renders as a card among the prose', (t) async {
      await edit(t, 'Notes above\n?[What is 7x8?](56)\nNotes below');
      expect(find.byType(FlipCard), findsOneWidget);
      expect(find.text('What is 7x8?'), findsOneWidget);
      expect(find.text('56'), findsNothing, reason: 'the answer is hidden');
    });

    testWidgets('the paragraph is still exactly as long as the raw text',
        (t) async {
      await edit(t, 'Notes above\n?[Q](A)\nNotes below');
      expect(laidOut(t).length, controller.text.length);
    });

    testWidgets('the caret after it still lands where the character is',
        (t) async {
      await edit(t, '?[Q](A)\nhello');
      final at = controller.text.indexOf('hello');
      final caret = tester(t)
          .renderEditable
          .getLocalRectForCaret(TextPosition(offset: at));
      expect(caret.left, lessThan(2.0));
    });

    testWidgets('and it reads the same when you are not editing', (t) async {
      // Both renderers, or the box visibly changes on entering edit mode.
      await t.pumpWidget(const MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: MarkdownView(
            text: 'Notes above\n?[What is 7x8?](56)\nNotes below',
            baseStyle: TextStyle(fontSize: 14),
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.byType(FlipCard), findsOneWidget);
      expect(find.text('What is 7x8?'), findsOneWidget);
    });
  });

  group('the passes that walk the finished tree', () {
    testWidgets('a typo elsewhere in the block does not delete the picture',
        (t) async {
      // Regression. The misspelling post-pass rebuilt children with
      // `whereType<TextSpan>()`, which silently dropped every placeholder — so
      // the picture vanished the moment the block contained one bad word.
      await edit(t, 'teh\n![](sha256:abc123)\nAfter');
      expect(find.byType(Image), findsOneWidget, reason: 'precondition');
      controller.misspellings = const [TextRange(start: 0, end: 3)];
      await t.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(laidOut(t).length, controller.text.length);
    });

    testWidgets('an underline BELOW the picture lands on the right word',
        (t) async {
      // The other half: the pass counts raw characters as it walks, so a
      // placeholder has to declare the length of the source it replaced or
      // every range after it slides left by that much.
      const text = '![](sha256:abc123)\nthe teh end';
      await edit(t, text);
      final start = text.indexOf('teh');
      controller.misspellings = [TextRange(start: start, end: start + 3)];
      await t.pumpAndSettle();

      final underlined = <String>[];
      void walk(InlineSpan s) {
        if (s is TextSpan) {
          if (s.text != null &&
              s.style?.decorationStyle == TextDecorationStyle.wavy) {
            underlined.add(s.text!);
          }
          s.children?.forEach(walk);
        }
      }

      walk(t.widget<EditableText>(find.byType(EditableText))
          .controller
          .buildTextSpan(
              context: t.element(find.byType(EditableText)),
              style: const TextStyle(fontSize: 14),
              withComposing: false));
      expect(underlined, ['teh']);
    });
  });

  group('the two renderers still agree', () {
    Future<double> heightOf(WidgetTester t, Widget w) async {
      final key = GlobalKey();
      await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 420, child: KeyedSubtree(key: key, child: w)),
          ),
        ),
      ));
      await t.pumpAndSettle();
      return t.getSize(find.byKey(key)).height;
    }

    testWidgets('a picture does not jump when you click into the box',
        (t) async {
      // The complaint this feature came from was a block that changed height
      // by the whole picture on entering edit — a ~100px reference collapsing
      // to a ~12px line of text. What is left is the strut's half-leading:
      // PlaceholderAlignment.top aligns the picture with the top of the FONT,
      // and the line's leading sits above that, so edit is a few pixels
      // taller. Pinned rather than removed — the only lever is the field-wide
      // strut, and flattening it would break the parity of every other line
      // shape (see edit_view_metrics_test.dart).
      const text = 'Before\n![](sha256:abc123 =200x100)\nAfter';
      final read = await heightOf(
          t,
          MarkdownView(
              text: text, baseStyle: style, imageResolver: (_) => png));
      final ctrl = LiveMarkdownController(text: text, dark: false)
        ..imageResolver = (_) => png;
      addTearDown(ctrl.dispose);
      final editH = await heightOf(
          t,
          TextField(
            controller: ctrl,
            maxLines: null,
            style: style,
            strutStyle:
                StrutStyle.fromTextStyle(style, forceStrutHeight: false),
            decoration: OnoteInput.bare,
          ));
      expect((read - editH).abs(), lessThanOrEqualTo(6.0),
          reason: 'read=$read edit=$editH');
    });
  });

  group('resizing', () {
    Future<void> dragHandle(WidgetTester t, double dx) async {
      final g = await t.startGesture(t.getCenter(find.byIcon(Icons.south_east)));
      // Several steps, so the pan is recognised the way a real drag is.
      for (var i = 0; i < 5; i++) {
        await g.moveBy(Offset(dx / 5, 0));
        await t.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await t.pumpAndSettle();
    }

    testWidgets('dragging the corner in writes a smaller =WxH', (t) async {
      await edit(t, '![](sha256:abc123 =200x100)');
      var saved = 0;
      controller.onSelfEdit = () => saved++;
      await dragHandle(t, -50);
      expect(controller.text, '![](sha256:abc123 =150x75)');
      expect(saved, 1, reason: 'a programmatic edit must tell the host once');
    });

    testWidgets('dragging past the edge grows the BOX with it', (t) async {
      // The rule reversed: "if i try to expand the image larger than the box,
      // the box just grows with it to accomodate it". This replaces a test
      // that pinned the opposite — the picture stopping at the box edge.
      await edit(t, '![](sha256:abc123 =200x100)', width: 300);
      final before = boxWidth.value;
      await dragHandle(t, 400);
      expect(boxWidth.value, greaterThan(before),
          reason: 'the box was asked for more room and took it');
      final m = RegExp(r'=(\d+)x(\d+)').firstMatch(controller.text)!;
      expect(int.parse(m.group(1)!), greaterThan(300),
          reason: 'and the picture is genuinely wider than the box used to be');
    });

    testWidgets('what is written is what is drawn', (t) async {
      // The invariant that makes growth safe. The picture is only ever
      // recorded at a width it is actually rendered at, so the `=WxH` in the
      // text and the pixels on screen can never disagree — which is what would
      // happen if the drag ran ahead of a box that refused to grow.
      await edit(t, '![](sha256:abc123 =200x100)', width: 300, growable: false);
      await dragHandle(t, 2000);
      final m = RegExp(r'=(\d+)x(\d+)').firstMatch(controller.text)!;
      final rendered = t.getSize(find.byType(Image)).width;
      expect(int.parse(m.group(1)!), closeTo(rendered, 1.0));
      expect(boxWidth.value, 300, reason: 'a box that cannot grow did not');
    });

    testWidgets('overshoot inside one drag is remembered, not swallowed',
        (t) async {
      // Against a box that will NOT grow, push well past the edge and come
      // back — within a single gesture. The pixels spent beyond the clamp have
      // to be remembered, or the way back is short by exactly that many and
      // the picture ends up smaller than it started. (Across two SEPARATE
      // drags it legitimately does not: each drag starts from the width that
      // was actually stored.)
      await edit(t, '![](sha256:abc123 =200x100)', width: 240, growable: false);
      final g = await t.startGesture(t.getCenter(find.byIcon(Icons.south_east)));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(50, 0));
        await t.pump(const Duration(milliseconds: 16));
      }
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(-50, 0));
        await t.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await t.pumpAndSettle();
      final m = RegExp(r'=(\d+)x(\d+)').firstMatch(controller.text)!;
      expect(int.parse(m.group(1)!), closeTo(200, 12),
          reason: 'back to roughly the width it began at');
    });

    testWidgets('it cannot be dragged away to nothing', (t) async {
      // Below the floor the grip is most of the picture and there is no way
      // back out of the corner you dragged yourself into.
      await edit(t, '![](sha256:abc123 =200x100)');
      await dragHandle(t, -1000);
      expect(controller.text, '![](sha256:abc123 =48x24)');
    });

    testWidgets('the aspect ratio is kept', (t) async {
      await edit(t, '![](sha256:abc123 =300x100)');
      await dragHandle(t, -90);
      final m = RegExp(r'=(\d+)x(\d+)').firstMatch(controller.text)!;
      final w = int.parse(m.group(1)!), h = int.parse(m.group(2)!);
      expect(w / h, closeTo(3.0, 0.05));
    });

    testWidgets('a resize the read renderer would not accept is impossible',
        (t) async {
      // The two renderers parse the same suffix; this proves what the drag
      // writes goes straight back to being a picture, not to being source.
      await edit(t, '![](sha256:abc123 =200x100)');
      await dragHandle(t, -40);
      final resized = controller.text;
      await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
        home: Scaffold(
          body: MarkdownView(
            text: resized,
            baseStyle: const TextStyle(fontSize: 14),
            imageResolver: (_) => png,
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(
          t
              .widgetList<RichText>(find.byType(RichText))
              .map((r) => r.text.toPlainText())
              .join(),
          isNot(contains('sha256')));
    });

    testWidgets('a stale drag is dropped rather than applied to other text',
        (t) async {
      // The offsets are captured when the span is built and used when the drag
      // ends. If the buffer moved on in between, landing the resize somewhere
      // else would be a corruption; landing it nowhere is a lost drag.
      await edit(t, '![](sha256:abc123 =200x100)');
      const other = 'entirely different text';
      controller.text = other;
      controller.resizeImageLine(0, 26, '![](sha256:abc123 =200x100)', 50, 25);
      expect(controller.text, other);
    });
  });
}

/// The live [EditableTextState], for questions only the render object answers.
EditableTextState tester(WidgetTester t) =>
    t.state<EditableTextState>(find.byType(EditableText));
