/// Small automatic fixes as a word is finished: a certain typo (`teh` → `the`),
/// the capital at the start of a sentence, and a lone `i`.
///
/// **Timid on purpose.** A wrong silent change is worse than a typo left for the
/// person to see, so every rule here is a reason to do nothing: not a single
/// typed character, not a word with a digit or a capital in the middle, not
/// anything inside code, a link or an equation, not a name that merely follows
/// a lower-case word. When in doubt, the text is left exactly as typed.
///
/// **English only.** The caller passes [correct] and the two switches only when
/// the person is writing English (`AppState.writingDialect != null`); for any
/// other language nothing is passed and nothing here runs. That is the whole
/// guarantee that German nouns, French accents and Chinese text are never
/// "fixed" — it is one gate in one place, not a check in each rule.
///
/// **Undo.** Two ways back, and they do the same thing. Backspace straight
/// after a fix puts the word back as typed and keeps the boundary character
/// (see `_LiveMarkdownSession._undoAutoFix`), which is how every word processor
/// does it, and remembers the word so it is not fixed again. **Ctrl+Z straight
/// after a fix does exactly that** (`AppState.undo` asks for it first): without
/// it, the app's own undo steps back a whole burst of typing, so the first
/// Ctrl+Z took the entire word away instead of the one change the person
/// objected to. Once anything else has been typed, Ctrl+Z is the ordinary undo.
library;

import 'package:flutter/services.dart';

import '../spell/spell_checker.dart';

/// What a fix did, enough to reverse it.
class AutoFix {
  const AutoFix({
    required this.value,
    required this.original,
    required this.replacement,
    required this.start,
    required this.before,
  });

  /// The edited value, to put in the field.
  final TextEditingValue value;

  /// The word as typed, and what it became.
  final String original;
  final String replacement;

  /// Where the word starts.
  final int start;

  /// The value as it was before the fix: the typed word and its boundary
  /// character, caret after it. Backspace restores this.
  final TextEditingValue before;
}

/// Characters that finish a word.
const String _boundaries = ' \n\t.,;:!?';

/// Before a word, characters that may sit directly in front of it. Anything
/// else (a slash, an @, a #, a hyphen, a digit) means this is not a plain word.
const String _openers = ' \n\t([{"“‘\'*_~';

final RegExp _letter = RegExp(r"[\p{L}'’]", unicode: true);

/// Words that end in a full stop without ending a sentence. Lower case, no dot.
const Set<String> _abbreviations = {
  'e.g', 'i.e', 'etc', 'vs', 'dr', 'mr', 'mrs', 'ms', 'prof', 'st', 'no',
  'fig', 'eq', 'approx', 'cf', 'al', 'inc', 'ltd', 'jr', 'sr', 'ca', 'est',
};

/// `i`, and `i'm` and friends: the English pronoun, always a capital.
final RegExp _pronounI = RegExp(r"^i(?:['’](?:m|ll|ve|d|s))?$");

