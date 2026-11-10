/// A small Markdown-to-HTML converter, for the clipboard.
///
/// Word, Google Docs and Outlook paste `text/html` with its formatting; none of
/// them reads Markdown. This covers what [pageMarkdownOf] writes — headings,
/// paragraphs, emphasis, code, links, lists, quotes, rules, tables and
/// pictures — and nothing more. Anything else comes out as an escaped
/// paragraph, which pastes as the same words.
library;

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Convert [markdown]. [imageSrc] maps a picture's path in the Markdown to the
/// `src` to emit (a data URI, normally); returning null drops the picture.
String markdownToHtml(String markdown, {String? Function(String path)? imageSrc}) {
  final lines = markdown.replaceAll('\r\n', '\n').split('\n');
  final out = StringBuffer();
  var i = 0;

  String inline(String s) {
    // Code spans first, so their contents are not read as emphasis.
    final spans = <String>[];
    var t = s.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) {
      spans.add('<code>${_esc(m[1]!)}</code>');
      return '\u0000${spans.length - 1}\u0000';
    });
    t = _esc(t);
    t = t.replaceAllMapped(RegExp(r'!\[([^\]]*)\]\(([^)\s]+)[^)]*\)'), (m) {
      final src = imageSrc?.call(m[2]!.replaceAll('&amp;', '&'));
      return src == null ? '' : '<img src="$src" alt="${m[1]}">';
    });
    t = t.replaceAllMapped(RegExp(r'\[([^\]]+)\]\(([^)\s]+)\)'), (m) {
      final href = m[2]!;
      final safe = RegExp(r'^(https?:|mailto:|#|\.{0,2}/|[\w.-]+/)',
              caseSensitive: false)
          .hasMatch(href);
      return safe ? '<a href="$href">${m[1]}</a>' : m[1]!;
    });
    t = t.replaceAllMapped(
        RegExp(r'\*\*(.+?)\*\*|__(.+?)__'), (m) => '<b>${m[1] ?? m[2]}</b>');
    t = t.replaceAllMapped(RegExp(r'(?<![*\w])\*([^*\n]+)\*(?!\*)|(?<![_\w])_([^_\n]+)_(?![_\w])'),
        (m) => '<i>${m[1] ?? m[2]}</i>');
    t = t.replaceAllMapped(RegExp(r'~~(.+?)~~'), (m) => '<s>${m[1]}</s>');
    return t.replaceAllMapped(
        RegExp('\u0000(\\d+)\u0000'), (m) => spans[int.parse(m[1]!)]);
  }

  bool isRow(String l) => l.trimLeft().startsWith('|');
  List<String> cells(String l) {
    var t = l.trim();
    if (t.startsWith('|')) t = t.substring(1);
    if (t.endsWith('|')) t = t.substring(0, t.length - 1);
    return t.split('|').map((c) => c.trim()).toList();
  }

  while (i < lines.length) {
    final line = lines[i];
    if (line.trim().isEmpty) {
      i++;
      continue;
    }
    final fence = RegExp(r'^```(\w*)').firstMatch(line);
    if (fence != null) {
      final buf = <String>[];
      i++;
      while (i < lines.length && !lines[i].startsWith('```')) {
        buf.add(lines[i++]);
      }
      i++;
      out.write('<pre><code>${_esc(buf.join('\n'))}</code></pre>');
      continue;
    }
    if (line.trim() == r'$$') {
      final buf = <String>[];
      i++;
      while (i < lines.length && lines[i].trim() != r'$$') {
        buf.add(lines[i++]);
      }
      i++;
      out.write('<p>${_esc(buf.join('\n'))}</p>');
      continue;
    }
    final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
    if (h != null) {
      final n = h[1]!.length;
      out.write('<h$n>${inline(h[2]!)}</h$n>');
      i++;
      continue;
    }
    if (RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$').hasMatch(line)) {
      out.write('<hr>');
      i++;
      continue;
    }
    if (isRow(line) &&
        i + 1 < lines.length &&
        RegExp(r'^\s*\|?[\s:|-]+\|[\s:|-]*$').hasMatch(lines[i + 1])) {
      final head = cells(line);
      i += 2;
      out.write('<table border="1" cellspacing="0" cellpadding="4"><tr>');
      for (final c in head) {
        out.write('<th>${inline(c)}</th>');
      }
      out.write('</tr>');
      while (i < lines.length && isRow(lines[i])) {
        out.write('<tr>');
        for (final c in cells(lines[i++])) {
          out.write('<td>${inline(c)}</td>');
        }
        out.write('</tr>');
      }
      out.write('</table>');
      continue;
    }
    if (line.startsWith('>')) {
      final buf = <String>[];
      while (i < lines.length && lines[i].startsWith('>')) {
        buf.add(lines[i++].replaceFirst(RegExp(r'^>\s?'), ''));
      }
      out.write('<blockquote>${inline(buf.join(' '))}</blockquote>');
      continue;
    }
    final li = RegExp(r'^(\s*)([-*+]|\d+[.)])\s+(.*)$').firstMatch(line);
    if (li != null) {
      final ordered = RegExp(r'\d').hasMatch(li[2]!);
      out.write(ordered ? '<ol>' : '<ul>');
      while (i < lines.length) {
        final m = RegExp(r'^(\s*)([-*+]|\d+[.)])\s+(.*)$').firstMatch(lines[i]);
        if (m == null) break;
        out.write('<li>${inline(m[3]!)}</li>');
        i++;
      }
      out.write(ordered ? '</ol>' : '</ul>');
      continue;
    }
    final buf = <String>[line];
    i++;
    while (i < lines.length &&
        lines[i].trim().isNotEmpty &&
        !lines[i].startsWith('```') &&
        !RegExp(r'^(#{1,6}\s|>|\s*([-*+]|\d+[.)])\s)').hasMatch(lines[i]) &&
        !isRow(lines[i])) {
      buf.add(lines[i++]);
    }
    out.write('<p>${buf.map(inline).join('<br>')}</p>');
  }
  return out.toString();
}
