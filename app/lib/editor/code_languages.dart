/// Every language a code cell can be — and, because it is the same question,
/// how typing behaves inside one.
///
/// One registry answers all of it: what the picker lists and in what order,
/// which alias a pasted fence (```c++, ```node, ```py) resolves to, how wide
/// one indent is, which quotes auto-pair, and whether the Run button appears.
/// Before this file the list lived inline in the picker as sixteen bare ids
/// (`cpp`, `js`, `sql`) in no particular order, and nothing on screen said
/// which of them would actually run.
///
/// The keystroke handlers live here rather than in the view because every
/// decision they make is a language fact: an indent is two spaces in Dart and
/// four in Python, `'` pairs in C (a char literal) and must not in Rust (a
/// lifetime). They are pure — `(text, selection) → (text, selection)` — so
/// the behaviour every IDE has muscle memory for is testable without a
/// widget, exactly as `list_editing.dart` does for prose.
library;

import 'package:flutter/services.dart';

import '../code/code_runner.dart';
import 'wrap_selection.dart';

/// The language a new — or unrecognised — code cell carries.
const String kDefaultLanguageId = 'text';

/// Group titles, in the order the picker shows them. Runnable first, because
/// "will this actually run?" is the one question the menu can answer that a
/// student cannot; then families, so C, C++ and C# sit together instead of
/// being scattered by spelling ("More logical ordering … c -> c++, c#").
const String kRunsHereGroup = 'Runs on this device';
const String _cFamily = 'C family';
const String _common = 'Common languages';
const String _web = 'Web pages';
const String _data = 'Data files';
const String _terminal = 'Terminal';
const String _plain = 'Plain';

/// Brackets pair in every language; quotes do not, so they are per-language.
const Map<String, String> _brackets = {'(': ')', '[': ']', '{': '}'};

class CodeLanguage {
  const CodeLanguage({
    required this.id,
    required this.name,
    required this.group,
    this.aliases = const <String>[],
    this.indent = 2,
    this.lineComment = '',
    this.quotes = const {'"', "'", '`'},
    this.indentAfterColon = false,
  });

  /// What is stored in the block and handed to the runner and the exporter.
  final String id;

  /// What a person reads: `C++`, not `cpp`.
  final String name;

  /// Menu group, one of the constants above.
  final String group;

  /// Other spellings that mean this language — what a pasted Markdown fence
  /// or an imported file is likely to say.
  final List<String> aliases;

  /// Spaces per indent level. Two unless the language's own convention is
  /// load-bearing enough that a student would be corrected for it.
  final int indent;

  /// The line-comment marker, or '' where there isn't one. Used for the
  /// empty cell's hint, so a Python cell doesn't suggest `//`.
  final String lineComment;

  /// Which quote characters auto-close. Rust omits `'` because a lifetime
  /// (`&'a str`) is not an unterminated string.
  final Set<String> quotes;

  /// Python: a line ending in `:` opens a block, the way `{` does elsewhere.
  final bool indentAfterColon;

  /// Whether a Run button appears. Asked of the runner rather than restated,
  /// so the menu can never promise a run the runner would refuse.
  bool get runnable => isRunnableLanguage(id);

  /// The auto-closing pairs, brackets plus this language's quotes — the same
  /// set [WrapSelectionFormatter.bracketPairs] wraps a selection with, since
  /// pairing and wrapping are two halves of one behaviour.
  Map<String, String> get pairs => {
        ..._brackets,
        for (final q in quotes) q: q,
      };
}

