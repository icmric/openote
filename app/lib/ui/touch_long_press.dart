/// **A long press with a finger is a right-click.**
///
/// Every context menu in the app opens on a right-click, which a touch screen
/// does not have. This wraps something so that holding a finger on it (and only
/// a finger: a mouse that rests for half a second is not asking for a menu, and
/// a pen is drawing) calls [onMenu] with where it was held, the same position a
/// right-click would have given.
///
/// It sits beside whatever the child already does with taps and drags and takes
/// nothing from them: a long press only wins if the finger stays put.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

class TouchLongPress extends StatelessWidget {
  const TouchLongPress({super.key, required this.onMenu, required this.child});

  /// Called with the global position of the press. Null turns it off.
  final void Function(Offset global)? onMenu;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final menu = onMenu;
    // **Always the same widget around the child, on or off.** Wrapping only
    // while a menu is wanted changes the shape of the tree under it every time
    // that flips, and Flutter answers a change of shape by rebuilding the whole
    // child from scratch, which for a text box means losing the caret mid-edit.
    // Off is a recogniser that accepts no pointers, so it never enters a
    // gesture contest at all and costs the child nothing.
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(),
          (r) {
            r.supportedDevices =
                menu == null ? const <PointerDeviceKind>{} : const {PointerDeviceKind.touch};
            r.onLongPressStart = menu == null ? null : (d) => menu(d.globalPosition);
          },
        ),
      },
      child: child,
    );
  }
}
