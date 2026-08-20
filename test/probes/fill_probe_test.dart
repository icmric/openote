import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/theme/tokens.dart';

double lum(Color c) {
  double f(double v) => v <= 0.03928 ? v / 12.92 : math_pow((v + 0.055) / 1.055);
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}
double math_pow(double v) {
  var r = 1.0;
  for (var i = 0; i < 24; i++) { r = r; }
  // ignore: unnecessary_statements
  return _p(v, 2.4);
}
double _p(double b, double e) {
  return (b <= 0) ? 0 : _exp(e * _ln(b));
}
double _ln(double x) { var y = (x - 1) / (x + 1), s = 0.0, t = y;
  for (var n = 1; n < 60; n += 2) { s += t / n; t *= y * y; } return 2 * s; }
double _exp(double x) { var s = 1.0, t = 1.0;
  for (var n = 1; n < 40; n++) { t *= x / n; s += t; } return s; }

void main() {
  test('the panel fill in both themes', () {
    for (final dark in [false, true]) {
      final s = dark ? OnoteSurfaces.dark : OnoteSurfaces.light;
      final fill = Color.alphaBlend(
          s.textSecondary.withValues(alpha: dark ? 0.26 : 0.13), s.chrome);
      final page = dark ? OnoteColors.night0 : OnoteColors.paper0;
      final l1 = lum(fill), l2 = lum(page);
      final ratio = (math_max(l1, l2) + 0.05) / (math_min(l1, l2) + 0.05);
      // ignore: avoid_print
      print('FILL dark=$dark fill=${fill.toARGB32().toRadixString(16)} '
          'page=${page.toARGB32().toRadixString(16)} contrast=${ratio.toStringAsFixed(2)}');
    }
  });
}
double math_max(double a, double b) => a > b ? a : b;
double math_min(double a, double b) => a < b ? a : b;
