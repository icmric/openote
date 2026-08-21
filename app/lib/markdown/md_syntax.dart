/// **The** inline Markdown grammar, and the only copy of it.
///
/// It used to exist twice — once in `md_render.inlineSpans` for reading and
/// once in `LiveMarkdownController._inline` for writing — as two hand-kept
/// alternations with hand-numbered capture groups. They disagreed in four
/// places, so text visibly changed shape every time the caret left a block:
/// `_italic_` was emphasis while typing and plain text when read, `####` was
/// a heading in one and hashes in the other. Worse, neither had a `***`
/// branch, so `***bold italic***` matched the `**` branch as `***bold
/// italic**` and rendered bold with a stray asterisk — exactly the imported
/// bold+italic bug, and reachable without importing anything by pressing
/// Ctrl+B then Ctrl+I.
///
/// Both renderers now scan with [mdInlineRe] and switch on [classifyInline],
/// so a branch added here reaches reading and writing in the same commit.
library;

/// What an inline match turned out to be.
enum MdInline {
  wikiLink,
  extLink,
  bareUrl,
  math,

  /// `$$inner$$` — BOTH dollar pairs are part of the match, so the live editor
  /// draws one atom where the read renderer draws its centred line. Before
  /// this the inline form took only the INNER pair and left a literal stray
  /// dollar on each side the moment the caret entered the block — measured:
  /// a 65px centred equation collapsing to dollar + 21px atom + dollar.
  mathDisplay,

  /// `$ x $` — one space of padding each side, accepted ONLY when the inner
  /// run carries a backslash command. Money never contains a backslash; the
  /// guard is the same narrowness rule MathClipboard.looksLikeMaths applies,
  /// for the same reason (v0.20 $.5).
  mathPadded,

  /// `$$` with nothing between: an equation the student has started
  /// but not yet written into. Drawn as the same empty box they already
  /// see inside a half-filled fraction.
  mathEmpty,
  colour,
  boldItalic,
  bold,
  italic,
  code,
  strike,
  highlight,
  underline,
  subscript,
  superscript,
}

/// One classified match: what it is, and where its markers are.
///
/// [openLen]/[closeLen] let the live editor emit `marker + inner + marker` as
/// three substrings of the source, which is how it hides markers without
/// changing the character count the caret walks.
class MdMatch {
  const MdMatch({
    required this.kind,
    required this.openLen,
    required this.closeLen,
    required this.inner,
    this.label,
    this.target,
  });

  final MdInline kind;
  final int openLen;
  final int closeLen;

  /// The styled text between the markers.
  final String inner;

  /// Wiki/external link label; null otherwise.
  final String? label;

  /// Link id/url, or the colour's hex digits.
  final String? target;
}

