import '../markdown/md_syntax.dart' show atomIdPattern;

/// **A thing that is not text, living inside a text block.**
///
/// The reference lives in the block's own `text` as
/// `![alt](onote://atom/<id>)` (grammar: `MdInline.atom`), and the payload
/// lives beside it in the same block:
///
/// ```jsonc
/// "content": {
///   "text": "Results: ![3x2 table](onote://atom/0198…) and it holds.",
///   "atoms": {
///     "0198…": {"id": "0198…", "type": "table",
///               "content": {"cells": [["a","b"]], "colWidths": [0, 120]}}
///   }
/// }
/// ```
///
/// **In the host block, not as a sibling block** (v0.19 §B). Cut, copy, undo
/// and sync then move the text and its atoms as one thing: there are no
/// orphans to collect, and the canvas paths that walk `app.blocks` — culling,
/// marquee, z-order, the export's y/x sort — need no "skip the inline ones"
/// clause. A sibling-block model would have touched every one of them.
///
/// **The payload is a Block's own shape**, so it rides through `Block.toJson`
/// and `fromJson`, the op log's `block.set`, `read_page`, `append_blocks` and
/// the open-folder export with no new schema anywhere.
class InlineAtom {
  const InlineAtom({required this.id, required this.type, required this.content});

  final String id;

  /// `'table'` today. The string rather than [BlockType] because an atom of a
  /// type this build has never heard of must survive being read and written
  /// back — a newer device's notebook is not a corrupt one.
  final String type;

  final Map<String, dynamic> content;

  static const String scheme = 'onote://atom/';

  /// The reference text that stands for this atom in the buffer.
  ///
  /// The alt text is what every renderer that cannot draw the atom shows
  /// instead — an older build, a Markdown export, somebody else's viewer — so
  /// it says what the thing IS rather than being empty.
  String reference(String alt) => '![$alt]($scheme$id)';

  Map<String, dynamic> toJson() =>
      {'id': id, 'type': type, 'content': content};

  static InlineAtom? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final type = j['type'];
    if (id is! String || id.isEmpty || type is! String) return null;
    final c = j['content'];
    return InlineAtom(
      id: id,
      type: type,
      content: c is Map ? Map<String, dynamic>.from(c) : <String, dynamic>{},
    );
  }

  /// Every atom carried by [content], keyed by id. Empty for a block that has
  /// none, which is almost all of them.
  static Map<String, InlineAtom> allIn(Map<String, dynamic> content) {
    final raw = content['atoms'];
    if (raw is! Map) return const {};
    final out = <String, InlineAtom>{};
    for (final e in raw.entries) {
      final a = fromJson(e.value);
      if (a != null) out[a.id] = a;
    }
    return out;
  }

  /// Put [atom] into [content], creating the map if this is the first one.
  static void putIn(Map<String, dynamic> content, InlineAtom atom) {
    final raw = content['atoms'];
    final m = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    m[atom.id] = atom.toJson();
    content['atoms'] = m;
  }

  /// Drop any atom whose id no longer appears in [text].
  ///
  /// Deleting the reference is how somebody deletes the table, and without
  /// this its payload would sit in the block for ever — invisible, exported,
  /// synced, and counted against the note's size.
  static void pruneTo(Map<String, dynamic> content, String text) {
    final raw = content['atoms'];
    if (raw is! Map || raw.isEmpty) return;
    final live = {for (final id in idsIn(text)) id};
    final kept = <String, dynamic>{};
    for (final e in raw.entries) {
      if (live.contains('${e.key}')) kept['${e.key}'] = e.value;
    }
    if (kept.isEmpty) {
      content.remove('atoms');
    } else {
      content['atoms'] = kept;
    }
  }

  /// The atom ids referenced by [text], in the order they appear.
  static List<String> idsIn(String text) =>
      [for (final r in referencesIn(text)) r.id];

  /// Every reference in [text], with where it sits and what it points at.
  ///
  /// The positions are what an exporter needs: projecting an atom to its
  /// native Markdown means putting the projection where the reference was,
  /// not appending it to the end of the block.
  static List<({int start, int end, String id, String alt})> referencesIn(
          String text) =>
      [
        for (final m in _refRe.allMatches(text))
          (start: m.start, end: m.end, id: m.group(2)!, alt: m.group(1) ?? '')
      ];

  /// Where the reference to [id] sits in [text], or null when it is not
  /// there. By id rather than by offset because an atom's offsets move under
  /// it with every character typed in the paragraph, and the widget that
  /// needs this answer is built once and then kept.
  static ({int start, int end})? rangeIn(String text, String id) {
    for (final r in referencesIn(text)) {
      if (r.id == id) return (start: r.start, end: r.end);
    }
    return null;
  }

  /// Built from the grammar's own id pattern rather than a second copy of
  /// it: the reference this class WRITES and the reference `md_syntax` READS
  /// have to be the same thing or an atom is stored and never drawn.
  static final RegExp _refRe =
      RegExp(r'!\[([^\]]*)\]\(onote://atom/(' + atomIdPattern + r')\)');
}

