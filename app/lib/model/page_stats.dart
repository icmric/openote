/// **How much have I written?** — words, characters and reading time for a
/// page (PLANNING: *"Word counter, char count, estimated reading time."*).
///
/// Every essay a student hands in has a word limit on it, and the number they
/// are counting is the number a marker will count: the words they WROTE, not
/// the characters the file happens to hold. So this counts the text as it
/// READS, not as it is stored — `**bold**` is one word, a link is its label,
/// an equation is one word, and the `- ` in front of a bullet is not a word
/// at all.
///
/// **Shared classifier, not a second one.** The stripping goes through
/// [mdInlineRe] and [classifyInline], the same pair both renderers use, so a
/// syntax added to the app is counted correctly in the same commit rather
/// than whenever somebody remembers this file exists.
library;

import '../markdown/md_syntax.dart';
import 'models.dart';

/// What a page adds up to.
class PageStats {
  const PageStats({
    required this.words,
    required this.characters,
    required this.charactersNoSpaces,
    required this.blocks,
  });

  static const PageStats empty = PageStats(
      words: 0, characters: 0, charactersNoSpaces: 0, blocks: 0);

  final int words;

  /// Characters as read, spaces included — the count a "2000 characters
  /// maximum" box on a form is applying.
  final int characters;
  final int charactersNoSpaces;

  /// How many blocks contributed anything, so the readout can say what it
  /// looked at rather than implying it read the whole page.
  final int blocks;

  /// **Minutes, at 200 words a minute.**
  ///
  /// The figure for silent reading of ordinary prose by an adult; school
  /// reading-age tables land between 150 and 250 and 200 is the middle of
  /// them. Never zero: "0 min" reads as an error, and anything you have
  /// written at all takes a moment to read.
  int get readingMinutes => words == 0 ? 0 : (words / 200).ceil();
}

/// Everything on the page that a person would call writing.
///
/// **What is counted, and what is not.** Text boxes and table cells count:
/// they are prose. Code does NOT — a code block is a listing, and nobody
/// counts it towards an essay — and neither do image or file names, page
/// links' targets, or the markup itself. A flashcard's question and answer
/// count, because a student writes them in words.
///
/// Deliberately a pure function over blocks, so it can be tested to the
/// character without a widget in sight. **On a long page it is not cheap** —
/// measured at 68 ms for 800 blocks, which is four dropped frames — so
/// anything counting on every rebuild wants [PageStatsCache] instead.
PageStats pageStats(Iterable<Block> blocks) {
  var words = 0;
  var chars = 0;
  var charsNoSpaces = 0;
  var counted = 0;
  for (final b in blocks) {
    final one = _statsOf(b);
    words += one.words;
    chars += one.characters;
    charsNoSpaces += one.charactersNoSpaces;
    counted += one.blocks;
  }
  return PageStats(
      words: words,
      characters: chars,
      charactersNoSpaces: charsNoSpaces,
      blocks: counted);
}

/// **The same count, done again only where the page changed.**
///
/// The readout sits on a row that rebuilds on every keystroke, and a keystroke
/// changes ONE block. Recounting all of them took 68 ms on a page of eight
/// hundred — four dropped frames per character typed, on the longest pages,
/// which are exactly the ones with a word limit worth watching.
///
/// Keyed on the text itself rather than on a timestamp: `updatedAt` is set by
/// whoever remembers to set it, and a count that is quietly wrong is worse
/// than one that is slow. Comparing the strings is a memcmp — measured in
/// microseconds against the regex pass's milliseconds — and usually not even
/// that, because an untouched block hands back the identical String object.
class PageStatsCache {
  Map<String, _Counted> _byBlock = {};

  PageStats of(Iterable<Block> blocks) {
    // Rebuilt rather than updated in place, so a block that has been deleted
    // leaves with it. A page open all afternoon must not accumulate the
    // wreckage of every block it ever held.
    final next = <String, _Counted>{};
    var words = 0;
    var chars = 0;
    var charsNoSpaces = 0;
    var counted = 0;
    for (final b in blocks) {
      final source = _sourceOf(b);
      final was = _byBlock[b.id];
      final one = was != null && was.matches(source)
          ? was
          : _Counted(source, _statsOf(b));
      next[b.id] = one;
      words += one.stats.words;
      chars += one.stats.characters;
      charsNoSpaces += one.stats.charactersNoSpaces;
      counted += one.stats.blocks;
    }
    _byBlock = next;
    return PageStats(
        words: words,
        characters: chars,
        charactersNoSpaces: charsNoSpaces,
        blocks: counted);
  }
}

/// One block's contribution, and the text it was counted from.
class _Counted {
  _Counted(this.source, this.stats);
  final List<String> source;
  final PageStats stats;

  bool matches(List<String> now) {
    if (now.length != source.length) return false;
    for (var i = 0; i < now.length; i++) {
      // `identical` first: an untouched block hands back the same String
      // object, so the common case never reads a character.
      final a = source[i], b = now[i];
      if (!identical(a, b) && a != b) return false;
    }
    return true;
  }
}

/// Everything about a block that its count depends on. Nothing else — a block
/// that only MOVED has not changed a word.
List<String> _sourceOf(Block b) {
  switch (b.type) {
    case BlockType.text:
      return [b.content['text'] as String? ?? ''];
    case BlockType.table:
      final cells = b.content['cells'];
      if (cells is! List) return const [];
      return [
        for (final row in cells)
          if (row is List)
            for (final cell in row)
              if (cell is String) cell
      ];
    case BlockType.math:
      return [b.content['latex'] as String? ?? ''];
    case BlockType.flashcard:
      return [
        b.content['front'] as String? ?? '',
        b.content['back'] as String? ?? '',
      ];
    // Not writing, and each for its own reason: a listing, a picture, a
    // file's name, a drawing, cards you drag about, a window onto another
    // page, a curve, and a type this build does not know.
    case BlockType.code:
    case BlockType.image:
    case BlockType.file:
    case BlockType.ink:
    case BlockType.frame:
    case BlockType.embed:
    case BlockType.board:
    case BlockType.graph:
    case BlockType.unknown:
      return const [];
  }
}

