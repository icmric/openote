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
  const WritingResult({
    this.spelling = const [],
    this.spellingFindings = const [],
    this.grammar = const [],
  });

  static const empty = WritingResult();

  /// Where the misspellings are.
  final List<TextRange> spelling;

  /// The same misspellings with their suggestions, best first and in the
  /// person's own English. Empty when the old word list answered (it has no
  /// suggestions to give ahead of time; the menu asks it directly).
  final List<TextFinding> spellingFindings;
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
      final spelled = <TextFinding>[];
      final others = <TextFinding>[];
      for (final f in found) {
        if (f.isSpelling) {
          // Words the person taught us stay taught.
          if (learnedWords.contains(f.word.toLowerCase())) continue;
          ranges.add(TextRange(start: f.start, end: f.end));
          spelled.add(f);
        } else {
          others.add(f);
        }
      }
      return WritingResult(
          spelling: ranges, spellingFindings: spelled, grammar: others);
    }
    // No native library: the old list, for spelling only.
    if (!spelling) return WritingResult.empty;
    final checker = SpellChecker.loaded ?? await SpellChecker.instance();
    return WritingResult(spelling: checker.check(text));
  }

  /// Suggestions for the misspelled [word], best first.
  ///
  /// [fixes] are the ones the checker attached to the underline, which are
  /// already ranked and in the person's English; they are used when there are
  /// any. Only when there are none (the old word list, which attaches nothing)
  /// does this ask the old list directly.
  static List<String> suggestionsFor(String word,
      {List<String> fixes = const []}) {
    if (fixes.isNotEmpty) return _matchCase(word, fixes);
    final checker = SpellChecker.loaded;
    return checker == null ? const [] : checker.suggest(word);
  }

  /// A suggestion for `TEH` should be `THE`, not `the`.
  static List<String> _matchCase(String word, List<String> suggestions) {
    if (word.length > 1 && word == word.toUpperCase()) {
      return [for (final s in suggestions) s.toUpperCase()];
    }
    return suggestions;
  }
}
