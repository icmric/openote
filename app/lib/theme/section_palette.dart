import 'package:flutter/rendering.dart';

import 'onote_theme.dart' show OnoteColors;

/// One colour a section can wear, with the value that suits each theme.
///
/// Every section is drawn with an open ring in its colour, so the colour has to
/// hold up against both the dark and the light navigator; each one therefore
/// has its own value per theme rather than one value used on both.
class SectionHue {
  const SectionHue(this.token, this.name, this.dark, this.light);

  /// What is saved on the section. Never change one once released: it is
  /// stored in people's notebooks.
  final String token;

  /// Shown as the tooltip in the colour picker.
  final String name;
  final Color dark;
  final Color light;
}

/// The eight colours new sections receive, in order, and the eight the picker
/// offers.
///
/// They run round the colour wheel, so a column of sections flows from one
/// colour into the next and the eighth sits beside the first. Lightness varies
/// a little so neighbours still tell apart without hue. (Worked out on the
/// design canvas; see `docs/planning/design-mockups.md`.)
const List<SectionHue> sectionPalette = [
  SectionHue('coral', 'Coral', Color(0xFFEE7B6B), Color(0xFFCC4435)),
  SectionHue('brass', 'Brass', Color(0xFFEBB24A), Color(0xFFB27608)),
  SectionHue('lime', 'Lime', Color(0xFFA9C95A), Color(0xFF647F17)),
  SectionHue('fern', 'Fern', Color(0xFF58B98A), Color(0xFF2A7F52)),
  SectionHue('sky', 'Sky', Color(0xFF5AB4E5), Color(0xFF1B7DB8)),
  // Exactly the app's own accent (OnoteColors.ink400 / ink500), so an uncoloured
  // section and one given Ink are the same colour.
  SectionHue('ink', 'Ink', Color(0xFF7B7FEE), Color(0xFF5B5BE6)),
  SectionHue('orchid', 'Orchid', Color(0xFFC689E4), Color(0xFF9347BE)),
  SectionHue('rose', 'Rose', Color(0xFFF08DB5), Color(0xFFC93E7A)),
];

/// Colours saved by earlier versions, which sections made then still carry.
/// They are left exactly as they were: a notebook is never recoloured under
/// the person who made it. They are no longer offered in the picker, but the
/// one a section already has is still shown there as its current choice.
const Map<String, Color> _legacy = {
  'brass-400': OnoteColors.brass400,
  'green': OnoteColors.success,
  'blue': Color(0xFF2F6FB3),
  'violet': Color(0xFF6A4BC0),
  'red': OnoteColors.danger,
};

bool isLegacySectionColor(String? token) => _legacy.containsKey(token);

/// The colour a section token paints as. No token (a section nobody coloured)
/// is the app's own ink, which is also the palette's `ink`.
Color sectionColorFor(String? token, bool dark) {
  final legacy = _legacy[token];
  if (legacy != null) return legacy;
  for (final h in sectionPalette) {
    if (h.token == token) return dark ? h.dark : h.light;
  }
  return dark ? OnoteColors.ink400 : OnoteColors.ink500;
}

/// The token to show as chosen in the picker. A section with no token looks
/// like `ink`, so that is the one ringed.
String? pickerTokenFor(String? token) => token ?? 'ink';

/// A group's colour: its first section's colour, softened towards slate, so the
/// group reads as one with the sections on its rail without needing a palette
/// of its own. With nothing inside yet it is plain slate.
Color groupColorFor(String? firstSectionToken, bool dark,
    {required bool hasSections}) {
  final slate = dark ? const Color(0xFF8FA3BF) : const Color(0xFF5A6F8C);
  if (!hasSections) return slate;
  return Color.lerp(slate, sectionColorFor(firstSectionToken, dark), .55)!;
}

/// The open ring that marks a section: three-quarters of a circle and a dot
/// in the gap, the shape of Openote's own icon. [color] is the section's.
class SectionRingPainter extends CustomPainter {
  const SectionRingPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 16 x 16 grid and scaled, so it matches the design exactly.
    final s = size.width / 16;
    canvas.scale(s);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    const r = 5.6;
    const circumference = 2 * 3.141592653589793 * r;
    const start = -55 * 3.141592653589793 / 180;
    const sweep = 27 / circumference * 2 * 3.141592653589793;
    canvas.drawArc(Rect.fromCircle(center: const Offset(8, 8), radius: r),
        start, sweep, false, stroke);
    canvas.drawCircle(
        const Offset(11.7, 3.4), 1.7, Paint()..color = color);
  }

  @override
  bool shouldRepaint(SectionRingPainter old) => old.color != color;
}
