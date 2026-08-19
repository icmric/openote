// The two ways an equation could still lose your work, and the crash beside
// them — all three confirmed by the 2026-08-20 audit and fixed together.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/math/math_editor.dart';
import 'package:openote/math/math_field.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the clipboard belongs to the equation', () {
    late MathEditor editor;
    late List<String> commits;
    late Map<String, String> clipboard;

    setUp(() {
      editor = MathEditor.empty();
      commits = [];
      clipboard = {};
      // The real platform channel isn't available in a test binding.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard['text'] = call.arguments['text'] as String;
        }
        if (call.method == 'Clipboard.getData') {
          return {'text': clipboard['text'] ?? ''};
        }
        return null;
      });
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MathField(
            editor: editor,
            textStyle: const TextStyle(fontSize: 20, color: Colors.black),
            onChanged: commits.add,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> chord(WidgetTester tester, LogicalKeyboardKey k) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(k);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('Ctrl+X takes the equation, NOT the block', (tester) async {
      // The one keystroke in the editor that could still lose work: it fell
      // through to the canvas, which cut the whole block out from under the
      // student mid-equation.
      editor.insertSource(r'\frac{1}{2}');
      await pump(tester);
      await chord(tester, LogicalKeyboardKey.keyX);
      expect(clipboard['text'], r'\frac{1}{2}',
          reason: 'the equation has to reach the clipboard');
      expect(editor.latex, '', reason: 'and be gone from the equation');
      expect(commits, isNotEmpty,
          reason: 'the block has to be told, or the cut is not saved');
    });

    testWidgets('Ctrl+C leaves the equation alone', (tester) async {
      editor.insertSource(r'x^{2}');
      await pump(tester);
      await chord(tester, LogicalKeyboardKey.keyC);
      expect(clipboard['text'], r'x^{2}');
      expect(editor.latex, r'x^{2}');
    });

    testWidgets('Ctrl+V brings LaTeX back in as maths', (tester) async {
      clipboard['text'] = r'\frac{n}{2}';
      await pump(tester);
      await chord(tester, LogicalKeyboardKey.keyV);
      expect(editor.latex, contains(r'\frac{n}{2}'));
    });

    testWidgets('and a plain 1/2 off a message still arrives as a fraction',
        (tester) async {
      // LaTeX first, then the linear grammar — pasting is never refused.
      clipboard['text'] = '1/2';
      await pump(tester);
      await chord(tester, LogicalKeyboardKey.keyV);
      expect(editor.latex, contains(r'\frac'));
    });

    test('cut then paste is a round trip', () {
      final e = MathEditor.empty()..insertSource(r'\sqrt{x+1}');
      final taken = e.latex;
      e.clear();
      expect(e.latex, '');
      e.insertSource(taken);
      expect(e.latex, r'\sqrt{x+1}');
    });
  });

  group('an inline equation emptied and retyped', () {
    test('does not eat the words after it', () {
      // The exact replay from the audit. Emptying the equation collapses its
      // range, which `replaceMathAt` refused — so the caller's idea of where
      // the equation was ran ahead of the buffer and the next keystroke wrote
      // over the sentence instead of over the equation.
      final c = LiveMarkdownController(
          text: r'total $x$ plus more words', dark: false);
      const start = 6;
      var current = 9;

      void card(String next) {
        final tidy = next.trim();
        final written = tidy.isEmpty ? '' : '\$$tidy\$';
        c.replaceMathAt(start, current, tidy);
        current = start + written.length;
      }

      card('');
      expect(c.text, 'total  plus more words');
      card('y');
      expect(c.text, r'total $y$ plus more words',
          reason: 'the words after the equation are not the equation');
      card('yz');
      expect(c.text, r'total $yz$ plus more words');
    });

    test('and a genuinely broken range is still refused', () {
      final c = LiveMarkdownController(text: r'$x$', dark: false);
      c.replaceMathAt(-1, 99, 'y');
      c.replaceMathAt(3, 1, 'y'); // inverted
      expect(c.text, r'$x$');
    });
  });
}
