/// GFM pipe-table parsing — the read side of [tableToMarkdown].
///
/// Table interop used to be **one-way**: Openote exported GFM tables happily
/// and could not render one back, so a table pasted in as Markdown showed as
/// rows of raw pipes. Anything the app can write, it should be able to read.
///
/// Kept as pure functions in their own file so the grammar is testable without
/// building a widget.
library;

enum MdAlign { left, center, right }

class MdTable {
  MdTable({required this.header, required this.rows, required this.align});

  /// First row. GFM requires a header, so this is never empty.
  final List<String> header;
  final List<List<String>> rows;
  final List<MdAlign> align;

  int get columns => header.length;
}

/// A parsed table plus how many source lines it consumed.
typedef MdTableMatch = ({MdTable table, int consumed});

// A delimiter row: at least one dash per cell, optional leading/trailing pipe,
// optional `:` alignment markers. This is the line that makes a block of
// pipe-separated text a *table* rather than prose that happens to contain '|'.
final _delimiterRow = RegExp(r'^\s*\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)*\|?\s*$');

/// True if [line] contains an unescaped pipe.
bool _hasPipe(String line) {
  for (var i = 0; i < line.length; i++) {
    if (line[i] == '|' && (i == 0 || line[i - 1] != r'\'[0])) return true;
  }
  return false;
}

/// Split one table row into cells on unescaped pipes, unescaping `\|`.
///
/// Escaping matters both ways round: [tableToMarkdown] writes `\|` for a pipe
/// inside a cell, so failing to honour it here would split one cell into two
/// and silently corrupt a round-trip.
List<String> splitRow(String line) {
  var s = line.trim();
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|') && !s.endsWith(r'\|')) {
    s = s.substring(0, s.length - 1);
  }
  final cells = <String>[];
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == r'\'[0] && i + 1 < s.length && s[i + 1] == '|') {
      buf.write('|');
      i++;
      continue;
    }
    if (c == '|') {
      cells.add(buf.toString().trim());
      buf.clear();
      continue;
    }
    buf.write(c);
  }
  cells.add(buf.toString().trim());
  return cells;
}

MdAlign _alignOf(String spec) {
  final s = spec.trim();
  final left = s.startsWith(':');
  final right = s.endsWith(':');
  if (left && right) return MdAlign.center;
  if (right) return MdAlign.right;
  return MdAlign.left;
}

/// Try to parse a pipe table starting at [start].
///
/// Returns null unless [start] is a row containing a pipe AND the next line is
/// a delimiter row — the two-line signature is what keeps ordinary prose with a
/// pipe in it from being swallowed as a table.
MdTableMatch? parsePipeTable(List<String> lines, int start) {
  if (start + 1 >= lines.length) return null;
  if (!_hasPipe(lines[start])) return null;
  if (!_delimiterRow.hasMatch(lines[start + 1])) return null;

  final header = splitRow(lines[start]);
  final spec = splitRow(lines[start + 1]);
  if (header.isEmpty) return null;

  final align = [
    for (var i = 0; i < header.length; i++)
      i < spec.length ? _alignOf(spec[i]) : MdAlign.left
  ];

  final rows = <List<String>>[];
  var i = start + 2;
  for (; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty || !_hasPipe(line)) break;
    final cells = splitRow(line);
    // Ragged rows are normal in hand-written Markdown; pad or trim to the
    // header width rather than rejecting the table, which is what a reader
    // expects and what our own exporter already does on the way out.
    while (cells.length < header.length) {
      cells.add('');
    }
    rows.add(cells.length > header.length
        ? cells.sublist(0, header.length)
        : cells);
  }

  return (
    table: MdTable(header: header, rows: rows, align: align),
    consumed: i - start,
  );
}