// Ordering is load-bearing. An alternation tries its branches left to right at
// each position, so `***` MUST precede `**`, which must precede `*` — that is
// the whole fix for bold+italic. The flanking guards are the other half: they
// stop `2 * 3 * 4` from italicising " 3 " (a marker may not sit against a
// space) and stop `snake_case_name` and `a_1` from losing their underscores
// (an underscore marker may not sit against a word character, which is
// CommonMark's own rule and why `**` is the safe emphasis marker mid-word).
const String _bi = r'(\*\*\*(?![\s*])(.+?)(?<![\s*])\*\*\*)';
const String _b = r'(\*\*(?![\s*])(.+?)(?<![\s*])\*\*)';
const String _i = r'(\*(?![\s*])(.+?)(?<![\s*])\*)';
const String _bU = r'((?<![\w\\])__(?![\s_])(.+?)(?<![\s_])__(?![\w]))';
const String _iU = r'((?<![\w\\])_(?![\s_])(.+?)(?<![\s_])_(?![\w]))';
const String _code = r'(`(.+?)`)';
const String _strike = r'(~~(.+?)~~)';
const String _high = r'(==(.+?)==)';
const String _under = r'(\+\+(.+?)\+\+)';
// Pandoc's subscript and superscript: `H~2~O`, `x^2^`.
//
// TWO rules, and both are load-bearing.
//
// 1. `~~` must stay strikethrough. A single tilde is a PREFIX of the double
//    one — the same shape as `*` inside `**`, which is the collision that
//    once rendered `***bold italic***` as bold plus a stray asterisk.
//    Answered twice over, because it is cheap:
//      * the inner class EXCLUDES `~`, so a subscript can neither begin on
//        the second tilde of a pair nor swallow one. This is what actually
//        does the work — a subscript branch simply cannot match anywhere
//        inside `~~struck~~`;
//      * and `_strike` sits BEFORE `_sub` in `_order`, so even if the inner
//        class were ever loosened, `~~…~~` still wins at the position it
//        starts on. `(?!~)` on both markers is the same belt on the outside.
//    Either one alone holds today; the test that proves the collision has to
//    break BOTH to make it fail, which is the honest thing to say about it.
//
// 2. The inner text may contain NO whitespace (`[^\s~]+`, `[^\s^]+`) — this
//    is Pandoc's own rule and it is what keeps ordinary prose literal. A
//    flanking guard alone is not enough: with a lazy `.+?` inner,
//    "3^2 = 9 and 4^2 = 16" matches `^2 = 9 and 4^` (the closing caret is
//    flanked by digits on both sides) and eats half the sentence. Forbidding
//    the space kills that, and with it "~5 to ~10", "a ~ b" and `~/Documents
//    ~/Downloads`. A lone `~` or `^` with no partner on its own side of a
//    space is simply a tilde or a caret, which is what students type.
const String _sub = r'(~(?!~)([^\s~]+)~(?!~))';
const String _sup = r'(\^([^\s^]+)\^)';
// Maths, with Pandoc's flanking rule — the opening `$` must be followed by a
// non-space, the closing one preceded by a non-space and NOT followed by a
// digit. Without those three guards the pattern eats money: measured against
// the old `(\$([^$\n]+?)\$)`, "coffee is $5 and lunch is $10 today" matched
// `$5 and lunch is $` and set a student's lunch order as an equation. Every
// guard earns its place — the trailing `(?!\d)` is the one that rejects the
// price pair specifically, since "5 and lunch is" ends in a non-space and
// would otherwise satisfy the rest.
const String _math = r'(\$([^\s$\n](?:[^$\n]*[^\s$\n])?)\$(?!\d))';

// An equation that is EMPTY — the two dollars Alt+= writes at the caret before
// the student has typed anything into it.
//
// It has to be part of the grammar, because the live editor draws whatever the
// grammar finds and shows anything it does not find as literal source: two
// dollar signs appearing mid-sentence, which is exactly the "random things
// popup" a student who has never heard of Markdown should never meet.
//
// The trailing guard keeps it off a display equation — in `$$x$$` the pair at
// index 0 is followed by `x`, so this declines and `_math` takes `$x$` as
// before. The empty capture group is what gives the classifier an inner of
// `''`, which is how every consumer recognises "nothing here yet".
const String _mathEmpty = r'((?<!\$)\$()\$(?![^\s]))';

// Both pairs consumed — see [MdInline.mathDisplay]. The inner guards are
// `_math`'s own (non-space at both ends, no trailing digit), so the money
// rule holds here too.
const String _mathDisplay =
    r'(\$\$([^\s\$\n](?:[^\$\n]*[^\s\$\n])?)\$\$(?!\d))';

// One space of padding, backslash-guarded — see [MdInline.mathPadded].
const String _mathPadded =
    r'(\$ ([^\$\n]*\\[a-zA-Z]+[^\$\n]*) \$)';
const String _colour =
    r'(\{\{#([0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?) (.+?)\}\})';
const String _wiki = r'(\[\[([^\]|]+)(?:\|([^\]]+))?\]\])';
const String _link = r'(\[([^\]\[]+)\]\((https?://[^)\s]+|mailto:[^)\s]+)\))';
// Last: an explicit `[label](url)` must win at the same position, and the
// lookbehind keeps a bare URL from firing mid-word or on the `(url)` half of
// a link the scanner has already stepped over.
const String _bare = r'((?:^|(?<=[\s(<]))(https?://[^\s)\]<]+))';