/// Every language, in menu order.
const List<CodeLanguage> codeLanguages = [
  CodeLanguage(
      id: 'sql',
      name: 'SQL',
      group: kRunsHereGroup,
      aliases: ['sqlite', 'postgres', 'mysql'],
      lineComment: '--',
      quotes: {'"', "'"}),
  CodeLanguage(
      id: 'js',
      name: 'JavaScript',
      group: kRunsHereGroup,
      aliases: ['javascript', 'node', 'mjs', 'jsx'],
      lineComment: '//'),

  CodeLanguage(
      id: 'c',
      name: 'C',
      group: _cFamily,
      aliases: ['h'],
      indent: 4,
      lineComment: '//',
      quotes: {'"', "'"}),
  CodeLanguage(
      id: 'cpp',
      name: 'C++',
      group: _cFamily,
      aliases: ['c++', 'cxx', 'cc', 'hpp'],
      indent: 4,
      lineComment: '//',
      quotes: {'"', "'"}),
  CodeLanguage(
      id: 'csharp',
      name: 'C#',
      group: _cFamily,
      aliases: ['cs', 'c#', 'dotnet'],
      indent: 4,
      lineComment: '//',
      quotes: {'"', "'"}),

  CodeLanguage(
      id: 'python',
      name: 'Python',
      group: _common,
      aliases: ['py', 'python3'],
      indent: 4,
      lineComment: '#',
      quotes: {'"', "'"},
      indentAfterColon: true),
  CodeLanguage(
      id: 'java',
      name: 'Java',
      group: _common,
      indent: 4,
      lineComment: '//',
      quotes: {'"', "'"}),
  CodeLanguage(
      id: 'kotlin',
      name: 'Kotlin',
      group: _common,
      aliases: ['kt'],
      indent: 4,
      lineComment: '//',
      quotes: {'"', "'"}),
  CodeLanguage(id: 'dart', name: 'Dart', group: _common, lineComment: '//'),
  CodeLanguage(
      id: 'go',
      name: 'Go',
      group: _common,
      aliases: ['golang'],
      indent: 4,
      lineComment: '//'),
  CodeLanguage(
      id: 'rust',
      name: 'Rust',
      group: _common,
      aliases: ['rs'],
      indent: 4,
      lineComment: '//',
      quotes: {'"'}),
  CodeLanguage(
      id: 'ts',
      name: 'TypeScript',
      group: _common,
      aliases: ['typescript', 'tsx'],
      lineComment: '//'),

  CodeLanguage(id: 'html', name: 'HTML', group: _web, aliases: ['htm']),
  CodeLanguage(id: 'css', name: 'CSS', group: _web, aliases: ['scss', 'less']),
  CodeLanguage(
      id: 'php',
      name: 'PHP',
      group: _web,
      indent: 4,
      lineComment: '//',
      quotes: {'"', "'"}),

  CodeLanguage(id: 'json', name: 'JSON', group: _data, quotes: {'"'}),
  CodeLanguage(
      id: 'yaml',
      name: 'YAML',
      group: _data,
      aliases: ['yml'],
      lineComment: '#',
      quotes: {'"', "'"}),

  CodeLanguage(
      id: 'bash',
      name: 'Bash',
      group: _terminal,
      aliases: ['sh', 'shell', 'zsh', 'console'],
      lineComment: '#',
      quotes: {'"', "'"}),

  CodeLanguage(
      id: kDefaultLanguageId,
      name: 'Plain text',
      group: _plain,
      aliases: ['plain', 'plaintext', 'txt'],
      quotes: {'"'}),
];

final Map<String, CodeLanguage> _byId = {
  for (final l in codeLanguages) ...{
    l.id: l,
    for (final a in l.aliases) a: l,
  }
};

/// The language [id] names, by id or alias, falling back to plain text — so
/// an imported ```c++ fence highlights and runs as the same language a pick
/// from the menu would.
CodeLanguage languageFor(String? id) =>
    _byId[(id ?? '').trim().toLowerCase()] ?? _byId[kDefaultLanguageId]!;

/// The picker's contents: groups in order, each with its languages in order.
final List<({String title, List<CodeLanguage> languages})> codeLanguageMenu =
    () {
  final out = <({String title, List<CodeLanguage> languages})>[];
  for (final l in codeLanguages) {
    if (out.isEmpty || out.last.title != l.group) {
      out.add((title: l.group, languages: <CodeLanguage>[]));
    }
    out.last.languages.add(l);
  }
  return out;
}();

// ── Detection ─────────────────────────────────────────────────────────────

RegExp _m(String pattern, {bool ignoreCase = false}) =>
    RegExp(pattern, multiLine: true, caseSensitive: !ignoreCase);

