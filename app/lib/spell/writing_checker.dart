/// The one place the editor asks "what is wrong with this text?".
///
/// Two checkers sit behind it. **Harper** (`rust/onote_text`, bundled) knows the
/// person's own English and reads grammar as well as spelling. The **word list**
/// in `spell_checker.dart` is the fallback for a build without the native
/// library, and answers spelling only. The editor does not need to know which it
/// is talking to: that is the seam the plan (`docs/planning/backlog.md` §1.16)
/// asked for, and it is why a missing library costs a feature, not the app.
///
/// **Other languages are not touched.** [WritingChecker.check] returns nothing
/// when the dialect is null, and the dialect is null whenever the person is not
/// writing English (see `writing_language.dart`). Before this, the English list
/// was applied to every language, which underlined all of a German note.
library;

import 'dart:ui' show TextRange;

import '../core/onote_text.dart';
import 'spell_checker.dart';

/// What a check found. [spelling] ranges are drawn as the red wavy line; every
/// finding in [grammar] as the blue one, with its message and fixes available
/// from the right-click menu.
class WritingResult {
  const WritingResult({this.spelling = const [], this.grammar = const []});

  static const empty = WritingResult();

  final List<TextRange> spelling;
  final List<TextFinding> grammar;

  bool get isEmpty => spelling.isEmpty && grammar.isEmpty;
}

class WritingChecker {
  WritingChecker._();

  /// Check [text] (a block's raw Markdown) as the English of [dialect].
  ///
  /// [dialect] null means "not English": nothing is checked.
  static Future<WritingResult> check(
    String text, {
    required EnglishDialect? dialect,
    required bool spelling,
    required bool grammar,
  }) async {
    if (dialect == null || (!spelling && !grammar) || text.trim().isEmpty) {
      return WritingResult.empty;
    }
    if (OnoteText.available) {
      final want = (spelling ? kWantSpelling : 0) | (grammar ? kWantGrammar : 0);
      final found = await OnoteText.check(
          SpellChecker.proseOnly(text), dialect, want);
      final ranges = <TextRange>[];
      final others = <TextFinding>[];
      for (final f in found) {
        if (f.isSpelling) {
          // Words the person taught us stay taught.
          if (learnedWords.contains(f.word.toLowerCase())) continue;
          ranges.add(TextRange(start: f.start, end: f.end));
        } else {
          others.add(f);
        }
      }
      return WritingResult(spelling: ranges, grammar: others);
    }
    // No native library: the old list, for spelling only.
    if (!spelling) return WritingResult.empty;
    final checker = SpellChecker.loaded ?? await SpellChecker.instance();
    return WritingResult(spelling: checker.check(text));
  }

  /// Suggestions for the misspelled [word], best first.
  static Future<List<String>> suggest(String word,
      {required EnglishDialect? dialect}) async {
    if (dialect == null) return const [];
    if (OnoteText.available) {
      final s = await OnoteText.suggest(word, dialect);
      if (s.isNotEmpty) return _matchCase(word, s);
    }
    final checker = SpellChecker.loaded;
    return checker == null ? const [] : checker.suggest(word);
  }

  /// A suggestion for `Teh` should be `The`, and for `TEH` should be `THE`.
  static List<String> _matchCase(String word, List<String> suggestions) {
    if (word.length > 1 && word == word.toUpperCase()) {
      return [for (final s in suggestions) s.toUpperCase()];
    }
    return suggestions;
  }
}
