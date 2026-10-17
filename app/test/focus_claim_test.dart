// Who holds the keyboard, when the answer is "nobody yet".
//
// [FocusNode.requestFocus] does not take effect where it is called — the
// manager marks the node and applies the change in a microtask — and every
// post-frame callback in a frame runs before that microtask. So a field that
// opens and asks for the keyboard is invisible to a standing claim that asks
// `primaryFocus` a moment later in the same frame, and the standing claim
// takes the keyboard it was told was free.
//
// Issue #19, second report: the page title's field appeared and the paragraph
// it had opened over kept the caret.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/core/focus_claim.dart';

void main() {
  late FocusNode opened;
  late FocusNode standing;

  setUp(() {
    opened = FocusNode(debugLabel: 'the field just clicked into');
    standing = FocusNode(debugLabel: 'an editor that claims from build');
  });

  tearDown(() {
    opened.dispose();
    standing.dispose();
  });

  Future<void> pumpBoth(WidgetTester t) => t.pumpWidget(Column(children: [
        Focus(focusNode: opened, child: const SizedBox(width: 10, height: 10)),
        Focus(focusNode: standing, child: const SizedBox(width: 10, height: 10)),
      ]));

  testWidgets('A CLAIM IS VISIBLE BEFORE THE MANAGER APPLIES IT', (t) async {
    await pumpBoth(t);
    expect(keyboardIsGoingSpare(standing), isTrue,
        reason: 'nothing holds the keyboard to start with');

    claimKeyboard(opened);

    expect(opened.hasPrimaryFocus, isFalse,
        reason: 'the request has not been applied yet — that is the gap');
    expect(keyboardIsGoingSpare(standing), isFalse,
        reason: 'and asking in the gap must still say somebody wants it');

    await t.pump();
    expect(opened.hasPrimaryFocus, isTrue);
    expect(keyboardIsGoingSpare(standing), isFalse,
        reason: 'now for the ordinary reason');
  });

  testWidgets('a claimant is not blocked by its own claim', (t) async {
    await pumpBoth(t);
    claimKeyboard(opened);
    expect(keyboardIsGoingSpare(opened), isTrue);
  });

  testWidgets('and the claim does not outlast the frame it was made in',
      (t) async {
    await pumpBoth(t);
    claimKeyboard(opened);
    await t.pump();
    opened.unfocus();
    await t.pump();

    // Otherwise a field that asked once and went away would keep the keyboard
    // from everything after it.
    expect(keyboardIsGoingSpare(standing), isTrue);
  });
}