/// Markers, weighted by how much they narrow things down. A shebang or
/// `<?php` is proof; `=>` is a hint. Negative weights are the ones that
/// matter most in practice: they are how C stops claiming C++ code and how
/// JSON stops claiming a JavaScript object literal.
final Map<String, List<(RegExp, int)>> _markers = {
  'python': [
    (_m(r'^#!.*\bpython'), 8),
    (_m(r'^\s*def \w+\s*\(.*\)\s*:'), 5),
    (_m(r'^\s*class \w+(\(\w*\))?\s*:'), 4),
    (_m(r'^\s*(from [\w.]+ )?import [\w.]+\s*$'), 4),
    (_m(r'\bself\.'), 3),
    (_m(r'^\s*elif\b'), 3),
    (_m(r'__name__'), 3),
    (_m(r'^\s*print\('), 2),
    (_m(r'\bTrue\b|\bFalse\b|\bNone\b'), 2),
    (_m(r'\bfor \w+ in '), 2),
    (_m(r'[;{]\s*$'), -3),
  ],
  'js': [
    (_m(r'\bconsole\.log\s*\('), 5),
    (_m(r'\bfunction\s+\w*\s*\('), 3),
    (_m(r'^\s*(const|let)\s+\w+\s*='), 3),
    (_m(r'\brequire\s*\('), 3),
    (_m(r'\b(document|window)\.'), 3),
    (_m(r'\bexport default\b'), 3),
    (_m(r'==='), 2),
    (_m(r'=>'), 2),
    (_m(r':\s*(string|number|boolean)\b'), -4),
    (_m(r'^\s*(interface|type) \w+'), -4),
  ],
  'ts': [
    (_m(r'^\s*interface \w+\s*\{'), 5),
    (_m(r':\s*(string|number|boolean)\b'), 4),
    (_m(r'^\s*type \w+\s*='), 4),
    (_m(r'\b(public|private|protected|readonly) \w+\s*:'), 4),
    (_m(r'\bimplements\b'), 3),
    (_m(r'^\s*enum \w+'), 3),
    (_m(r'\bconsole\.log\s*\('), 2),
  ],
  'dart': [
    (_m("import 'package:"), 6),
    (_m(r'\bWidget build\s*\(BuildContext'), 6),
    (_m(r'@override\b'), 4),
    (_m(r'^\s*void main\(\)'), 4),
    (_m(r'\b(List|Map|Future|Stream)<'), 2),
    (_m(r'\bfinal \w+\s*='), 2),
  ],
  'rust': [
    (_m(r'\bfn \w+\s*\('), 5),
    (_m(r'\blet mut\b'), 5),
    (_m(r'\bprintln!'), 5),
    (_m(r'\buse std::'), 4),
    (_m(r'^\s*impl\b'), 4),
    (_m(r'#\[derive'), 4),
    (_m(r'&str\b|\bString::'), 3),
    (_m(r'\bpub fn\b'), 3),
  ],
  'c': [
    (_m(r'#include\s*<\w+\.h>'), 5),
    (_m(r'\bprintf\s*\('), 4),
    (_m(r'\b(malloc|free|sizeof)\s*\('), 3),
    (_m(r'\b(scanf|fgets|strcpy)\s*\('), 3),
    (_m(r'\bint main\s*\('), 3),
    (_m(r'\bstruct \w+\s*\{'), 2),
    (_m(r'\bNULL\b'), 2),
    (_m(r'std::|\bcout\b|\bnullptr\b|\bnamespace\b|\btemplate\s*<'), -6),
    (_m(r'\bclass \w+'), -4),
  ],
  'cpp': [
    (_m(r'#include\s*<(iostream|vector|string|map|set|algorithm|memory|sstream)>'),
        6),
    (_m(r'std::'), 5),
    (_m(r'\bcout\s*<<|\bcin\s*>>'), 5),
    (_m(r'\busing namespace\b'), 5),
    (_m(r'\bnullptr\b'), 4),
    (_m(r'^\s*template\s*<'), 4),
    (_m(r'^\s*(public|private|protected)\s*:'), 3),
    (_m(r'#include\s*<\w+>'), 2),
    (_m(r'\bint main\s*\('), 2),
    (_m(r'\bclass \w+'), 2),
    (_m(r'^\s*using System'), -6),
  ],
  'csharp': [
    (_m(r'^\s*using System'), 6),
    (_m(r'\bConsole\.(Write|Read)'), 6),
    (_m(r'\bstatic void Main\s*\('), 5),
    (_m(r'^\s*namespace \w'), 4),
    (_m(r'\bstring\[\]\s*args'), 4),
    (_m(r'\bget;\s*set;'), 4),
    (_m(r'\basync Task\b'), 4),
    (_m(r'^\s*\[\w+(\(.*\))?\]\s*$'), 3),
    (_m(r'\bpublic\s+(class|static|void|int|string|async|override)\b'), 3),
    (_m(r'\bvar \w+\s*='), 1),
    (_m(r'#include\b|\bstd::'), -6),
  ],
  'java': [
    (_m(r'\bSystem\.out\.print'), 6),
    (_m(r'^\s*import java'), 6),
    (_m(r'\bpublic static void main\s*\(\s*String'), 6),
    (_m(r'^\s*package [\w.]+;'), 3),
    (_m(r'@Override\b'), 3),
    (_m(r'^\s*(public|private)\s+class \w+'), 3),
    (_m(r'\bString\[\]'), 3),
    (_m(r'\bConsole\.|^\s*using System'), -6),
  ],
  'kotlin': [
    (_m(r'\bfun \w+\s*\('), 5),
    (_m(r'\bdata class\b'), 5),
    (_m(r'\bcompanion object\b'), 4),
    (_m(r'^\s*val \w+'), 4),
    (_m(r'\bprintln\s*\('), 3),
    (_m(r'^\s*var \w+\s*:'), 3),
    (_m(r'\?:|\?\.'), 2),
  ],
  'go': [
    (_m(r'^package \w+\s*$'), 6),
    (_m(r'\bfmt\.(Print|Sprint)'), 6),
    (_m(r'\bfunc \w*\s*\('), 5),
    (_m(r'\berr != nil\b'), 4),
    (_m(r':='), 4),
    (_m(r'^import \('), 4),
  ],
  'sql': [
    (_m(r'\bselect\b[\s\S]*\bfrom\b', ignoreCase: true), 5),
    (_m(r'\binsert\s+into\b', ignoreCase: true), 5),
    (_m(r'\bcreate\s+table\b', ignoreCase: true), 5),
    (_m(r'\b(group|order)\s+by\b', ignoreCase: true), 3),
    (_m(r'\b(inner|left|right)\s+join\b', ignoreCase: true), 3),
    (_m(r'\bupdate\b[\s\S]*\bset\b', ignoreCase: true), 3),
    (_m(r'\bwhere\b', ignoreCase: true), 1),
    (_m(r'\bfunction\b|=>|\bconsole\.'), -5),
  ],
  'bash': [
    (_m(r'^#!.*\b(ba|z)?sh\b'), 8),
    (_m(r'^\s*(fi|done|esac)\s*$'), 4),
    (_m(r'^\s*echo\s'), 3),
    (_m(r'\bif \[|\[\['), 3),
    (_m(r'^\s*(sudo|apt|git|cd|ls|mkdir|rm|cp|mv|chmod|curl|npm|flutter)\s'), 3),
    (_m(r'\$\{?\w+\}?'), 2),
    (_m(r'<\?php'), -8),
  ],
  'php': [
    (_m(r'<\?php'), 10),
    (_m(r'\becho\s'), 3),
    (_m(r'\$\w+\s*='), 3),
    (_m(r'->\w+\('), 2),
  ],
  'json': [
    (_m(r'"[\w-]+"\s*:'), 4),
    (_m(r'^\s*[\{\[]'), 2),
    (_m(r'[\}\]]\s*$'), 2),
    (_m(r';\s*$'), -6),
    (_m(r'//|/\*|\bfunction\b|=>|\b(const|let|var)\b'), -6),
    (_m(r"'"), -2),
  ],
  'yaml': [
    (_m(r'^[\w.-]+:\s*$'), 4),
    (_m(r'^---\s*$'), 4),
    (_m(r'^[\w.-]+:\s+\S'), 3),
    (_m(r'^\s*- \w'), 3),
    (_m(r'[{};]'), -3),
  ],
  'html': [
    (_m(r'<!DOCTYPE html', ignoreCase: true), 8),
    (_m(r'<html\b', ignoreCase: true), 6),
    (_m(r'</(div|p|span|body|head|ul|li|a|h[1-6])>', ignoreCase: true), 5),
    (_m(r'<(div|p|span|body|head|ul|li|table|img|br)\b', ignoreCase: true), 4),
    (_m(r'<\w+[^>]*>'), 2),
  ],
  'css': [
    (_m(r'^[.#]?[\w-][^\n{]*\{[^}]*:[^}]*;'), 5),
    (_m(r'@media\b|@import\b'), 5),
    (_m(
        r'\b(color|background|margin|padding|font-size|display|width|height|border)\s*:'),
        4),
    (_m(r'\d+(px|rem|em)\b'), 3),
    (_m(r'\bfunction\b|=>|\bclass \w'), -4),
  ],
};

