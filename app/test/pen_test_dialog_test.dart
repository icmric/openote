// The instrument for the pen-buttons report has to report.
//
// Three times now, from two people, on hardware nobody here owns: the pen's
// buttons do not erase or select. Each answer has been a guess about what
// Windows sends — three button bits accepted, the device kind widened to
// `mouse` because a barrel press is often promoted to a right-click — and a
// guess with a test around it is the worst kind, because it looks settled.
//
// So this pins the instrument, not the guess: every event is listed, and the
// verdict line says what the ink layer would conclude. If a pen sends nothing,
// the readout is empty and that is the answer.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/ui/pen_test_dialog.dart';

import 'support/app.dart';

void main() {
  Future<void> openIt(WidgetTester t) async {
    await t.pumpWidget(testApp(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showPenTestDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    )));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  /// The box in the middle of the dialog that captures events.
  Finder pad() => find.text('press, draw and hover here');

  testWidgets('A BARREL PRESS FROM A PEN READS AS ERASE', (t) async {
    await openIt(t);
    expect(find.textContaining('nothing yet'), findsOneWidget);

    final g = await t.startGesture(t.getCenter(pad()),
        kind: PointerDeviceKind.stylus, buttons: kSecondaryButton);
    await t.pump();

    expect(find.textContaining('ERASE'), findsOneWidget,
        reason: 'the verdict line answers the actual question');
    expect(find.textContaining('secondary/barrel'), findsOneWidget,
        reason: 'and both names of the bit are printed, because '
            'kPrimaryStylusButton and kSecondaryButton share a value — which '
            'is the ambiguity this dialog exists to resolve');
    await g.up();
    await t.pump();
  });

  testWidgets('a plain pen contact reads as drawing', (t) async {
    await openIt(t);
    final g = await t.startGesture(t.getCenter(pad()),
        kind: PointerDeviceKind.stylus);
    await t.pump();

    expect(find.textContaining('draw'), findsWidgets);
    expect(find.textContaining('ERASE'), findsNothing);
    await g.up();
    await t.pump();
  });

  testWidgets('a finger reads as navigation, and is still listed', (t) async {
    await openIt(t);
    final g =
        await t.startGesture(t.getCenter(pad()), kind: PointerDeviceKind.touch);
    await g.moveBy(const Offset(10, 10));
    await t.pump();

    expect(find.textContaining('touch — navigate'), findsOneWidget);
    expect(find.textContaining('kinds: touch'), findsOneWidget);
    await g.up();
    await t.pump();
  });
}
