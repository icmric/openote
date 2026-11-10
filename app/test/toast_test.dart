import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/ui/toast.dart';

void main() {
  Future<void> pumpToast(WidgetTester t, SnackBar bar,
      {bool accessible = false}) async {
    await t.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(accessibleNavigation: accessible),
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ScaffoldMessenger.of(context).showToast(bar),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets('a notice with an Undo button still goes away', (t) async {
    await pumpToast(
        t,
        SnackBar(
          content: const Text('Moved page to the bin'),
          action: SnackBarAction(label: 'Undo', onPressed: () {}),
        ));
    expect(find.text('Moved page to the bin'), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Moved page to the bin'), findsNothing);
  });

  testWidgets('with accessible navigation on, it goes away too', (t) async {
    await pumpToast(t, const SnackBar(content: Text('Saved')),
        accessible: true);
    expect(find.text('Saved'), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('a long duration is cut to five seconds', (t) async {
    await pumpToast(
        t,
        const SnackBar(
            content: Text('Slow'), duration: Duration(seconds: 30)));
    await t.pump(const Duration(seconds: 6));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Slow'), findsNothing);
  });
}
