// A long press with a finger is the touch screen's right-click; a mouse that
// rests on something is not asking for a menu.
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/ui/touch_long_press.dart';

void main() {
  Future<List<Offset>> pump(WidgetTester t) async {
    final got = <Offset>[];
    await t.pumpWidget(MaterialApp(
      home: Center(
        child: TouchLongPress(
          onMenu: got.add,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: const SizedBox(width: 200, height: 100, key: Key('box')),
          ),
        ),
      ),
    ));
    return got;
  }

  testWidgets('a finger held still opens the menu, where it was held',
      (t) async {
    final got = await pump(t);
    final centre = t.getCenter(find.byKey(const Key('box')));
    final g = await t.startGesture(centre, kind: PointerDeviceKind.touch);
    await t.pump(const Duration(milliseconds: 700));
    await g.up();
    await t.pumpAndSettle();
    expect(got, [centre]);
  });

  testWidgets('a quick tap is still a tap and opens nothing', (t) async {
    final got = await pump(t);
    await t.tap(find.byKey(const Key('box')));
    await t.pumpAndSettle();
    expect(got, isEmpty);
  });

  testWidgets('a mouse held still opens nothing', (t) async {
    final got = await pump(t);
    final g = await t.startGesture(t.getCenter(find.byKey(const Key('box'))),
        kind: PointerDeviceKind.mouse);
    await t.pump(const Duration(milliseconds: 700));
    await g.up();
    await t.pumpAndSettle();
    expect(got, isEmpty);
  });

  testWidgets('a finger that moves is a drag, not a menu', (t) async {
    final got = await pump(t);
    final g = await t.startGesture(t.getCenter(find.byKey(const Key('box'))),
        kind: PointerDeviceKind.touch);
    await g.moveBy(const Offset(60, 0));
    await t.pump(const Duration(milliseconds: 700));
    await g.up();
    await t.pumpAndSettle();
    expect(got, isEmpty);
  });

  testWidgets('turning the menu on and off does not rebuild what is inside',
      (t) async {
    // A text box being edited turns its menu off; if that changed the shape of
    // the tree under it, the box would be rebuilt from scratch and lose its
    // caret. This is what broke "an empty box removes itself" when it did.
    var inits = 0;
    Widget app(bool on) => MaterialApp(
          home: TouchLongPress(
            onMenu: on ? (_) {} : null,
            child: _Probe(onInit: () => inits++),
          ),
        );
    await t.pumpWidget(app(true));
    await t.pumpWidget(app(false));
    await t.pumpWidget(app(true));
    expect(inits, 1);
  });
}

class _Probe extends StatefulWidget {
  const _Probe({required this.onInit});
  final VoidCallback onInit;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const SizedBox(width: 10, height: 10);
}