/// Group numbers, derived once from the order above rather than counted by
/// hand — miscounting them is what made the two old copies so fragile.
const _order = <MapEntry<MdInline, int>>[
  MapEntry(MdInline.wikiLink, 3), // outer, label, id
  MapEntry(MdInline.extLink, 3), // outer, label, url
  MapEntry(MdInline.colour, 3), // outer, hex, text
  MapEntry(MdInline.boldItalic, 2),
  MapEntry(MdInline.bold, 2),
  MapEntry(MdInline.italic, 2),
  MapEntry(MdInline.underline, 2), // ++u++ before __u__ can claim it
  MapEntry(MdInline.strike, 2),
  MapEntry(MdInline.highlight, 2),
  // AFTER strike: `~~` must beat `~`, exactly as `**` beats `*` above.
  MapEntry(MdInline.subscript, 2),
  MapEntry(MdInline.superscript, 2),
  MapEntry(MdInline.code, 2),
  // Display first: at the same offset `$$x$$` must be read whole, or the
  // single-dollar form takes the inner pair and strands a dollar each side.
  MapEntry(MdInline.mathDisplay, 2),
  MapEntry(MdInline.math, 2),
  MapEntry(MdInline.mathPadded, 2),
  // AFTER the filled form, so `$x$` always wins where it can.
  MapEntry(MdInline.mathEmpty, 2),
  MapEntry(MdInline.bareUrl, 2),
];

String _patternFor(MdInline k) => switch (k) {
      MdInline.wikiLink => _wiki,
      MdInline.extLink => _link,
      MdInline.colour => _colour,
      MdInline.boldItalic => _bi,
      MdInline.bold => '$_b|$_bU',
      MdInline.italic => '$_i|$_iU',
      MdInline.underline => _under,
      MdInline.strike => _strike,
      MdInline.highlight => _high,
      MdInline.subscript => _sub,
      MdInline.superscript => _sup,
      MdInline.code => _code,
      MdInline.math => _math,
      MdInline.mathDisplay => _mathDisplay,
      MdInline.mathPadded => _mathPadded,
      MdInline.mathEmpty => _mathEmpty,
      MdInline.bareUrl => _bare,
    };

/// Marker widths, by kind. `-1` means "work it out from the match".
int _openLen(MdInline k) => switch (k) {
      MdInline.boldItalic => 3,
      MdInline.bold || MdInline.strike || MdInline.highlight => 2,
      MdInline.underline => 2,
      MdInline.italic || MdInline.code || MdInline.math => 1,
      MdInline.mathEmpty => 1,
      // The opening '$$' / '$ ' and their mirrored closers.
      MdInline.mathDisplay || MdInline.mathPadded => 2,
      MdInline.subscript || MdInline.superscript => 1,
      _ => -1,
    };

/// The one scanner. Built by joining the ordered branch patterns, so the
/// group indices below are computed, never counted.
final RegExp mdInlineRe = RegExp([
  for (final e in _order)
    e.key == MdInline.bold || e.key == MdInline.italic
        ? _patternFor(e.key)
        : _patternFor(e.key)
].join('|'));

/// Where each kind's outer group starts, in the same computed order.
final Map<MdInline, int> _groupBase = () {
  final m = <MdInline, int>{};
  var g = 1;
  for (final e in _order) {
    m[e.key] = g;
    // `bold` and `italic` each carry TWO alternatives (asterisk and
    // underscore), so they occupy twice their group count.
    final mult =
        (e.key == MdInline.bold || e.key == MdInline.italic) ? 2 : 1;
    g += e.value * mult;
  }
  return m;
}();

