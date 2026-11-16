/// How each kind of writing finding looks, in the page and in the review panel:
/// one place, so the underline under a word and the dot beside it in the panel
/// can never disagree.
///
/// **Safe for colour blindness by default.** The hues are the orange, blue and
/// reddish-purple of the Okabe–Ito set, which stay apart for red-green and
/// blue-yellow colour vision; and colour is never the only cue, because each
/// kind also has its own line: spelling wavy, grammar double, punctuation
/// dotted. (The earlier red / amber pair was the one that merged.)
library;

import 'package:flutter/painting.dart';

import 'writing_review.dart';

/// The colour of [c]'s underline and dot.
Color reviewColor(ReviewCategory c) => switch (c) {
      ReviewCategory.spelling => const Color(0xFFD55E00),
      ReviewCategory.grammar => const Color(0xFF2B7FD6),
      ReviewCategory.punctuation => const Color(0xFFB5469B),
    };

/// The kind of line under a word of kind [c].
TextDecorationStyle reviewLine(ReviewCategory c) => switch (c) {
      ReviewCategory.spelling => TextDecorationStyle.wavy,
      ReviewCategory.grammar => TextDecorationStyle.double,
      ReviewCategory.punctuation => TextDecorationStyle.dotted,
    };

/// The text style that draws [c]'s underline, to merge over a span's own.
TextStyle reviewUnderline(ReviewCategory c) => TextStyle(
      decoration: TextDecoration.underline,
      decorationStyle: reviewLine(c),
      decorationColor: reviewColor(c),
    );

/// A word the app itself has just corrected: a quiet dotted line in a neutral
/// blue-grey, which is none of the three above.
const TextStyle correctedUnderline = TextStyle(
  decoration: TextDecoration.underline,
  decorationStyle: TextDecorationStyle.dotted,
  decorationColor: Color(0xFF8A94A6),
);
