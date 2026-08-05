/// The design tokens — every metric the UI is allowed to use (v0.6 stage 1).
///
/// **Why this file exists.** Openote had a palette (`OnoteColors`) and it had
/// pixels, and nothing operative in between. The 2026-08-05 UI review counted
/// what that produced across `lib/ui`: **17 distinct font sizes** (including
/// half-pixel one-offs like 10.5 and 12.5), **11 icon sizes**, **13 corner
/// radii** and **12 ad-hoc opacities**. None of them repeated, and that missing
/// repetition is what "the app feels a bit off and unprofessional" actually
/// was — a professional interface is mostly the relentless reuse of a small
/// number of values, which the eye reads as rhythm without ever being told.
///
/// So the rule this file exists to enforce: **a bare `fontSize:`, `size:` on an
/// `Icon`, `BorderRadius.circular(n)` or `withValues(alpha:)` literal in
/// `lib/ui` is a review flag.** Name a token instead. If no token fits, the
/// question is whether the design needs a new token — decided once, here — not
/// whether this one widget can have its own number.
///
/// Normative source: [docs/05-style-guide.md] §3.7 (surface roles and
/// interaction alphas), §4.2a (the chrome type ramp), §5.1–5.3 (spacing,
/// radius, elevation), §6 (icon sizes), §10 (motion).
library;

import 'package:flutter/material.dart';

import 'onote_theme.dart' show OnoteColors, onoteFontFallback;

/// Type for the app's **chrome** — toolbars, panels, menus, dialogs, status.
///
/// Deliberately separate from the *editor's* content scale (16px body, Markdown
/// headings), which belongs to the user's document and is set per block. This
/// ramp is for the frame around it.
///
/// **Integer pixels only.** The half-point sizes the app had grown (10.5, 11.5,
/// 12.5) were each chosen locally and could not be reasoned about globally;
/// three of them sat within one pixel of each other on adjacent controls, which
/// is exactly the sort of not-quite-alignment a reader senses and cannot name.
abstract final class OnoteType {
  /// The UI face, named on **every** style here rather than left to
  /// `ThemeData.fontFamily`.
  ///
  /// Not belt-and-braces — load-bearing. `ButtonStyle.textStyle` overrides the
  /// `TextTheme`, so a token with a null family reaches a button and resolves
  /// to Flutter's default (Roboto) instead of Inter. That shipped: every button
  /// label in the app rendered in a different face from the text beside it.
  /// Any widget using these styles directly gets the same guarantee.
  static const family = 'Inter';

  /// Dialog and sheet titles. The largest size chrome is allowed.
  static const title = TextStyle(
      fontFamily: family,
      fontFamilyFallback: onoteFontFallback,
      fontSize: 15,
      height: 20 / 15,
      fontWeight: FontWeight.w600);

  /// The default: rows, menu items, inputs, buttons, body copy in dialogs.
  static const ui = TextStyle(
      fontFamily: family,
      fontFamilyFallback: onoteFontFallback,
      fontSize: 13,
      height: 18 / 13);

  /// Emphasis within [ui] — a row's title against its subtitle, a count.
  static const uiStrong = TextStyle(
      fontFamily: family,
      fontFamilyFallback: onoteFontFallback,
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w600);

  /// Secondary text: subtitles, tooltips, supporting lines under a control.
  static const small = TextStyle(
      fontFamily: family,
      fontFamilyFallback: onoteFontFallback,
      fontSize: 12,
      height: 16 / 12);

  /// Metadata, hints, badges, the status bar. The smallest size allowed —
  /// 9, 9.5 and 10px are retired.
  static const caption = TextStyle(
      fontFamily: family,
      fontFamilyFallback: onoteFontFallback,
      fontSize: 11,
      height: 14 / 11);

  /// Panel titles and list-group labels. **The only all-caps style**, and the
  /// only one that carries tracking; using it for anything else flattens the
  /// hierarchy, which is what happened when it labelled every surface in the
  /// app at once.
  static const overline = TextStyle(
    fontFamily: family,
    fontFamilyFallback: onoteFontFallback,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w700,
    letterSpacing: .5,
  );

  /// Code and other monospaced runs inside chrome (paths, hashes, key names).
  static const mono = TextStyle(
      fontFamily: 'JetBrains Mono',
      fontFamilyFallback: onoteFontFallback,
      fontSize: 12,
      height: 16 / 12);
}

/// Icon sizes (style guide §6). Three, not eleven.
///
/// Optical, not arithmetic: 16 is the workhorse and pairs with [OnoteType.ui];
/// 18 gives the command bar a little more presence without a second row of
/// height; 20 is for the collapsed rail and empty states, where an icon is
/// doing the work of a picture.
abstract final class OnoteIcon {
  /// Rows, panel headers, inline markers, menu leading icons.
  static const sm = 16.0;

