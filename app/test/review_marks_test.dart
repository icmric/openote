// The three kinds of writing finding must stay apart for people with the common
// kinds of colour blindness: not by hue alone, and by hues that survive.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/spell/review_marks.dart';
import 'package:openote/spell/writing_review.dart';

/// What [c] looks like to someone with the given kind of colour blindness, by
/// the usual linear-RGB simulation matrices (Machado et al., severity 1).
Color simulate(Color c, List<double> m) {
  double lin(double v) =>
      v <= .04045 ? v / 12.92 : math.pow((v + .055) / 1.055, 2.4).toDouble();
  double enc(double v) {
    final x = v.clamp(0.0, 1.0);
    return x <= .0031308 ? x * 12.92 : 1.055 * math.pow(x, 1 / 2.4) - .055;
  }

  final r = lin(c.r), g = lin(c.g), b = lin(c.b);
  return Color.from(
      alpha: 1,
      red: enc(m[0] * r + m[1] * g + m[2] * b),
      green: enc(m[3] * r + m[4] * g + m[5] * b),
      blue: enc(m[6] * r + m[7] * g + m[8] * b));
}

const protanopia = [
  .152286, 1.052583, -.204868, //
  .114503, .786281, .099216,
  -.003882, -.048116, 1.051998,
];
const deuteranopia = [
  .367322, .860646, -.227968, //
  .280085, .672501, .047413,
  -.011820, .042940, .968881,
];
const tritanopia = [
  1.255528, -.076749, -.178779, //
  -.078411, .930809, .147602,
  .004733, .691367, .303900,
];

double distance(Color a, Color b) {
  final dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b;
  return math.sqrt(dr * dr + dg * dg + db * db);
}

void main() {
  const kinds = ReviewCategory.values;

  test('each kind has its own line as well as its own colour', () {
    final lines = {for (final c in kinds) reviewLine(c)};
    expect(lines.length, kinds.length,
        reason: 'colour is never the only cue: wavy, double and dotted');
  });

  test('the colours stay apart under protan, deutan and tritan vision', () {
    for (final (name, m) in <(String, List<double>)>[
      ('normal', const [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]),
      ('protanopia', protanopia),
      ('deuteranopia', deuteranopia),
      ('tritanopia', tritanopia),
    ]) {
      for (final a in kinds) {
        for (final b in kinds) {
          if (a.index >= b.index) continue;
          final d = distance(simulate(reviewColor(a), m), simulate(reviewColor(b), m));
          // The old red and amber pair measured about .2 under deuteranopia.
          expect(d, greaterThan(.15),
              reason: '$a and $b are too alike for $name vision ($d)');
        }
      }
    }
  });

  test('the editor draws each kind in the review colour and line', () {
    for (final c in kinds) {
      final s = reviewUnderline(c);
      expect(s.decorationColor, reviewColor(c));
      expect(s.decorationStyle, reviewLine(c));
    }
  });
}