/// The fix for the word just finished in [next], or null to leave it alone.
///
/// [old] is the value before the keystroke. [correct] answers the sure
/// correction for a word (the checker), or null; it is only asked when
/// [autoCorrect] is on. [keep] holds words the person has put back as typed.
AutoFix? computeAutoFix({
  required TextEditingValue old,
  required TextEditingValue next,
  required bool autoCorrect,
  required bool autoCapitalize,
  String? Function(String word)? correct,
  Set<String> keep = const {},
}) {
  if (!autoCorrect && !autoCapitalize) return null;
  final t = next.text;
  final sel = next.selection;
  if (!sel.isValid || !sel.isCollapsed) return null;
  // An input method mid-composition owns the text until it commits.
  if (next.composing.isValid && !next.composing.isCollapsed) return null;

  // Exactly one character, typed at the caret: not a paste, not a delete, not
  // a programmatic change (undo, a suggestion, a list continuation).
  if (t.length != old.text.length + 1) return null;
  final caret = sel.baseOffset;
  if (caret < 2 || caret > t.length) return null;
  if ('${t.substring(0, caret - 1)}${t.substring(caret)}' != old.text) {
    return null;
  }
  final typed = t[caret - 1];
  if (!_boundaries.contains(typed)) return null;

  // The word directly before it.
  final we = caret - 1;
  var ws = we;
  while (ws > 0 && _letter.hasMatch(t[ws - 1])) {
    ws--;
  }
  // A leading apostrophe is a quote mark, not part of the word.
  while (ws < we && (t[ws] == "'" || t[ws] == '’')) {
    ws++;
  }
  if (ws >= we) return null;
  final word = t.substring(ws, we);
  if (!word.contains(RegExp(r'\p{L}', unicode: true))) return null;
  if (ws > 0 && !_openers.contains(t[ws - 1])) return null;

  var fixed = word;
  final lower = word.toLowerCase();
  final first = word[0];
  final startsSentence = _startsSentence(t, ws);

  if (autoCorrect &&
      correct != null &&
      // Two letters is enough now that the answer comes from a list: `im` is
      // a slip for I'm, and nothing else.
      word.length >= 2 &&
      !keep.contains(lower) &&
      // A capital in the middle of a sentence is a name or an acronym; names
      // the dictionary lacks must not be "corrected" into other words.
      (first == first.toLowerCase() || startsSentence) &&
      !word.contains("'") &&
      !word.contains('’')) {
    final c = correct(word);
    if (c != null && c.isNotEmpty && c != word) fixed = c;
  }

  if (autoCapitalize) {
    final f = fixed;
    // Not on a full stop: "i.e." must not become "I.e.".
    if (typed != '.' && _pronounI.hasMatch(f)) {
      fixed = 'I${f.substring(1)}';
    } else if (startsSentence &&
        f == f.toLowerCase() &&
        f[0] != f[0].toUpperCase() &&
        // One letter is capitalised only if it is the word "a": a line that
        // starts "x = 5" is an equation, and "e.g." is an abbreviation.
        (f.length > 1 || (f == 'a' && typed != '.'))) {
      fixed = '${f[0].toUpperCase()}${f.substring(1)}';
    }
  }

  if (fixed == word) return null;

  // Prose only: inside `code`, a [[link]], a URL or an equation, nothing is
  // touched. (The same blanking the grammar checker is shown.) Asked last,
  // because it reads the whole block and almost every word needs no fix.
  if (SpellChecker.proseOnly(t).substring(ws, we) != word) return null;

  final newText = t.replaceRange(ws, we, fixed);
  final newCaret = caret + (fixed.length - word.length);
  return AutoFix(
    value: TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCaret),
    ),
    original: word,
    replacement: fixed,
    start: ws,
    before: next,
  );
}

/// Is the word starting at [ws] the first of a sentence?
bool _startsSentence(String t, int ws) {
  final lineStart = ws == 0 ? 0 : t.lastIndexOf('\n', ws - 1) + 1;
  final prefix = t.substring(lineStart, ws);
  // Start of a line, or only a list, quote, heading or checkbox marker before.
  if (RegExp(r'^\s*(?:(?:[-*+>]|\d+[.)]|#{1,6})\s+)*(?:\[[ xX]\]\s+)?$')
      .hasMatch(prefix)) {
    return true;
  }
  // Otherwise: the last thing before it must be . ! ? (possibly followed by
  // closing quotes or brackets) and the word it ends must not be an
  // abbreviation or a number.
  var i = prefix.length - 1;
  while (i >= 0 && ' \t'.contains(prefix[i])) {
    i--;
  }
  if (i < 0) return true;
  if (i == prefix.length - 1) return false; // no space after the stop: not a gap
  while (i >= 0 && '"”’\')]}*_'.contains(prefix[i])) {
    i--;
  }
  if (i < 0 || !'.!?'.contains(prefix[i])) return false;
  if (prefix[i] != '.') return true; // ! and ? always end a sentence
  // An ellipsis trails off; it does not end a sentence.
  if (i > 0 && prefix[i - 1] == '.') return false;
  var j = i - 1;
  while (j >= 0 && RegExp(r"[\p{L}\p{N}.]", unicode: true).hasMatch(prefix[j])) {
    j--;
  }
  final token = prefix.substring(j + 1, i).toLowerCase();
  if (token.isEmpty) return false; // "..." or a lone dot
  if (token.length == 1) return false; // an initial: "J. Smith"
  if (RegExp(r'^\d').hasMatch(token)) return false; // "3. " is a list or a number
  if (_abbreviations.contains(token)) return false;
  return true;
}

/// The formatter that applies [computeAutoFix] to what is typed.
class AutoWritingFormatter extends TextInputFormatter {
  AutoWritingFormatter({
    required this.enabled,
    required this.autoCorrect,
    required this.autoCapitalize,
    required this.correct,
    required this.keep,
    required this.onFix,
  });

  /// False whenever the person is not writing English: then this does nothing.
  final bool Function() enabled;
  final bool Function() autoCorrect;
  final bool Function() autoCapitalize;
  final String? Function(String word) correct;
  final Set<String> keep;
  final void Function(AutoFix fix) onFix;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (!enabled()) return newValue;
    final fix = computeAutoFix(
      old: oldValue,
      next: newValue,
      autoCorrect: autoCorrect(),
      autoCapitalize: autoCapitalize(),
      correct: correct,
      keep: keep,
    );
    if (fix == null) return newValue;
    onFix(fix);
    return fix.value;
  }
}
