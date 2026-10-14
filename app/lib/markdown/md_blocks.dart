/// **Markdown in, Openote's own objects out.**
///
/// A Markdown document pasted whole into one text block keeps working as
/// Markdown, but it is not what somebody typing the same notes would have
/// made: a fenced code block stays fenced text inside the paragraph (no
/// highlighting, no Run, no language picker), and a GFM table stays rows of
/// raw pipes — drawn as a table, but not one you can tab through, size, or
/// that fits its box, and it turns back into pipes the moment you edit.
///
/// So this splits it the way the app itself would hold it:
///
///  * fenced code (```lang) → a `code` block, its language resolved through
///    the picker's own alias table (`languageFor`), so ```py and ```c++ land
///    as the same language a pick from the menu would;
///  * a GFM pipe table → an inline table ATOM inside the surrounding text
///    block, the same shape Insert → Table and the table-block converter
///    write (`model/inline_atom.dart`);
///  * everything else → text blocks, one per run of prose between code.
///
/// Pure — positions are left at 0 for the caller to lay out — so it is
/// testable without an app, and [atomizePipeTables] is reusable by anything
/// else that wants pipes turned into tables, such as the editor's planned
/// "convert pipe tables when leaving edit mode" (the read side of
/// `tableToMarkdown`).
library;

import '../core/ids.dart';
import '../editor/code_languages.dart';
import '../model/inline_atom.dart';
import '../model/models.dart';
import 'md_table.dart';

/// Default box widths for blocks made from Markdown — the Markdown folder
/// importer's text width, so an API-written page looks like an imported one.
const double kMarkdownTextWidth = 640;
const double kMarkdownCodeWidth = 640;

final RegExp _fenceOpen = RegExp(r'^ {0,3}(`{3,}|~{3,})\s*([^\s`]*)');

bool _closes(String line, String fence) {
  final t = line.trim();
  if (t.isEmpty || t[0] != fence[0]) return false;
  var n = 0;
  while (n < t.length && t[n] == fence[0]) {
    n++;
  }
  return n >= fence.length && t.substring(n).trim().isEmpty;
}

/// Turn every GFM pipe table in [text] into an inline table atom.
///
/// Returns the rewritten text (each table replaced by its reference, on a line
/// of its own) and the atoms to put beside it with [InlineAtom.putIn]. Fenced
/// code is left alone — pipes in a code sample are code. Text with no table in
/// it comes back unchanged with no atoms.
({String text, List<InlineAtom> atoms}) atomizePipeTables(
  String text, {
  required String madeIn,
  String Function()? atomId,
}) {
  final lines = text.split('\n');
  final out = <String>[];
  final atoms = <InlineAtom>[];
  String? fence;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (fence != null) {
      out.add(line);
      if (_closes(line, fence)) fence = null;
      continue;
    }
    final open = _fenceOpen.firstMatch(line);
    if (open != null) {
      fence = open.group(1);
      out.add(line);
      continue;
    }
    final m = parsePipeTable(lines, i);
    if (m == null) {
      out.add(line);
      continue;
    }
    final t = m.table;
    final atom = InlineAtom(
      id: (atomId ?? newId)(),
      type: 'table',
      content: {
        'cells': [
          [...t.header],
          for (final r in t.rows) [...r],
        ],
        'madeIn': madeIn,
      },
    );
    atoms.add(atom);
    out.add(atom.reference(TableData.referenceAlt));
    i += m.consumed - 1;
  }
  return (text: atoms.isEmpty ? text : out.join('\n'), atoms: atoms);
}

/// Split [markdown] into text and code blocks, tables as inline atoms.
///
/// Blocks come back in reading order at (0, 0); the caller places them.
List<Block> markdownToBlocks(
  String markdown, {
  required String madeIn,
  double textWidth = kMarkdownTextWidth,
  double codeWidth = kMarkdownCodeWidth,
}) {
  final lines = markdown.replaceAll('\r\n', '\n').split('\n');
  final blocks = <Block>[];
  final prose = <String>[];

  void flushProse() {
    // Blank lines at the edges of a run are the gaps between blocks, which
    // the layout already provides.
    while (prose.isNotEmpty && prose.first.trim().isEmpty) {
      prose.removeAt(0);
    }
    while (prose.isNotEmpty && prose.last.trim().isEmpty) {
      prose.removeLast();
    }
    if (prose.isEmpty) return;
    final r = atomizePipeTables(prose.join('\n'), madeIn: madeIn);
    final content = <String, dynamic>{'text': r.text, 'autoWidth': false};
    for (final a in r.atoms) {
      InlineAtom.putIn(content, a);
    }
    blocks.add(Block(
        type: BlockType.text, x: 0, y: 0, w: textWidth, content: content));
    prose.clear();
  }

  for (var i = 0; i < lines.length; i++) {
    final open = _fenceOpen.firstMatch(lines[i]);
    if (open == null) {
      prose.add(lines[i]);
      continue;
    }
    flushProse();
    final fence = open.group(1)!;
    final info = open.group(2) ?? '';
    final body = <String>[];
    // An unclosed fence runs to the end of the document (CommonMark).
    for (i++; i < lines.length && !_closes(lines[i], fence); i++) {
      body.add(lines[i]);
    }
    blocks.add(Block(
      type: BlockType.code,
      x: 0,
      y: 0,
      w: codeWidth,
      content: {
        'source': body.join('\n'),
        'language': languageFor(info).id,
      },
    ));
  }
  flushProse();
  return blocks;
}
