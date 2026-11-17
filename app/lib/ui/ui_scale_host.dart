/// Draws the whole app at the chosen interface size.
///
/// Sits directly under the app's `MaterialApp`, so the navigator, every dialog,
/// every menu and every tooltip are inside it and grow together.
///
/// **The same widgets at every size, 100% included.** Taking the wrapper away
/// at 100% would change the shape of the tree above the navigator, and Flutter
/// answers a change of shape by throwing the whole tree away: every open page,
/// dialog and half-typed word. So at 100% this is a `FittedBox` doing nothing.
///
/// The child is laid out in a box 1/scale as big as the window and then drawn
/// scale times larger, which is what makes text and icons crisp at any size
/// (they are drawn bigger, not stretched), and pointer positions come out right
/// because the box applies its transform to hit testing as well.
library;

import 'package:flutter/widgets.dart';

import '../state/app_state.dart';
import '../state/ui_scale.dart';
import 'device_class.dart';

class UiScaleHost extends StatelessWidget {
  const UiScaleHost({super.key, required this.app, required this.child});

  final AppState app;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: app.uiScaleNotifier,
      child: child,
      builder: (context, chosen, child) => LayoutBuilder(
        builder: (context, constraints) {
          final window = constraints.biggest;
          // A tablet is drawn larger, so every target is finger-sized, on top of
          // whatever size the person chose. The class is decided from the real
          // window, before any zoom (see `device_class.dart`).
          final device = classifyDevice(window);
          final s = effectiveUiScale(
              chosen * (device == DeviceClass.tablet ? kTabletBoost : 1.0),
              window);
          app.effectiveUiScale = s;
          final logical = Size(window.width / s, window.height / s);
          return DeviceClassScope(
            device: device,
            child: MediaQuery(
              // Anything that asks how big the window is gets the size the
              // layout actually has, not the one it is drawn at.
              data: MediaQuery.of(context).copyWith(size: logical),
              child: FittedBox(
                fit: BoxFit.fill,
                alignment: Alignment.topLeft,
                child: SizedBox.fromSize(size: logical, child: child),
              ),
            ),
          );
        },
      ),
    );
  }
}
