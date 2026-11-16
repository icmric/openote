// Every kind of pressable control gets the click pointer from the THEME, so a
// new button cannot be forgotten: it is set once, here, and this fails when a
// control family is left out. ("New section" and "New group" were popup-menu rows
// and had the plain arrow.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/theme/onote_theme.dart';

MouseCursor? resolve(Object? c) {
  if (c == null) return null;
  if (c is WidgetStateProperty<MouseCursor?>) {
    return c.resolve(<WidgetState>{});
  }
  if (c is MouseCursor) return c;
  return null;
}

void main() {
  for (final b in Brightness.values) {
    test('the ${b.name} theme gives every pressable family the click pointer',
        () {
      final t = onoteTheme(b);
      final families = <String, Object?>{
        'popup menu rows': t.popupMenuTheme.mouseCursor,
        'menu buttons': t.menuButtonTheme.style?.mouseCursor,
        'filled': t.filledButtonTheme.style?.mouseCursor,
        'elevated': t.elevatedButtonTheme.style?.mouseCursor,
        'text': t.textButtonTheme.style?.mouseCursor,
        'outlined': t.outlinedButtonTheme.style?.mouseCursor,
        'icon': t.iconButtonTheme.style?.mouseCursor,
        'segmented': t.segmentedButtonTheme.style?.mouseCursor,
        'tabs': t.tabBarTheme.mouseCursor,
        'list tiles': t.listTileTheme.mouseCursor,
        'checkbox': t.checkboxTheme.mouseCursor,
        'radio': t.radioTheme.mouseCursor,
        'switch': t.switchTheme.mouseCursor,
      };
      for (final e in families.entries) {
        expect(resolve(e.value), SystemMouseCursors.click,
            reason: '${e.key} must show the click pointer');
      }
    });
  }
}