/// Classify a match produced by [mdInlineRe].
///
/// Never returns null: every branch of the alternation is covered here, which
/// is what stops a renderer falling through to somebody else's `else` and
/// dereferencing a group that did not participate.
MdMatch classifyInline(RegExpMatch m) {
  for (final e in _order) {
    final g = _groupBase[e.key]!;
    final isPair = e.key == MdInline.bold || e.key == MdInline.italic;
    // Asterisk form first, then the underscore alternative.
    for (var alt = 0; alt < (isPair ? 2 : 1); alt++) {
      final base = g + alt * e.value;
      if (m.group(base) == null) continue;
      switch (e.key) {
        case MdInline.wikiLink:
          return MdMatch(
              kind: e.key,
              openLen: 2,
              closeLen: 2,
              inner: m.group(base + 1)!,
              label: m.group(base + 1),
              target: m.group(base + 2));
        case MdInline.extLink:
          return MdMatch(
              kind: e.key,
              openLen: 1,
              closeLen: 0,
              inner: m.group(base + 1)!,
              label: m.group(base + 1),
              target: m.group(base + 2));
        case MdInline.colour:
          final hex = m.group(base + 1)!;
          return MdMatch(
              kind: e.key,
              openLen: hex.length + 4, // '{{#' + hex + ' '
              closeLen: 2,
              inner: m.group(base + 2)!,
              target: hex);
        case MdInline.bareUrl:
          return MdMatch(
              kind: e.key,
              openLen: 0,
              closeLen: 0,
              inner: m.group(base + 1)!,
              target: m.group(base + 1));
        default:
          final len = _openLen(e.key);
          return MdMatch(
              kind: e.key,
              openLen: len,
              closeLen: len,
              inner: m.group(base + 1)!);
      }
    }
  }
  // Unreachable while every branch is listed in `_order`; a plain span is a
  // safer failure than an exception inside a paint.
  return MdMatch(
      kind: MdInline.bold, openLen: 0, closeLen: 0, inner: m.group(0)!);
}

// ── Line grammar ──────────────────────────────────────────────────────────
//
// The other half of the drift. `md_render` accepted only `-` as a bullet
// while the live editor accepted `-` and `*`, so `* item` greyed out like a
// real marker as you typed it and came back as literal text the moment you
// clicked away. See editor/list_editing.dart for the parser these feed.

/// Every bullet character Markdown allows, and that people actually type.
const String kBulletChars = r'-*+';

final RegExp mdHeadingRe = RegExp(r'^(#{1,3})( +)');
final RegExp mdCheckboxRe = RegExp(r'^([ \t]*)[-*+] \[( |x|X)\]\s?(.*)$');
final RegExp mdBulletRe = RegExp(r'^([ \t]*)[-*+][ \t]+(.*)$');
final RegExp mdNumberedRe = RegExp(r'^([ \t]*)(\d{1,9})[.)][ \t]+(.*)$');
final RegExp mdQuoteRe = RegExp(r'^>\s?(.*)$');
final RegExp mdDividerRe = RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$');

/// **Every equation in a piece of Markdown**, as (where it starts, where it
/// ends, and the LaTeX inside).
///
/// A standalone walk over [mdInlineRe], for the things that must read a
/// paragraph's maths without a live editor open on it — re-working answers
/// after the angle mode changes, for one. The live editor has its own copy of
/// this walk over the buffer it is editing; this is the same grammar for text
/// at rest.
Iterable<({int start, int end, String latex})> mathRunsIn(String text) sync* {
  for (final m in mdInlineRe.allMatches(text)) {
    final c = classifyInline(m);
    if (c.kind != MdInline.math &&
        c.kind != MdInline.mathDisplay &&
        c.kind != MdInline.mathPadded) {
      continue;
    }
    yield (start: m.start, end: m.end, latex: c.inner.trim());
  }
}

/// The same run with a new equation in it, dollars and all.
String replaceMathRun(String text, ({int start, int end, String latex}) run,
    String latex) {
  final full = text.substring(run.start, run.end);
  var d = 0;
  while (d < full.length && full.codeUnitAt(d) == 0x24) {
    d++;
  }
  final wrap = r'$' * (d == 0 ? 1 : d);
  return text.replaceRange(run.start, run.end, 'wrapLATEXwrap'
      .replaceFirst('wrap', wrap)
      .replaceFirst('LATEX', latex)
      .replaceFirst('wrap', wrap));
}

