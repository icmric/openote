// THROWAWAY probe: horizontal parity between read mode and edit mode.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/editor/text_block_view.dart';
import 'package:openote/markdown/md_render.dart';
import 'package:openote/theme/onote_theme.dart';

const style = TextStyle(
    fontSize: 15,
    height: 1.5,
    letterSpacing: TextBlockView.letterSpacing,
    fontFamily: 'Inter');

Widget host(Widget child) => MaterialApp(
      theme: onoteTheme(Brightness.light),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 420, child: child),
        ),
      ),
    );

Widget editField(String text) => TextField(
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

/// Global x of the first glyph of [body] as READ mode draws it.
Future<double> readBodyX(WidgetTester t, String text, String body) async {
  await t.pumpWidget(host(MarkdownView(text: text, baseStyle: style)));
  final f = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText() == body);
  expect(f, findsOneWidget, reason: 'no RichText for "$body" in "$text"');
  return t.getTopLeft(f).dx;
}

/// Global x of the caret at raw offset [at] as EDIT mode draws it.
Future<double> editCaretX(WidgetTester t, String text, int at) async {
  await t.pumpWidget(host(editField(text)));
  await t.pump();
  final st = t.state<EditableTextState>(find.byType(EditableText));
  final RenderEditable r = st.renderEditable;
  final caret = r.getLocalRectForCaret(TextPosition(offset: at));
  return r.localToGlobal(caret.topLeft).dx;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('Inter')
      ..addFont(File('assets/fonts/inter/Inter-Regular.ttf')
          .readAsBytes()
          .then((b) => ByteData.view(b.buffer)));
    await loader.load();
  });

  testWidgets('bullets: body x in read vs edit', (t) async {
    final cases = <(String, String, int)>[
      ('- item', 'item', 2),
      ('  - item', 'item', 4),
      ('    - item', 'item', 6),
      ('      - item', 'item', 8),
      ('1. item', 'item', 3),
      ('  1. item', 'item', 5),
      ('  indented paragraph', 'indented paragraph', 2),
      ('    deeper paragraph', 'deeper paragraph', 4),
    ];
    for (final (src, body, prefixLen) in cases) {
      final read = await readBodyX(t, src, body);
      final edit = await editCaretX(t, src, prefixLen);
      // ignore: avoid_print
      print('src=${src.replaceAll(' ', '·')}  read=$read  edit=$edit  '
          'jump=${(read - edit).toStringAsFixed(1)}');
    }
  });

  testWidgets('checkbox: body x in read vs edit', (t) async {
    for (final src in ['- [ ] task', '  - [ ] task']) {
      final read = await readBodyX(t, src, 'task');
      final edit = await editCaretX(t, src, src.indexOf('task'));
      // ignore: avoid_print
      print('src=${src.replaceAll(' ', '·')}  read=$read  edit=$edit  '
          'jump=${(read - edit).toStringAsFixed(1)}');
    }
  });

  testWidgets('plain line is the control (should be ~0)', (t) async {
    final read = await readBodyX(t, 'plain line', 'plain line');
    final edit = await editCaretX(t, 'plain line', 0);
    // ignore: avoid_print
    print('control read=$read edit=$edit jump=${(read - edit)}');
  });
}