  /// Command bar and other primary tool surfaces.
  static const md = 18.0;

  /// The navigator rail, empty states, anywhere an icon carries meaning alone.
  static const lg = 20.0;
}

/// Corner radii (style guide §5.2).
///
/// One step tighter than this document's first draft (4/8/12/16), because the
/// app's realised character is denser than v0.1 imagined and 16px reads
/// consumer-mobile at this density. Stock Material 3 must never show through:
/// un-themed M3 dialogs are 28 and M3 buttons are full stadiums.
abstract final class OnoteRadius {
  /// Inputs, checkboxes, small chips, colour swatches.
  static const sm = 4.0;

  /// Buttons, menu items, toggles, list rows, small controls.
  static const md = 6.0;

  /// Menus, popovers, cards, inline banners.
  static const lg = 8.0;

  /// Dialogs, large floating surfaces, canvas text containers.
  static const xl = 12.0;

  /// Pills only — badges, avatars.
  static const full = 999.0;

  static const smAll = BorderRadius.all(Radius.circular(sm));
  static const mdAll = BorderRadius.all(Radius.circular(md));
  static const lgAll = BorderRadius.all(Radius.circular(lg));
  static const xlAll = BorderRadius.all(Radius.circular(xl));
}

/// The 4-pt spacing scale (style guide §5.1), named so call sites stop
/// inventing 3s, 5s and 7s.
abstract final class OnoteSpace {
  static const x0 = 0.0;
  static const x1 = 2.0;
  static const x2 = 4.0;
  static const x3 = 6.0;
  static const x4 = 8.0;
  static const x5 = 12.0;
  static const x6 = 16.0;
  static const x7 = 20.0;
  static const x8 = 24.0;
  static const x9 = 32.0;

  /// Standard control padding (style guide §5.1): 8 vertical, 12 horizontal.
  static const control = EdgeInsets.symmetric(horizontal: x5, vertical: x4);

  /// Standard panel padding.
  static const panel = EdgeInsets.all(x5);

  /// A list row inside a panel: comfortable to hit, tight enough to scan.
  static const row = EdgeInsets.symmetric(horizontal: x5, vertical: x3);
}

/// State overlay opacities (style guide §3.7).
///
/// Five named values replacing the twelve ad-hoc ones the review counted. They
/// are applied to the *role's own* foreground or the primary colour, never to
/// an arbitrary picked colour — which is what made the old values impossible
/// to compare.
abstract final class OnoteAlpha {
  /// Pointer is over it.
  static const hover = .05;

  /// It is the current thing — a selected row, an active toggle.
  static const selected = .10;

  /// Selected *and* focused, or a selection that must survive a busy
  /// background.
  static const selectedStrong = .14;

  /// Being dragged, or a drop target.
  static const drag = .18;

  /// A border drawn on top of a tinted fill of the same hue.
  static const borderOnTint = .35;

  /// Disabled content that must still be readable as text.
  static const disabled = .38;
}

/// Motion durations (style guide §10). Nothing slower without a reason.
abstract final class OnoteMotion {
  /// Hover and press feedback.
  static const micro = Duration(milliseconds: 100);

  /// Panels, menus, expanding sections.
  static const standard = Duration(milliseconds: 180);

  /// Page and notebook transitions.
  static const large = Duration(milliseconds: 260);

  /// Decelerate-in — the standard curve.
  static const curve = Cubic(0.2, 0, 0, 1);
}

/// Fixed chrome dimensions, so the shell's regions agree with each other.
abstract final class OnoteSize {
  /// Every right-hand panel. One slot, one width (style guide §7c).
  static const panelWidth = 320.0;

  /// The collapsed navigator rail.
  static const railWidth = 44.0;

  /// Default button height; [buttonCompact] for dense toolbars.
  static const button = 32.0;
  static const buttonCompact = 28.0;

  /// Menu row height (style guide §7a.1).
  static const menuRow = 36.0;

  /// The status bar.
  static const statusBar = 24.0;

  /// Minimum pointer target (style guide §9). Touch wants 44.
  static const hitTarget = 32.0;
}