/// Below this the guess is not worth making, and silence is the right
/// answer: a two-line snippet that could be four languages stays plain text.
const int _kMinScore = 5;

/// The language [source] looks like, or null when nothing is clearly ahead.
///
/// Pure and side-effect free: the caller decides whether acting on the answer
/// is allowed (see [autoLanguageFor]).
String? detectLanguage(String source) {
  if (source.trim().length < 4) return null;
  var bestId = '';
  var best = 0, runnerUp = 0;
  for (final entry in _markers.entries) {
    var score = 0;
    for (final (re, weight) in entry.value) {
      if (re.hasMatch(source)) score += weight;
    }
    if (score > best) {
      runnerUp = best;
      best = score;
      bestId = entry.key;
    } else if (score > runnerUp) {
      runnerUp = score;
    }
  }
  // A near-tie is not a detection either: two languages fitting almost as
  // well as each other is exactly where guessing is worse than leaving it.
  if (best < _kMinScore || best - runnerUp < 2) return null;
  return bestId;
}

/// Did the source change by enough to be worth re-reading? A paste, a chunk
/// deleted, or a finished line — never mid-word, so the label cannot flicker
/// through three languages while a `for` loop is typed.
bool _changedSubstantially(String before, String after) {
  if (after.trim().length < 12) return false;
  if ((after.length - before.length).abs() >= 2) return true;
  return '\n'.allMatches(after).length > '\n'.allMatches(before).length;
}

