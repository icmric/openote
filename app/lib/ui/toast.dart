/// The one way to show a notice at the foot of the window.
///
/// Every notice goes away by itself within [kToastMax]. Flutter keeps a
/// snackbar that carries an action (our **Undo**) on screen until it is swiped
/// away, and keeps none at all while the platform reports accessible
/// navigation, which a pen or touch laptop can. Neither is wanted here, so the
/// notice is told not to persist and, where the framework would not time it
/// out, a timer of ours closes it.
library;

import 'dart:async';

import 'package:flutter/material.dart';

/// The longest any notice stays up.
const Duration kToastMax = Duration(seconds: 5);

extension OnoteToast on ScaffoldMessengerState {
  /// [showSnackBar] with a ceiling on how long it stays.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showToast(
      SnackBar bar) {
    final duration = bar.duration > kToastMax ? kToastMax : bar.duration;
    final controller = showSnackBar(SnackBar(
      key: bar.key,
      content: bar.content,
      backgroundColor: bar.backgroundColor,
      elevation: bar.elevation,
      margin: bar.margin,
      padding: bar.padding,
      width: bar.width,
      shape: bar.shape,
      hitTestBehavior: bar.hitTestBehavior,
      behavior: bar.behavior,
      action: bar.action,
      showCloseIcon: bar.showCloseIcon,
      closeIconColor: bar.closeIconColor,
      duration: duration,
      persist: false,
      animation: bar.animation,
      onVisible: bar.onVisible,
      dismissDirection: bar.dismissDirection,
      clipBehavior: bar.clipBehavior,
    ));
    // The framework starts no timer while accessible navigation is on.
    if (MediaQuery.maybeAccessibleNavigationOf(context) ?? false) {
      var closed = false;
      final timer = Timer(duration, () {
        if (!closed) controller.close();
      });
      controller.closed.whenComplete(() {
        closed = true;
        timer.cancel();
      });
    }
    return controller;
  }
}
