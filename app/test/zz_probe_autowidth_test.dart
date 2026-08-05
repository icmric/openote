// THROWAWAY probe: does the auto-width measurement match what read mode needs?
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/editor/text_block_view.dart';
import 'package:openote/markdown/md_render.dart';
import 'package:openote/model/models.dart';
import 'package:openote/theme/onote_theme.dart';

Block blk(String text) =>
    Block(type: BlockType.text, x: 0, y: 0, content: {'text': text});

Widget host(double width, Widget child) => MaterialApp(
      theme: onoteTheme(Brightness.light),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    );

Future<double> readHeight(WidgetTester t, String text, TextStyle style,
    double width) async {
  final key = GlobalKey();
  await t.pumpWidget(host(
      width,
      KeyedSubtree(
          key: key, child: MarkdownView(text: text, baseStyle: style))));
  return t.getSize(find.byKey(key)).height;
}

Future<double> editHeight(WidgetTester t, String text, TextStyle style,
    double width) async {
  final key = GlobalKey();
  await t.pumpWidget(host(
    width,
    KeyedSubtree(
      key: key,
      child: TextField(
        controller: LiveMarkdownController(text: text, dark: false),
        maxLines: null,
        style: style,
        strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: false),
        inputFormatters: [WrapSelectionFormatter()],
        decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none),
      ),
    ),
  ));
  return t.getSize(find.byKey(key)).height;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final (fam, path) in [
      ('Inter', 'assets/fonts/inter/Inter-Regular.ttf'),
      ('Inter', 'assets/fonts/inter/Inter-SemiBold.ttf'),
    ]) {
      await (FontLoader(fam)
            ..addFont(
                File(path).readAsBytes().then((b) => ByteData.view(b.buffer))))
          .load();
    }
  });

  testWidgets('auto-width vs what read mode actually needs', (t) async {
    const inset = 20.0; // TextBlockView.insetFor -> horizontal 10 each side
    for (final text in [
      'The quick brown fox jumps over the lazy dog',
      '# The quick brown fox jumps',
      '## A slightly shorter heading here',
      '- The quick brown fox jumps over the lazy',
      '    - The quick brown fox jumps over lazy',
      '      - The quick brown fox jumps over la',
      '- [ ] The quick brown fox jumps over lazy',
      '    An indented imported paragraph of text',
    ]) {
      final b = blk(text);
      final style = TextBlockView.baseStyle(b, dark: false);
      final w = TextBlockView.autoWidth(b, dark: false);
      final inner = w - inset;
      // One-line height at effectively infinite width, for comparison.
      final free = await readHeight(t, text, style, 4000);
      final atBox = await readHeight(t, text, style, inner);
      final editAtBox = await editHeight(t, text, style, inner);
      final editFree = await editHeight(t, text, style, 4000);
      // ignore: avoid_print
      print('${atBox > free + 1 ? "WRAPS " : "ok    "} w=${w.toStringAsFixed(1)}'
          ' readFree=${free.toStringAsFixed(1)} readAtBox=${atBox.toStringAsFixed(1)}'
          ' editFree=${editFree.toStringAsFixed(1)} editAtBox=${editAtBox.toStringAsFixed(1)}'
          '  <<${text.replaceAll(' ', '·')}>>');
    }
  });
}
