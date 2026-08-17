/// Shared helpers for the open-format exporters/importers.
///
/// Consolidates three things that were previously copy-pasted (and drifting)
/// across `markdown_export.dart`, `open_export.dart`, `pdf_export.dart` and the
/// importers:
///  * [safeFilename] — a Unicode-aware, filesystem-safe name derived from a
///    title (keeps letters/digits of any script; strips only hostile chars);
///  * [markdownInline] — projects Openote's stored text into strict CommonMark
///    for the `.md` convenience files (wiki-links and the colour extension are
///    converted, not leaked verbatim — Data Model Spec §5.2);
///  * [tableToMarkdown] — one GFM-table renderer.
library;

// Characters illegal in Windows/macOS/Linux filenames, plus control chars.
final _invalidNameChars = RegExp(r'[<>:"/\\|?*\x00-\x1F]');
final _trailingDotsSpaces = RegExp(r'[. ]+$');
final _whitespaceRun = RegExp(r'\s+');
// Windows reserved device names (case-insensitive, with or without extension).
final _reservedName =
    RegExp(r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)', caseSensitive: false);

/// A filesystem-safe file/folder name derived from a user title. Unlike the old
/// ASCII-only `[^\w\- ]` scrub, this preserves international titles ("日本語",
/// "Über") and only removes characters that break real filesystems.
String safeFilename(String s, {String fallback = 'untitled'}) {
  var out = s
      .replaceAll(_invalidNameChars, ' ')
      .replaceAll(_whitespaceRun, ' ')
      .trim()
      .replaceAll(_trailingDotsSpaces, '');
  if (out.isEmpty || _reservedName.hasMatch(out)) return fallback;
  if (out.length > 120) out = out.substring(0, 120).trim();
  return out.isEmpty ? fallback : out;
}

final _wikiLink = RegExp(r'\[\[([^\]|]+)(?:\|([^\]]+))?\]\]');
final _colorWrap =
    RegExp(r'\{\{#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})? (.*?)\}\}', dotAll: true);

/// Project stored text into strict CommonMark for `.md` export:
///  * `{{#RRGGBB text}}` colour spans → their inner text (the colour extension
///    isn't standard Markdown, so we degrade to plain text rather than leak the
///    braces);
///  * `[[Title|id]]` wiki-links → `[Title](onote://page/id)`; `[[Title]]` →
///    `[Title]` (Data Model Spec §5.2 strict-Markdown mapping).
String markdownInline(String text) {
  var out = text.replaceAllMapped(_colorWrap, (m) => m.group(1) ?? '');
  out = out.replaceAllMapped(_wikiLink, (m) {
    final label = m.group(1)!.trim();
    final id = m.group(2)?.trim();
    return (id != null && id.isNotEmpty)
        ? '[$label](onote://page/$id)'
        : '[$label]';
  });
  return out;
}

/// Render a table block's `cells` (list-of-rows) as a GFM table. Tolerates
/// ragged rows by padding every row to the widest one; escapes pipes and
/// newlines so a multi-line cell can't break the table grid.
String tableToMarkdown(dynamic cells) {
  if (cells is! List || cells.isEmpty) return '';
  final rows = <List<String>>[
    for (final row in cells)
      if (row is List)
        [
          for (final c in row)
            (c?.toString() ?? '')
                .replaceAll('|', r'\|')
                .replaceAll('\n', ' ')
        ]
  ];
  if (rows.isEmpty) return '';
  final cols = rows.map((r) => r.length).fold(1, (a, b) => a > b ? a : b);
  for (final r in rows) {
    while (r.length < cols) {
      r.add('');
    }
  }
  final buf = StringBuffer()
    ..writeln('| ${rows[0].join(' | ')} |')
    ..writeln('|${List.filled(cols, ' --- ').join('|')}|');
  for (final r in rows.skip(1)) {
    buf.writeln('| ${r.join(' | ')} |');
  }
  return buf.toString().trimRight();
}

/// One line of stored text as a human would read it — markers gone.
///
/// For **UI summaries**: the planner's agenda rows, the find-tags rollup, and
/// anywhere else a line of a note is quoted outside the renderer that
/// understands it. Those surfaces were showing raw source — a to-do written as
/// a bullet appeared in the planner as `- Conjunction: p ∧ q`, dash and all,
/// and an emphasised phrase carried its asterisks.
///
/// Deliberately **not** a Markdown parser. It strips the leading block marker
/// (list bullet, ordered number, task box, heading hashes, block quote) and the
/// paired inline emphasis runs, and leaves everything else alone. A summary
/// line does not need a syntax tree, and a half-parser that tried to be one
/// would mangle the maths and code these notes are full of.
///
/// Inline stripping is conservative: a marker only comes off when it is
/// genuinely paired, so `2 * 3 * 4` keeps its asterisks and `a_1` keeps its
/// underscore.
String plainLine(String line) {
  var s = line.trim();

  // Leading block markers, in the order they can nest: quote, then list, then
  // heading. Only one round — `>> - # x` is not a shape any of these produce.
  s = s.replaceFirst(RegExp(r'^>\s*'), '');
  // `\s+|$` so a line that is ONLY a marker ("- ") reduces to empty rather
  // than to a stray dash.
  s = s.replaceFirst(RegExp(r'^(?:[-*+]|\d+[.)])(?:\s+|$)'), '');
  s = s.replaceFirst(RegExp(r'^\[[ xX]\]\s*'), ''); // task box after a bullet
  s = s.replaceFirst(RegExp(r'^#{1,6}\s+'), '');

  // Paired inline runs, longest marker first so `**bold**` is not seen as two
  // `*italic*` edges.
  //
  // `_` additionally requires a word boundary on the outside, which is
  // CommonMark's own intraword rule and the reason `a_1 and b_2` survives —
  // subscripts are everywhere in the notes this feature exists for.
  for (final marker in const ['***', '**', '~~', '==', '++', '`', '*']) {
    final m = RegExp.escape(marker);
    s = s.replaceAllMapped(
        RegExp('$m(?!\\s)(.+?)(?<!\\s)$m', dotAll: true), (x) => x.group(1)!);
  }
  s = s.replaceAllMapped(
      RegExp(r'(?<![\w])_(?!\s)(.+?)(?<!\s)_(?![\w])', dotAll: true),
      (x) => x.group(1)!);

  // Sub/superscript (`H~2~O`, `x^2^`). AFTER the `~~` pass above, so a
  // strikethrough is already gone and cannot be read as two subscripts. The
  // inner text forbids whitespace, which is the grammar's own rule
  // (markdown/md_syntax.dart) and what keeps "~5 to ~10" and "3^2 = 9 and
  // 4^2 = 16" reading as the arithmetic somebody actually wrote.
  s = s.replaceAllMapped(RegExp(r'~([^\s~]+)~'), (m) => m.group(1)!);
  s = s.replaceAllMapped(RegExp(r'\^([^\s^]+)\^'), (m) => m.group(1)!);

  // The colour extension and wiki-links degrade to their visible text, the
  // same way `markdownInline` degrades them for export.
  s = s.replaceAllMapped(
      RegExp(r'\{\{#[0-9a-fA-F]{6}\s+(.+?)\}\}', dotAll: true),
      (m) => m.group(1)!);
  s = s.replaceAllMapped(
      RegExp(r'\[\[([^\]|]+)(?:\|[^\]]*)?\]\]'), (m) => m.group(1)!);

  return s.trim();
}