PageStats _statsOf(Block b) {
  var words = 0;
  var chars = 0;
  var charsNoSpaces = 0;
  var counted = 0;

  void take(String raw) {
    if (raw.isEmpty) return;
    final plain = plainTextOf(raw);
    if (plain.trim().isEmpty) return;
    counted++;
    words += _wordsIn(plain);
    chars += plain.length;
    charsNoSpaces += plain.replaceAll(_space, '').length;
  }

  final source = _sourceOf(b);
  switch (b.type) {
    case BlockType.math:
      // An equation is one word wherever it sits — the same rule an inline
      // one gets inside a sentence, so moving an equation out of a paragraph
      // and into a box of its own does not change the count.
      if (source.isNotEmpty && source.first.trim().isNotEmpty) {
        counted = 1;
        words = 1;
      }
    case BlockType.table:
      // One block, however many cells: a table is one thing you wrote.
      take(source.join('\n'));
    default:
      for (final part in source) {
        take(part);
      }
  }
  return PageStats(
      words: words,
      characters: chars,
      charactersNoSpaces: charsNoSpaces,
      blocks: counted);
}

final RegExp _space = RegExp(r'\s');

/// Markdown as it READS: markers gone, links as their label, equations as a
/// single placeholder word, and list bullets and heading hashes dropped.
///
/// The placeholder matters. An equation deleted outright would join the words
/// either side of it into one (`the answer is $x$ exactly` counting as four
/// rather than five), and left as its LaTeX it would count `\frac{1}{2}` as
/// two or three depending on the spacing. One token, always.
String plainTextOf(String markdown) {
  final out = StringBuffer();
  for (final line in markdown.split('\n')) {
    out.writeln(_inlineText(_stripLineMarkers(line)));
  }
  return out.toString();
}

/// Bullets, numbers, checkboxes, quote marks and heading hashes: punctuation
/// of the layout, not of the sentence.
String _stripLineMarkers(String line) {
  var t = line.replaceFirst(_leadingSpace, '');
  t = t.replaceFirst(_heading, '');
  t = t.replaceFirst(_quote, '');
  t = t.replaceFirst(_bullet, '');
  t = t.replaceFirst(_checkbox, '');
  // A horizontal rule is a line, not a word.
  if (_rule.hasMatch(t)) return '';
  return t;
}

// Built once. A `RegExp(...)` inside a loop compiles a fresh pattern on every
// call, and this file walks every line of every block: measured at 150 ms for
// a page of two thousand, of which the per-word pattern below was most.
final RegExp _leadingSpace = RegExp(r'^\s+');
final RegExp _heading = RegExp(r'^#{1,6}\s+');
final RegExp _quote = RegExp(r'^>\s?');
final RegExp _bullet = RegExp(r'^([-*+]|\d+[.)])\s+');
final RegExp _checkbox = RegExp(r'^\[[ xX]\]\s+');
final RegExp _rule = RegExp(r'^([-*_]\s*){3,}$');
final RegExp _wordish = RegExp(r'[\p{L}\p{N}\u2022]', unicode: true);

String _inlineText(String line) {
  // **Most lines are plain prose**, and the shared classifier is one very
  // large alternation — measured as most of the cost of counting a page.
  // Every construct it can match needs one of these characters somewhere in
  // the line (a bare URL needs the colon of `http://`), so a line without any
  // of them cannot contain one and does not need looking at.
  if (!_couldBeInline.hasMatch(line)) return line;
  final out = StringBuffer();
  var last = 0;
  for (final m in mdInlineRe.allMatches(line)) {
    if (m.start > last) out.write(line.substring(last, m.start));
    final c = classifyInline(m);
    switch (c.kind) {
      case MdInline.math:
      case MdInline.mathDisplay:
      case MdInline.mathPadded:
        out.write(' • ');
      case MdInline.mathEmpty:
        break; // started and never written in
      case MdInline.wikiLink:
      case MdInline.extLink:
        // The words on the page are the label; nobody reads a URL aloud.
        out.write(c.label ?? '');
      case MdInline.bareUrl:
        // A pasted address IS one thing on the page, and a marker counting an
        // essay would count it once.
        out.write(' • ');
      case MdInline.colour:
      case MdInline.boldItalic:
      case MdInline.bold:
      case MdInline.italic:
      case MdInline.code:
      case MdInline.strike:
      case MdInline.highlight:
      case MdInline.underline:
      case MdInline.subscript:
      case MdInline.superscript:
        // Styling. The words inside it are still words — and they may hold
        // more markup, so they go back through.
        out.write(_inlineText(c.inner));
    }
    last = m.end;
  }
  if (last < line.length) out.write(line.substring(last));
  return out.toString();
}

/// **A word is a run with a letter or a digit in it.**
///
/// Splitting on whitespace alone counts a lone em-dash between two clauses as
/// a word, and an image's leftover `!` as another. Requiring a letter or a
/// digit is the rule every word counter converges on, and it makes
/// `don't`, `year-10` and `3.14` one word each, which is what they are.
int _wordsIn(String plain) {
  var n = 0;
  for (final run in plain.split(_spaces)) {
    if (run.isEmpty) continue;
    if (_wordish.hasMatch(run)) n++;
  }
  return n;
}

final RegExp _spaces = RegExp(r'\s+');

final RegExp _couldBeInline = RegExp(r'[\[\]{}\$*_~=+^`:]');
