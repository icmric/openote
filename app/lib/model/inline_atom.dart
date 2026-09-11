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
      [for (final m in _refRe.allMatches(text)) m.group(1)!];

  /// Built from the grammar's own id pattern rather than a second copy of
  /// it: the reference this class WRITES and the reference `md_syntax` READS
  /// have to be the same thing or an atom is stored and never drawn.
  static final RegExp _refRe =
      RegExp(r'!\[[^\]]*\]\(onote://atom/(' + atomIdPattern + r')\)');
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
}