/// The language a block should switch to after an edit, or null to leave it.
///
/// The rules, in the order they override each other:
///  1. A language the user PICKED is never second-guessed. That is what makes
///     auto-detection safe: it is always one menu choice away from off.
///  2. A language that arrived with the content — an imported ```rust fence —
///     is a statement by whoever wrote it, so only the default is re-read.
///  3. A previous auto-detection may be revised ([autoSet]), because the
///     first two lines of a paste are often not the telling ones.
String? autoLanguageFor({
  required String? current,
  required bool userPicked,
  required bool autoSet,
  required String previousSource,
  required String source,
}) {
  if (userPicked) return null;
  final now = languageFor(current).id;
  if (now != kDefaultLanguageId && !autoSet) return null;
  if (!_changedSubstantially(previousSource, source)) return null;
  final found = detectLanguage(source);
  if (found == null || found == now) return null;
  return found;
}

// ── Typing ────────────────────────────────────────────────────────────────

int _lineStart(String text, int at) =>
    at <= 0 ? 0 : text.lastIndexOf('\n', at - 1) + 1;

int _lineEnd(String text, int at) {
  final i = text.indexOf('\n', at < 0 ? 0 : at);
  return i < 0 ? text.length : i;
}

final _leading = RegExp(r'^[ \t]*');

String _indentOf(String line) => _leading.firstMatch(line)!.group(0)!;

TextEditingValue _value(String text, int caret) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
      composing: TextRange.empty,
    );

