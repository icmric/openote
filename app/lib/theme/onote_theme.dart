import 'package:flutter/material.dart';

/// Style-guide tokens (docs/05-style-guide.md §3). Single source of truth for color.
/// Fallback families searched, in order, for glyphs the chosen font lacks.
///
/// This is what makes imported OneNote notes legible. A maths note is full of
/// characters outside a UI font's coverage — ∃ ∀ ∧ ∨ ⊆ ⊘ ¬ ℝ, arrows, Greek —
/// and a font without the glyph renders nothing useful. Flutter only consults
/// these when the primary family has no glyph, so naming them costs nothing for
/// ordinary text and is the difference between a symbol and a blank box.
///
/// Deliberately cross-platform and ordered widest-coverage-first, because we
/// bundle no fonts yet (style guide §4.1): Windows ships Segoe UI Symbol and
/// Cambria Math, macOS/iOS ship Apple Symbols and STIX, most Linux desktops ship
/// DejaVu Sans and Noto. Naming a family that isn't installed is harmless — it
/// is skipped. Bundling a known-coverage font is the durable fix; until then
/// this removes the worst of the platform variance.
///
/// **Order is load-bearing, not cosmetic.** Verified against the actual cmaps of
/// the shipped Windows fonts: `Segoe UI Symbol` covers ∧ ∀ ∃ ℤ ⊆ ∅ and 7 500
/// other code points, while `Symbol` and `Wingdings` cover only ~400 — *and they
/// also claim `U+00AC`*, where Symbol's glyph is a left arrow rather than the
/// negation sign. Putting them last means they are only ever reached for
/// characters nothing else defines, i.e. the Private Use Area. Move them earlier
/// and ordinary punctuation starts rendering as dingbats.
///
/// Family names are the OS-resolvable ones, checked against each font's name
/// table — a misspelled family fails silently, which is the worst possible
/// failure mode here. `Cambria Math` is a separate face inside `cambria.ttc`.
const List<String> onoteFontFallback = <String>[
  'Segoe UI Symbol', // Windows: broad symbol/arrow/maths coverage
  'Cambria Math', // Windows: maths operators, blackboard bold
  'Apple Symbols', // macOS
  'STIX Two Math', // macOS/cross-platform maths
  'Noto Sans Symbols 2',
  'Noto Sans Math',
  'DejaVu Sans', // Linux workhorse, very wide BMP coverage
  // Office stores a Symbol/Wingdings character as U+F000+n in the Private Use
  // Area, and no ordinary font claims the PUA — so those characters render as
  // blank boxes however good the rest of the fallback chain is. Microsoft's own
  // Symbol and Wingdings map that range in their cmaps, so naming them resolves
  // the glyph the document actually meant. Deliberately *not* translated to
  // "real" Unicode in the importer: Symbol's 0xAC is ← while a user typing ¬
  // means U+00AC, and there is no way to tell those apart after the fact, so
  // guessing would corrupt content. Let the font that defines the encoding draw
  // it.
  'Symbol',
  'Wingdings',
  'Segoe UI Emoji',
  'Apple Color Emoji',
  'Noto Color Emoji',
];

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
    // Bundled Inter (style guide §4.1) — the app finally looks the same on
    // every OS. The fallback chain stays exactly as verified in review §O.3:
    // it resolves the math/symbol glyphs Inter lacks, and Symbol/Wingdings
    // must stay LAST in it (they claim U+00AC with the wrong glyph).
    fontFamily: 'Inter',
    fontFamilyFallback: onoteFontFallback,
    visualDensity: VisualDensity.compact,
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
  );
}
