import 'package:flutter/material.dart';

import 'tokens.dart';

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

/// Desktop apps do not ripple.
///
/// Material's ink splash is a touch affordance — it exists to show a finger
/// where it landed on a surface it was covering. On a pointer device it reads
/// as a phone gesture echo, and it was one of the loudest "this is a mobile
/// toolkit" tells in the 2026-08 UI review. Hover and pressed *tints*
/// (`OnoteAlpha`) carry the same information without the animation, so the
/// theme installs `NoSplash.splashFactory` app-wide and on every button.

/// The app theme.
///
/// **Everything Material renders is themed here** (v0.6 stage 2). Before this
/// pass the function set colours, the font and density and stopped — so every
/// Material widget the app reached for rendered in stock *mobile* Material 3
/// beside the hand-rolled dense desktop panels: full-window-width snackbar
/// slabs, stadium-pill buttons, 28px-radius dialogs, mobile-metric menus and
/// pickers. Two design languages in one window, which is what "it feels a bit
/// off and unprofessional" turned out to be.
///
/// The rule for anything added later: if a Material component can appear in
/// the app, it gets a theme here. A component that inherits M3 defaults is a
/// component that will look like a different product.
ThemeData onoteTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final surfaces = dark ? OnoteSurfaces.dark : OnoteSurfaces.light;
  final primary = dark ? OnoteColors.ink400 : OnoteColors.ink500;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: dark ? OnoteColors.graphite900 : Colors.white,
    secondary: OnoteColors.brass400,
    onSecondary: OnoteColors.graphite900,
    error: OnoteColors.danger,
    onError: Colors.white,
    surface: surfaces.chrome,
    onSurface: surfaces.textPrimary,
    surfaceContainerHighest: surfaces.chrome2,
    outline: dark ? OnoteColors.night300 : OnoteColors.paper300,
  );

  // The chrome ramp (style guide §4.2a) as Material's text theme, so anything
  // that reads `Theme.of(context).textTheme` — menus, dialogs, buttons, list
  // tiles — lands on the ramp without each call site restating it.
  //
  // **The family is applied here, explicitly.** `ThemeData.fontFamily` only
  // reaches the text theme Flutter *derives from typography* — pass an explicit
  // `textTheme` and its null families stay null, so they resolve to Flutter's
  // default (Roboto). That is not theoretical: it rendered every button label
  // in the app in a different face from everything around it, which is exactly
  // the per-surface inconsistency this pass exists to remove.
  final text = TextTheme(
    titleMedium: OnoteType.title,
    titleSmall: OnoteType.uiStrong,
    bodyMedium: OnoteType.ui,
    bodySmall: OnoteType.small,
    labelLarge: OnoteType.ui,
    labelMedium: OnoteType.small,
    labelSmall: OnoteType.caption,
  ).apply(
    fontFamily: 'Inter',
    fontFamilyFallback: onoteFontFallback,
    bodyColor: surfaces.textPrimary,
    displayColor: surfaces.textPrimary,
  );

  // Focus is an accessibility requirement (style guide §9), and M3's default
  // is nearly invisible on these surfaces.
  final focusBorder = OutlineInputBorder(
    borderRadius: OnoteRadius.smAll,
    borderSide: BorderSide(color: primary, width: 2),
  );
  final restBorder = OutlineInputBorder(
    borderRadius: OnoteRadius.smAll,
    borderSide: BorderSide(color: surfaces.border),
  );

  ButtonStyle buttonBase({Color? fg, Color? bg}) => ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(
            Size(0, OnoteSize.buttonCompact)),
        padding: const WidgetStatePropertyAll(OnoteSpace.control),
        textStyle: const WidgetStatePropertyAll(OnoteType.ui),
        foregroundColor: fg == null ? null : WidgetStatePropertyAll(fg),
        backgroundColor: bg == null ? null : WidgetStatePropertyAll(bg),
        // Never the stadium. This single line is the difference between
        // "an app" and "a Material demo" on every dialog in the product.
        shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: OnoteRadius.mdAll)),
        splashFactory: NoSplash.splashFactory,
        visualDensity: VisualDensity.compact,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: surfaces.chrome,
    canvasColor: surfaces.canvas,
    dividerColor: surfaces.border,
    // Bundled Inter (style guide §4.1) — the app finally looks the same on
    // every OS. The fallback chain stays exactly as verified in review §O.3:
    // it resolves the math/symbol glyphs Inter lacks, and Symbol/Wingdings
    // must stay LAST in it (they claim U+00AC with the wrong glyph).
    fontFamily: 'Inter',
    fontFamilyFallback: onoteFontFallback,
    visualDensity: VisualDensity.compact,
    textTheme: text,
    splashFactory: NoSplash.splashFactory,
    extensions: [surfaces],

    dividerTheme: DividerThemeData(
        color: surfaces.border, thickness: 1, space: 1),

    iconTheme: IconThemeData(size: OnoteIcon.sm, color: surfaces.textPrimary),

    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      textStyle: OnoteType.caption.copyWith(
          color: dark ? OnoteColors.graphite900 : OnoteColors.moon0),
      decoration: BoxDecoration(
        color: dark ? OnoteColors.moon100 : OnoteColors.graphite900,
        borderRadius: OnoteRadius.smAll,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    ),

    // ── Buttons ────────────────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(style: buttonBase()),
    elevatedButtonTheme: ElevatedButtonThemeData(style: buttonBase()),
    textButtonTheme: TextButtonThemeData(style: buttonBase()),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: buttonBase().copyWith(
        side: WidgetStatePropertyAll(BorderSide(color: surfaces.border)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        iconSize: const WidgetStatePropertyAll(OnoteIcon.sm),
        splashFactory: NoSplash.splashFactory,
        shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: OnoteRadius.mdAll)),
        visualDensity: VisualDensity.compact,
      ),
    ),

    // ── Menus (style guide §7a.1) ──────────────────────────────────────
    //
    // 36px rows and `raised` surfaces, against M3's taller mobile metrics.
    popupMenuTheme: PopupMenuThemeData(
      color: surfaces.raised,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      textStyle: OnoteType.ui.copyWith(color: surfaces.textPrimary),
      shape: RoundedRectangleBorder(
        borderRadius: OnoteRadius.lgAll,
        side: BorderSide(color: surfaces.border),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: OnoteSpace.x2),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(surfaces.raised),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(4),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: OnoteSpace.x2)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: OnoteRadius.lgAll,
          side: BorderSide(color: surfaces.border),
        )),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        minimumSize:
            const WidgetStatePropertyAll(Size(0, OnoteSize.menuRow)),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: OnoteSpace.x5)),
        textStyle: const WidgetStatePropertyAll(OnoteType.ui),
        splashFactory: NoSplash.splashFactory,
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
        visualDensity: VisualDensity.compact,
      ),
    ),
    menuBarTheme: MenuBarThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(surfaces.chrome),
        elevation: const WidgetStatePropertyAll(0),
      ),
    ),

    // ── Dialogs ────────────────────────────────────────────────────────
    dialogTheme: DialogThemeData(
      backgroundColor: surfaces.raised,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: OnoteRadius.xlAll,
        side: BorderSide(color: surfaces.border),
      ),
      titleTextStyle: OnoteType.title.copyWith(color: surfaces.textPrimary),
      contentTextStyle: OnoteType.ui.copyWith(color: surfaces.textPrimary),
    ),

    // Date and time pickers are the planner's flagship interactions and were
    // the most obviously *mobile* surfaces in the app.
    datePickerTheme: DatePickerThemeData(
      backgroundColor: surfaces.raised,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: OnoteRadius.xlAll,
        side: BorderSide(color: surfaces.border),
      ),
      headerBackgroundColor: surfaces.chrome2,
      headerForegroundColor: surfaces.textPrimary,
      headerHelpStyle: OnoteType.small.copyWith(color: surfaces.textSecondary),
      headerHeadlineStyle: OnoteType.title.copyWith(fontSize: 22),
      dayStyle: OnoteType.ui,
      weekdayStyle: OnoteType.caption.copyWith(color: surfaces.textSecondary),
      yearStyle: OnoteType.ui,
      dayShape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: OnoteRadius.mdAll)),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: surfaces.raised,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: OnoteRadius.xlAll,
        side: BorderSide(color: surfaces.border),
      ),
      helpTextStyle: OnoteType.small.copyWith(color: surfaces.textSecondary),
      dialTextStyle: OnoteType.ui,
      hourMinuteShape: const RoundedRectangleBorder(
          borderRadius: OnoteRadius.lgAll),
    ),

    // ── Toasts (style guide §7 Toasts) ─────────────────────────────────
    //
    // The single highest-leverage line in this file: 52 call sites were
    // rendering a full-window-width mobile slab to say "Saved".
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      width: 440,
      backgroundColor: dark ? OnoteColors.night200 : OnoteColors.graphite900,
      contentTextStyle: OnoteType.small.copyWith(
          color: dark ? OnoteColors.moon0 : OnoteColors.paper0),
      actionTextColor: dark ? OnoteColors.ink300 : OnoteColors.ink200,
      elevation: 6,
      shape: const RoundedRectangleBorder(borderRadius: OnoteRadius.lgAll),
      insetPadding: const EdgeInsets.all(OnoteSpace.x6),
    ),

    // ── Inputs & controls ──────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: surfaces.chrome2,
      contentPadding: OnoteSpace.control,
      border: restBorder,
      enabledBorder: restBorder,
      focusedBorder: focusBorder,
      hintStyle: OnoteType.ui.copyWith(color: surfaces.textSecondary),
      labelStyle: OnoteType.small.copyWith(color: surfaces.textSecondary),
      helperStyle: OnoteType.caption.copyWith(color: surfaces.textSecondary),
      errorStyle: OnoteType.caption.copyWith(color: OnoteColors.danger),
    ),
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: surfaces.textSecondary, width: 1.4),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(3))),
      splashRadius: 0,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    radioTheme: const RadioThemeData(
        splashRadius: 0, visualDensity: VisualDensity.compact),
    switchTheme: const SwitchThemeData(splashRadius: 0),
    chipTheme: ChipThemeData(
      backgroundColor: surfaces.chrome2,
      side: BorderSide(color: surfaces.border),
      labelStyle: OnoteType.small.copyWith(color: surfaces.textPrimary),
      padding: const EdgeInsets.symmetric(
          horizontal: OnoteSpace.x4, vertical: OnoteSpace.x1),
      shape: const RoundedRectangleBorder(borderRadius: OnoteRadius.mdAll),
    ),
    listTileTheme: ListTileThemeData(
      dense: true,
      minVerticalPadding: OnoteSpace.x3,
      titleTextStyle: OnoteType.ui.copyWith(color: surfaces.textPrimary),
      subtitleTextStyle:
          OnoteType.caption.copyWith(color: surfaces.textSecondary),
      shape: const RoundedRectangleBorder(borderRadius: OnoteRadius.mdAll),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: primary,
      linearMinHeight: 3,
      linearTrackColor: surfaces.chrome2,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(8),
      radius: const Radius.circular(OnoteRadius.sm),
      thumbColor: WidgetStatePropertyAll(
          surfaces.textDisabled.withValues(alpha: .5)),
      crossAxisMargin: 2,
    ),
  );
}