/// Which surface a region is, in words rather than in per-widget brightness
/// checks (style guide §3.7).
///
/// **The bug this fixes.** Sixteen files branched on `Brightness.dark` by hand
/// to pick their own background. Because each did it independently, the planner
/// picked `night0` — the *canvas* colour — so in dark mode the panel and the
/// page merged into one undifferentiated black, and light mode wobbled between
/// two papers with no rule. Naming the role makes the layering a property of
/// the theme, which is the only place that can be consistent.
///
/// Read it with `Theme.of(context).surfaces` (see [OnoteSurfacesX]).
@immutable
class OnoteSurfaces extends ThemeExtension<OnoteSurfaces> {
  const OnoteSurfaces({
    required this.canvas,
    required this.chrome,
    required this.chrome2,
    required this.raised,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
  });

  /// The page itself — and **nothing else**. Keeping this exclusive is what
  /// makes "the page is the hero" true in dark mode: chrome sits a step above
  /// the deepest colour, so the page reads as the thing being lit.
  final Color canvas;

  /// Command bar, status bar, side panels.
  final Color chrome;

  /// Insets within chrome: the navigator's sections column, wells, code tints.
  final Color chrome2;

  /// Menus, popovers, dialogs — always with elevation (§5.3).
  final Color raised;

  /// Every hairline. Regions do not draw private borders on top of the shell's.
  final Color border;

  /// Body text on chrome.
  final Color textPrimary;

  /// Metadata, subtitles, hints. **AA-compliant** — this is the token that
  /// replaces the ~130 uses of `graphite400` the contrast audit found failing
  /// at 2.80:1 (style guide §3.3).
  final Color textSecondary;

  /// Disabled and decorative only, where the 4.5:1 text rule does not apply.
  final Color textDisabled;

  static const light = OnoteSurfaces(
    canvas: OnoteColors.paper0,
    chrome: OnoteColors.paper50,
    chrome2: OnoteColors.paper100,
    raised: OnoteColors.paper0,
    border: OnoteColors.paper200,
    textPrimary: OnoteColors.graphite700,
    textSecondary: OnoteColors.graphite500,
    textDisabled: OnoteColors.graphite400,
  );

  static const dark = OnoteSurfaces(
    canvas: OnoteColors.night0,
    chrome: OnoteColors.night50,
    chrome2: OnoteColors.night100,
    raised: OnoteColors.night100,
    border: OnoteColors.night200,
    textPrimary: OnoteColors.moon100,
    textSecondary: OnoteColors.moon300,
    textDisabled: OnoteColors.moon400,
  );

  @override
  OnoteSurfaces copyWith({
    Color? canvas,
    Color? chrome,
    Color? chrome2,
    Color? raised,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textDisabled,
  }) =>
      OnoteSurfaces(
        canvas: canvas ?? this.canvas,
        chrome: chrome ?? this.chrome,
        chrome2: chrome2 ?? this.chrome2,
        raised: raised ?? this.raised,
        border: border ?? this.border,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textDisabled: textDisabled ?? this.textDisabled,
      );

  @override
  OnoteSurfaces lerp(covariant OnoteSurfaces? other, double t) {
    if (other == null) return this;
    return OnoteSurfaces(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      chrome: Color.lerp(chrome, other.chrome, t)!,
      chrome2: Color.lerp(chrome2, other.chrome2, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
    );
  }
}

extension OnoteSurfacesX on ThemeData {
  /// The surface roles for this theme. Never null — `onoteTheme` always
  /// registers them — so widgets can read it without a fallback dance.
  OnoteSurfaces get surfaces =>
      extension<OnoteSurfaces>() ??
      (brightness == Brightness.dark
          ? OnoteSurfaces.dark
          : OnoteSurfaces.light);
}

extension OnoteSurfacesContextX on BuildContext {
  /// `context.surfaces.chrome` — the short form widgets actually use.
  OnoteSurfaces get surfaces => Theme.of(this).surfaces;
}

/// Decorations for text fields that are **content, not form controls**.
///
/// The canvas editor, the page title, table cells, code and math blocks are
/// all `TextField`s, but none of them is an input in the design-system sense —
/// they are the user's document, and a border or a fill around them would be
/// chrome drawn on top of the page.
///
/// This exists because the distinction is not optional once the theme styles
/// inputs properly: `InputDecorationTheme.enabledBorder` **overrides a
/// decoration's own `border`** (Flutter resolves theme-specific borders before
/// the decoration's general one), so a field that says `border:
/// InputBorder.none` still gets the themed outline. That regressed the editor's
/// width by 8px the moment inputs were themed — caught by the edit/view metrics
/// test, which measures exactly this.
abstract final class OnoteInput {
  /// Every border and fill off, in every state. Compose with `copyWith` for
  /// hint text or padding.
  static const bare = InputDecoration(
    isDense: true,
    filled: false,
    contentPadding: EdgeInsets.zero,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
  );
}
