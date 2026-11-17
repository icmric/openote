/// **Which kind of device is this?** Phone, tablet or computer, decided once,
/// from the window's real size, and handed down to everything that lays itself
/// out differently for each.
///
/// Why not just ask the width: the interface can be drawn larger than normal (a
/// tablet is drawn at [kTabletBoost] times so that every target is a
/// finger-sized 44), and a layout that asked "how wide am I?" inside that would
/// see a smaller window than the device really has and mistake a tablet for a
/// phone. The window's size BEFORE any such zoom is what counts, so it is
/// measured at the top, in `UiScaleHost`, and read from here.
///
/// The rule is the one Android itself uses for its "smallest width" classes: on
/// a touch device the SHORTER side decides (so a phone held sideways is still a
/// phone); on a computer, or a browser, the width does (so a narrow window is a
/// phone-shaped layout, as it always was).
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum DeviceClass { phone, tablet, desktop }

/// Narrower than this (or, on a touch device, with a shorter side under it) is a phone.
const double kPhoneMaxWidth = 600;

/// How much larger a tablet is drawn than a computer, so a 32 px target comes to
/// 43 and a 28 px row to 38. Not more: the page needs the room.
const double kTabletBoost = 1.35;

/// A test says it is on a touch device (or not) here. Never set in the app.
///
/// **Not `defaultTargetPlatform`**: widget tests report Android for that, so
/// every test of the desktop layout in a tall window would have been judged a
/// tablet.
@visibleForTesting
bool? debugTouchPlatform;

/// Whether this runs on a device you touch: Android or iOS, as the operating
/// system says, never a browser.
bool get isTouchPlatform =>
    debugTouchPlatform ?? (!kIsWeb && (Platform.isAndroid || Platform.isIOS));

DeviceClass classifyDevice(Size window, {bool? touch}) {
  final isTouch = touch ?? isTouchPlatform;
  if (isTouch) {
    return window.shortestSide < kPhoneMaxWidth
        ? DeviceClass.phone
        : DeviceClass.tablet;
  }
  return window.width < kPhoneMaxWidth ? DeviceClass.phone : DeviceClass.desktop;
}

/// The class of the window, from outside any zoom. Without one above (a test, a
/// dialog in its own window) the size in `MediaQuery` is used instead.
class DeviceClassScope extends InheritedWidget {
  const DeviceClassScope({super.key, required this.device, required super.child});
  final DeviceClass device;

  static DeviceClass of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<DeviceClassScope>();
    return s?.device ?? classifyDevice(MediaQuery.sizeOf(context));
  }

  @override
  bool updateShouldNotify(DeviceClassScope old) => device != old.device;
}

bool isPhoneWidth(BuildContext context) =>
    DeviceClassScope.of(context) == DeviceClass.phone;

bool isTablet(BuildContext context) =>
    DeviceClassScope.of(context) == DeviceClass.tablet;

/// A tablet held upright: no room for a navigator beside the page, so it folds
/// to a rail and opens as a drawer, as on a phone.
bool isTabletPortrait(BuildContext context) =>
    isTablet(context) &&
    MediaQuery.sizeOf(context).height > MediaQuery.sizeOf(context).width;