/// **The one shape a table has, wherever it is kept.**
///
/// A table is `cells` plus the widths somebody dragged, and it is exactly
/// that whether it sits in a `BlockType.table` of its own or inside a
/// sentence. Keeping the reading of it in ONE place is what makes converting
/// between the two safe, and it is what stops the six things that already
/// read a table block — SQL cells, Markdown export, the open-folder export,
/// PDF, the word count, the importer — each growing their own idea of it.
class TableData {
  const TableData({required this.cells, required this.colWidths});

  /// Rows of plain strings, rectangular.
  final List<List<String>> cells;

  /// Per-column width in pixels; 0 means "work it out". Never shorter than
  /// the column count is not guaranteed — callers index defensively.
  final List<double> colWidths;

  /// Read a table out of any block content, normalising exactly as the table
  /// editor always has.
  ///
  /// **Every cell is stringified and every row is padded**, because the data
  /// really does arrive as other things: a CSV import writes numbers, the
  /// OneNote importer writes whatever the source had, `null` appears in a
  /// hand-edited file, and a jagged grid comes from both. The editor has
  /// always coerced with `toString()` and padded short rows to the widest —
  /// `RangeError` in `cellWidget` was the alternative — so a conversion that
  /// did anything else would change what the user sees.
  static TableData from(Map<String, dynamic> content) {
    final raw = content['cells'];
    final grid = <List<String>>[];
    if (raw is List) {
      for (final row in raw) {
        if (row is List) {
          grid.add([for (final c in row) c?.toString() ?? '']);
        } else if (row != null) {
          // A row that is not a list at all. One cell is a truer reading of
          // it than dropping the row, and dropping data silently is the one
          // thing a converter may never do.
          grid.add([row.toString()]);
        } else {
          grid.add(<String>[]);
        }
      }
    }
    if (grid.isEmpty) {
      return const TableData(cells: [
        ['', ''],
        ['', '']
      ], colWidths: []);
    }
    final cols = grid.fold(0, (m, r) => r.length > m ? r.length : m);
    for (final r in grid) {
      while (r.length < cols) {
        r.add('');
      }
    }
    final w = content['colWidths'];
    return TableData(
      cells: grid,
      colWidths: w is List
          ? [for (final v in w) v is num ? v.toDouble() : 0.0]
          : const [],
    );
  }

  Map<String, dynamic> toContent() => {
        'cells': [for (final r in cells) [...r]],
        if (colWidths.isNotEmpty) 'colWidths': [...colWidths],
      };

  int get rows => cells.length;
  int get cols => cells.isEmpty ? 0 : cells.first.length;

  /// What a renderer that cannot draw this shows instead, and what a screen
  /// reader says. Small, factual, and never empty.
  String get altText => '${rows}x$cols table';

  // ── Structure ────────────────────────────────────────────────────────────
  //
  // Every one of these returns a NEW table rather than mutating this one, so
  // a caller can compare before and after — the converter does, before it
  // writes anything — and so an undo snapshot taken from the old value is
  // genuinely the old value. They are here, on the data, rather than in the
  // widget because the right-click menu, the tests and the converter all need
  // the same arithmetic, and a second copy of it would be a second set of
  // off-by-ones.

  /// A copy with [value] at ([row], [col]). Out of range returns this table.
  TableData withCell(int row, int col, String value) {
    if (row < 0 || col < 0 || row >= rows || col >= cols) return this;
    final grid = [for (final r in cells) [...r]];
    grid[row][col] = value;
    return TableData(cells: grid, colWidths: colWidths);
  }