/// The IDE half of typing: auto-pairs, stepping over a closer, deleting an
/// empty pair, and what Enter does about indentation.
///
/// Given the value BEFORE the keystroke and the value the field produced,
/// returns the value that should stand instead — or null when the field's own
/// result is already right, which is the overwhelming majority of keystrokes.
///
/// It runs as an input formatter rather than off key events because that is
/// the only path every platform shares: a newline arrives from the text input
/// service, not from a raw key, so handling Enter as a key would work on the
/// desktop and quietly do nothing on a tablet.
TextEditingValue? applyCodeTyping(
    TextEditingValue before, TextEditingValue after, CodeLanguage lang) {
  final sel = before.selection;
  // A selection being typed over is the wrap formatter's business (it wraps
  // rather than replaces); pairing must not also fire and double the text.
  if (!sel.isValid || !sel.isCollapsed) return null;
  // Mid-composition (an IME, a phone's autocorrect) the "one character" test
  // below means nothing — leave the field alone until it commits.
  if (after.composing.isValid && !after.composing.isCollapsed) return null;

  final at = sel.baseOffset;
  final text = before.text;
  if (at < 0 || at > text.length) return null;
  final grew = after.text.length - text.length;

  if (grew == 1) {
    // Exactly one character, inserted exactly at the caret.
    if (after.text.substring(0, at) != text.substring(0, at)) return null;
    if (after.text.substring(at + 1) != text.substring(at)) return null;
    final ch = after.text[at];
    return ch == '\n' ? _enter(text, at, lang) : _pair(text, at, ch, lang);
  }
  if (grew == -1 && at > 0) {
    if (after.text != text.replaceRange(at - 1, at, '')) return null;
    return _backspace(text, at, lang);
  }
  return null;
}

/// Where a pair may close: at the end of the line, or before whitespace or
/// something that already ends an expression. Not before a word — closing
/// `(` in front of `foo` would trap the word inside brackets nobody asked
/// for, which is the auto-pairing everybody turns off.
bool _closableBefore(String next) =>
    next.isEmpty || ' \t\n)]}>,;:.'.contains(next);

final _wordChar = RegExp(r'[A-Za-z0-9_$]');

bool _isWordChar(String c) => c.isNotEmpty && _wordChar.hasMatch(c);

