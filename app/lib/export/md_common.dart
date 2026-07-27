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
