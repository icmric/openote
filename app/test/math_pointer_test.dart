// The mouse, inside an equation (plan: v0.20 §E).
//
// Before this, the field's only gesture was a tap that jumped the caret to
// the END and destroyed any keyboard-made highlight on its way — so for a
// mouse user, selection did not exist: "i cant highlight anything". These
// tests drive real pointer events through the real field.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/math/math_editor.dart';
import 'package:openote/math/math_field.dart';
import 'package:openote/math/math_view.dart';

void main() {
  late MathEditor editor;

  setUp(() => editor = MathEditor.empty());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: MathField(
            editor: editor,
            textStyle: const TextStyle(fontSize: 22, color: Colors.black),
            onChanged: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String chars) async {
    for (final ch in chars.split('')) {
      final key = switch (ch) {
        '/' => LogicalKeyboardKey.slash,
        '+' || '=' => LogicalKeyboardKey.equal,
        ' ' => LogicalKeyboardKey.space,
        _ => LogicalKeyboardKey(ch.codeUnitAt(0)),
      };
      await tester.sendKeyDownEvent(key, character: ch);
      await tester.sendKeyUpEvent(key);
    }
    await tester.pump();
  }

  /// A click resolves one frame late (the hit table is measured offstage
  /// post-frame), so every gesture is followed by two pumps.
  Future<void> resolve(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a click puts the caret WHERE YOU CLICKED, not at the end',
      (tester) async {
    await pump(tester);
    await type(tester, 'x+2y=7');
    expect(editor.caretIndex, 6, reason: 'typing left the caret at the end');

    final left = tester.getTopLeft(find.byType(MathField));
    await tester.tapAt(left + const Offset(2, 18));
    await resolve(tester);

    expect(editor.caretIndex, lessThanOrEqualTo(1),
        reason: 'a click at the far left belongs at the start — for years it '
            'jumped to the end no matter where it landed');
  });

  testWidgets('dragging across the equation highlights it', (tester) async {
    await pump(tester);
    await type(tester, 'x+2y=7');

    final box = tester.getRect(find.byType(MathField));
    final g = await tester.startGesture(
      Offset(box.left + 2, box.center.dy),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await resolve(tester); // the hit table is built on pointer-down
    await g.moveTo(Offset(box.right - 2, box.center.dy));
    await tester.pump();
    await g.up();
    await tester.pump();

    expect(editor.hasSelection, isTrue,
        reason: 'THE defect: a mouse drag selected nothing at all');
    expect(editor.selectionLatex, editor.latex,
        reason: 'edge to edge takes everything');
  });

  testWidgets('the highlight is drawn in the stronger selection tint',
      (tester) async {
    await pump(tester);
    await type(tester, 'x+2');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    final math = tester.widget<OnoteMath>(find.byType(OnoteMath).first);
    expect(math.tex, contains(r'\fcolorbox'));
    expect(math.tex, isNot(contains(r'\rule')),
        reason: 'highlight OR caret, never both — the caret is always at one '
            'end of the highlight and reads as a stray hairline');
  });

  testWidgets('double-click selects the atom under the pointer, whole',
      (tester) async {
    await pump(tester);
    await type(tester, '1/2'); // '/' builds the fraction: one root child
    expect(editor.latex, r'\frac{1}{2}');

    final centre = tester.getCenter(find.byType(MathField));
    await tester.tapAt(centre);
    await resolve(tester);
    await tester.tapAt(centre);
    await resolve(tester);

    expect(editor.hasSelection, isTrue);
    expect(editor.selectionLatex, r'\frac{1}{2}',
        reason: 'a double-click on a fraction means the fraction — the same '
            'whole-structure rule Shift+arrow follows');
  });

  testWidgets('Shift+click extends from the caret', (tester) async {
    await pump(tester);
    await type(tester, 'x+2y');
    expect(editor.caretIndex, 4);

    final left = tester.getTopLeft(find.byType(MathField));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tapAt(left + const Offset(2, 18));
    await resolve(tester);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(editor.hasSelection, isTrue);
    expect(editor.selectionLatex, editor.latex,
        reason: 'caret at the end, Shift+click at the start: everything');
  });

  testWidgets('the field does NOT change height when a highlight appears',
      (tester) async {
    await pump(tester);
    await type(tester, 'x+2');
    final before = tester.getSize(find.byType(MathField)).height;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(editor.hasSelection, isTrue);
    final after = tester.getSize(find.byType(MathField)).height;
    expect((after - before).abs(), lessThan(0.5),
        reason: 'the 0.68em box cost is RESERVED (kSelectionBoxEm), so '
            'nothing outside the equation moves when a highlight appears');
  });

  testWidgets('kSelectionBoxEm is what the renderer actually charges',
      (tester) async {
    // Pinned so a flutter_math upgrade that changes \fboxsep fails HERE,
    // loudly, instead of quietly reintroducing the selection jump.
    const fs = 20.0;
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OnoteMath('x', textStyle: TextStyle(fontSize: fs), key: Key('a')),
            OnoteMath(r'\fcolorbox{#FF0000}{#FF0000}{$x$}',
                textStyle: TextStyle(fontSize: fs), key: Key('b')),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final plain = tester.getSize(find.byKey(const Key('a'))).height;
    final boxed = tester.getSize(find.byKey(const Key('b'))).height;
    expect(boxed - plain, closeTo(kSelectionBoxEm * fs, 1.0));
  });
}
