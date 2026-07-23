import 'package:flutter/material.dart';

/// Style-guide tokens (docs/05-style-guide.md §3). Single source of truth for color.
abstract final class OnoteColors {
  // Ink (primary)
  static const ink50 = Color(0xFFEEF0FF);
  static const ink100 = Color(0xFFDFE2FF);
  static const ink200 = Color(0xFFC2C7FB);
  static const ink300 = Color(0xFF9AA0F5);
  static const ink400 = Color(0xFF7B7FEE);
  static const ink500 = Color(0xFF5B5BE6);
  static const ink600 = Color(0xFF4A45D6);
  static const ink700 = Color(0xFF3D38B4);
  static const ink800 = Color(0xFF302B8C);
  static const ink900 = Color(0xFF20205C);
  // Brass (accent)
  static const brass100 = Color(0xFFFBEFD3);
  static const brass400 = Color(0xFFEBB24A);
  static const brass500 = Color(0xFFD9971F);
  static const brass700 = Color(0xFF9A6A12);
  // Paper & graphite (light)
  static const paper0 = Color(0xFFFFFFFF);
  static const paper50 = Color(0xFFFAF9F7);
  static const paper100 = Color(0xFFF2F1ED);
  static const paper200 = Color(0xFFE7E5DF);
  static const paper300 = Color(0xFFD6D3CA);
  static const graphite400 = Color(0xFF9A968C);
  static const graphite500 = Color(0xFF6E6B63);
  static const graphite700 = Color(0xFF403D38);
  static const graphite900 = Color(0xFF211F1B);
  // Night ink (dark)
  static const night0 = Color(0xFF17161C);
  static const night50 = Color(0xFF1E1D24);
  static const night100 = Color(0xFF26252E);
  static const night200 = Color(0xFF33313C);
  static const night300 = Color(0xFF45424F);
  static const moon0 = Color(0xFFF6F4FA);
  static const moon100 = Color(0xFFE6E3EC);
  static const moon300 = Color(0xFFB8B4C2);
  static const moon400 = Color(0xFF8E8A99);
  // Semantic
  static const danger = Color(0xFFC63838);
  static const success = Color(0xFF2E8B57);

  /// Default content-ink pen colors (style guide §3.6).
  static const penColors = <Color>[
    graphite900,
    Color(0xFF2F6FB3),
    danger,
    success,
    Color(0xFF6A4BC0),
    brass500,
  ];
  static const highlighterColors = <Color>[
    Color(0xFFF7E27A),
    Color(0xFFB6E39A),
    Color(0xFFF3B0C6),
    Color(0xFFA8CCF0),
  ];
}

ThemeData onoteTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: dark ? OnoteColors.ink400 : OnoteColors.ink500,
    onPrimary: Colors.white,
    secondary: OnoteColors.brass400,
    onSecondary: OnoteColors.graphite900,
    error: OnoteColors.danger,
    onError: Colors.white,
    surface: dark ? OnoteColors.night50 : OnoteColors.paper50,
    onSurface: dark ? OnoteColors.moon100 : OnoteColors.graphite700,
    surfaceContainerHighest: dark ? OnoteColors.night100 : OnoteColors.paper100,
    outline: dark ? OnoteColors.night300 : OnoteColors.paper300,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: dark ? OnoteColors.night0 : OnoteColors.paper0,
    dividerColor: dark ? OnoteColors.night200 : OnoteColors.paper200,
    fontFamily: null, // system UI font as Inter-fallback until fonts are bundled
    visualDensity: VisualDensity.compact,
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
  );
}