  /// An empty row inserted at [at] (`rows` appends).
  TableData insertRow(int at) {
    final i = at.clamp(0, rows);
    final grid = [for (final r in cells) [...r]];
    grid.insert(i, List.filled(cols == 0 ? 1 : cols, '', growable: true));
    return TableData(cells: grid, colWidths: colWidths);
  }

  /// An empty column inserted at [at] (`cols` appends).
  ///
  /// The widths move with the columns: inserting before a column somebody
  /// dragged out to 300px must not hand that 300px to the new empty one.
  TableData insertColumn(int at) {
    final i = at.clamp(0, cols);
    final grid = [for (final r in cells) [...r]..insert(i, '')];
    final w = [...colWidths];
    if (w.isNotEmpty) w.insert(i.clamp(0, w.length), 0.0);
    return TableData(cells: grid, colWidths: w);
  }

  /// Without row [at]. The last row is never removed — a table with no rows
  /// cannot be typed into, so it would be a one-way door.
  TableData removeRow(int at) {
    if (rows <= 1 || at < 0 || at >= rows) return this;
    final grid = [for (final r in cells) [...r]]..removeAt(at);
    return TableData(cells: grid, colWidths: colWidths);
  }

  /// Without column [at]. The last column is never removed, as above.
  TableData removeColumn(int at) {
    if (cols <= 1 || at < 0 || at >= cols) return this;
    final grid = [for (final r in cells) [...r]..removeAt(at)];
    final w = [...colWidths];
    if (at < w.length) w.removeAt(at);
    return TableData(cells: grid, colWidths: w);
  }

  /// Same cells, same widths — the test the converter runs before it writes.
  bool sameAs(TableData other) {
    if (rows != other.rows || cols != other.cols) return false;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (cells[r][c] != other.cells[r][c]) return false;
      }
    }
    if (colWidths.length != other.colWidths.length) return false;
    for (var i = 0; i < colWidths.length; i++) {
      if (colWidths[i] != other.colWidths[i]) return false;
    }
    return true;
  }
}

/// **Keep the payloads and the references in step, without losing a table to
/// a cut and paste.**
///
/// Two jobs, and they have to be one function because they are two halves of
/// the same invariant:
///
/// * An atom nobody references any more is *remembered* and then dropped.
///   Left in place its payload would sit in the block for ever — invisible,
///   exported, synced, and counted against the note's size.
/// * A reference whose payload is missing is *recalled*. This is what makes
///   cut-and-paste work: cutting the reference takes the text and leaves the
///   payload behind, and pasting it into another block — or back into this
///   one a minute later — arrives with nothing but an id. Dropping the
///   payload the moment its reference left would turn every cut table into an
///   empty box, which is the one outcome a table must never have.
///
/// [remember] is handed each atom on its way out and [recall] is asked for one
/// on the way back in; a caller with no memory passes neither and gets plain
/// pruning. Returns true when [content] changed.
bool reconcileAtoms(
  Map<String, dynamic> content,
  String text, {
  void Function(InlineAtom atom)? remember,
  InlineAtom? Function(String id)? recall,
}) {
  final referenced = InlineAtom.idsIn(text);
  final held = InlineAtom.allIn(content);
  var changed = false;

  for (final e in held.entries) {
    if (referenced.contains(e.key)) continue;
    remember?.call(e.value);
    changed = true;
  }
  if (changed) InlineAtom.pruneTo(content, text);

  if (recall == null) return changed;
  for (final id in referenced) {
    if (held.containsKey(id)) continue;
    final found = recall(id);
    if (found == null) continue;
    InlineAtom.putIn(content, found);
    changed = true;
  }
  return changed;
}

/// **Every table a block carries, in reading order.**
///
/// A table used to be a block, so a surface that wanted the page's tables
/// filtered `blocks.where(type == table)`. A table can now also be an atom
/// inside a paragraph, and a surface that does not know that does not merely
/// draw it wrong — it silently loses it: from an export, from a word count,
/// from the list of tables a SQL cell can query. This is the one answer to
/// "what tables are in here", so learning about atoms is one call each.
List<TableData> tablesIn(Map<String, dynamic> content) {
  final text = content['text'];
  if (text is! String || !text.contains(InlineAtom.scheme)) return const [];
  final atoms = InlineAtom.allIn(content);
  return [
    for (final id in InlineAtom.idsIn(text))
      if (atoms[id]?.type == 'table') TableData.from(atoms[id]!.content)
  ];
}