TextEditingValue? _pair(String text, int at, String ch, CodeLanguage lang) {
  final pairs = lang.pairs;
  final next = at < text.length ? text[at] : '';
  final prev = at > 0 ? text[at - 1] : '';
  final closer = pairs[ch];
  final closes = pairs.containsValue(ch);

  // Typing the closer that is already sitting there walks past it instead of
  // leaving `())` behind — the other half of auto-pairing, and the reason
  // finishing a call by typing `)` feels normal.
  if (closes && next == ch) return _value(text, at + 1);

  if (closer == null) return null;
  if (!_closableBefore(next)) return null;
  // A quote after a word is an apostrophe (`don't`, `it's`) or a suffix, and
  // after a backslash it is escaped — neither opens a string.
  if (closer == ch && (_isWordChar(prev) || prev == r'\' || prev == ch)) {
    return null;
  }
  return _value(text.replaceRange(at, at, '$ch$closer'), at + 1);
}

TextEditingValue? _backspace(String text, int at, CodeLanguage lang) {
  final deleted = text[at - 1];
  final closer = lang.pairs[deleted];
  // Backspace between the halves of an empty pair takes both: the closer was
  // never typed, so having to delete it is a chore the editor invented.
  if (closer != null && at < text.length && text[at] == closer) {
    return _value(text.replaceRange(at - 1, at + 1, ''), at - 1);
  }
  // Inside a line's indentation, backspace goes back one LEVEL rather than
  // one space, so it undoes Tab instead of unpicking it.
  if (deleted == ' ') {
    final ls = _lineStart(text, at);
    final head = text.substring(ls, at);
    if (head.isNotEmpty && head.trim().isEmpty && !head.contains('\t')) {
      final col = at - ls;
      final back = col % lang.indent == 0 ? lang.indent : col % lang.indent;
      if (back > 1) {
        return _value(text.replaceRange(at - back, at, ''), at - back);
      }
    }
  }
  return null;
}

TextEditingValue? _enter(String text, int at, CodeLanguage lang) {
  final ls = _lineStart(text, at);
  final head = text.substring(ls, at);
  final indent = _indentOf(head);
  final unit = ' ' * lang.indent;
  final left = head.trimRight();
  final lastCh = left.isEmpty ? '' : left[left.length - 1];

  final tail = text.substring(at, _lineEnd(text, at));
  final trimmedTail = tail.trimLeft();
  final firstCh = trimmedTail.isEmpty ? '' : trimmedTail[0];

  // Enter between the two halves of a pair: a blank line at one more level to
  // type on, and the closer pushed down to the OPENING line's indent — "then
  // pressing enter while inside creates a new line but adds the tab
  // indentation and moves } to a new line below the cursor".
  if (_brackets.containsKey(lastCh) && _brackets[lastCh] == firstCh) {
    final skip = tail.length - trimmedTail.length;
    return _value(
      text.replaceRange(at, at + skip, '\n$indent$unit\n$indent'),
      at + 1 + indent.length + unit.length,
    );
  }

  final opens = _brackets.containsKey(lastCh) ||
      (lang.indentAfterColon && lastCh == ':');
  final next = indent + (opens ? unit : '');
  // Nothing to add: the field's own newline already does exactly this.
  if (next.isEmpty) return null;
  return _value(text.replaceRange(at, at, '\n$next'), at + 1 + next.length);
}

/// Tab and Shift+Tab.
///
/// A caret indents to the next stop, so Tab in a half-indented line lands on
/// the grid rather than two spaces past it. A selection that spans lines
/// indents or outdents EVERY line it touches and stays selected, which is the
/// only way to move a block of code without retyping it. Returns null when
/// there is nothing to do (Shift+Tab at column 0) — the caller still swallows
/// the key, because Tab moving focus out of a code cell is the bug this
/// replaced.
TextEditingValue? handleCodeTab(TextEditingValue v, CodeLanguage lang,
    {bool outdent = false}) {
  final sel = v.selection;
  if (!sel.isValid) return null;
  final text = v.text;
  final width = lang.indent;
  final spansLines = text.substring(sel.start, sel.end).contains('\n');

  if (!spansLines && !outdent) {
    final col = sel.start - _lineStart(text, sel.start);
    final n = width - (col % width);
    return _value(
        text.replaceRange(sel.start, sel.end, ' ' * n), sel.start + n);
  }

  final firstLs = _lineStart(text, sel.start);
  // A selection that ends at the very start of a line (dragging down past the
  // last line's newline) has not touched that line, so it must not move.
  final lastLe = !sel.isCollapsed && _lineStart(text, sel.end) == sel.end
      ? sel.end - 1
      : _lineEnd(text, sel.end);
  final region = text.substring(firstLs, lastLe);
  final lines = region.split('\n');
  final out = <String>[];
  var firstDelta = 0, total = 0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final String next;
    if (outdent) {
      next = _outdent(line, width);
    } else {
      // A blank line inside a selected block gains nothing but trailing
      // whitespace.
      next = line.trim().isEmpty && lines.length > 1
          ? line
          : '${' ' * width}$line';
    }
    if (i == 0) firstDelta = next.length - line.length;
    total += next.length - line.length;
    out.add(next);
  }
  final replaced = out.join('\n');
  if (replaced == region) return null;

  final text2 = text.replaceRange(firstLs, lastLe, replaced);
  // A selection that began at the margin keeps it, so a block of code stays
  // wholly selected and Tab can be pressed twice.
  final start = (sel.start == firstLs ? firstLs : sel.start + firstDelta)
      .clamp(firstLs, text2.length);
  final end = (sel.end + total).clamp(firstLs, text2.length);
  return TextEditingValue(
    text: text2,
    selection: sel.isCollapsed
        ? TextSelection.collapsed(offset: start)
        : TextSelection(
            baseOffset: sel.baseOffset <= sel.extentOffset ? start : end,
            extentOffset: sel.baseOffset <= sel.extentOffset ? end : start,
          ),
    composing: TextRange.empty,
  );
}

/// One level off the front of a line: a tab, or up to [width] spaces.
String _outdent(String line, int width) {
  if (line.startsWith('\t')) return line.substring(1);
  var drop = 0;
  while (drop < width && drop < line.length && line[drop] == ' ') {
    drop++;
  }
  return line.substring(drop);
}

/// The pairing/indent rules as an input formatter, installed after
/// [WrapSelectionFormatter] (which handles the selection case) on the code
/// cell's field.
class CodeTypingFormatter extends TextInputFormatter {
  const CodeTypingFormatter(this.language);
  final CodeLanguage language;

  @override
  TextEditingValue formatEditUpdate(
          TextEditingValue oldValue, TextEditingValue newValue) =>
      applyCodeTyping(oldValue, newValue, language) ?? newValue;
}
