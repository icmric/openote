/// CSV → a table block. "Import data (csv)" from PLANNING.md — drop a file
/// exported from Excel, a bank, a lab instrument, onto the page and get the
/// same table the table button makes, editable like any other.
///
/// The parser is RFC 4180 with the two liberties real files force:
///  * the delimiter is DETECTED (comma, semicolon, tab) — Excel in half of
///    Europe writes semicolons, and "CSV" from a spreadsheet copy-paste is
///    usually tab-separated;
///  * bytes are decoded as UTF-8 with malformed sequences replaced rather
///    than rejected, because a Latin-1 export with one ° in it is still a
///    table the user can see and fix.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import '../model/models.dart';
import '../state/app_state.dart';
import 'xlsx_import.dart';

/// Rows and columns are capped, not because parsing is slow but because the
/// RESULT is a block the canvas lays out — a 50,000-row dump would freeze the
/// page every frame thereafter. The cap keeps the block usable; the caller
/// reports what was cut so truncation is never silent.
const int kCsvMaxRows = 500;
const int kCsvMaxCols = 64;

/// One parsed field at a time, quote-aware.
///
/// Handles: quoted fields with embedded delimiters and newlines, `""` as an
/// escaped quote, CRLF and bare-LF line ends, and a trailing newline not
/// producing a phantom empty row.
List<List<String>> parseCsv(String text, {String? delimiter}) {
  final delim = delimiter ?? detectCsvDelimiter(text);
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var sawAny = false;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    sawAny = true;
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++; // the escaped quote's second half
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
      continue;
    }
    if (c == '"' && field.isEmpty) {
      inQuotes = true;
    } else if (c == delim) {
      endField();
    } else if (c == '\r') {
      // CRLF: consumed here, the LF below ends the row. A bare CR (classic
      // Mac, effectively extinct) is treated as a line end too.
      if (i + 1 < text.length && text[i + 1] == '\n') continue;
      endRow();
    } else if (c == '\n') {
      endRow();
    } else {
      field.write(c);
    }
  }
  // The final row, when the file does not end in a newline.
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  if (!sawAny) return const [];
  return rows;
}

/// Which of comma, semicolon, tab this text most likely uses — counted
/// OUTSIDE quotes on the first non-empty line, so a title like "Smith, Jane"
/// does not vote for comma.
String detectCsvDelimiter(String text) {
  final firstLine = text
      .split('\n')
      .map((l) => l.trimRight())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  var comma = 0, semi = 0, tab = 0;
  var inQuotes = false;
  for (var i = 0; i < firstLine.length; i++) {
    final c = firstLine[i];
    if (c == '"') inQuotes = !inQuotes;
    if (inQuotes) continue;
    if (c == ',') comma++;
    if (c == ';') semi++;
    if (c == '\t') tab++;
  }
  if (tab > comma && tab > semi) return '\t';
  if (semi > comma) return ';';
  return ',';
}

/// The cells for a table block: capped and padded rectangular — the table
/// view and the Markdown exporter both assume every row has the header's
/// width, exactly as `md_table` pads on the way in. Shared by the CSV and
/// xlsx paths, so both truncate by the same rule and report it the same way.
({List<List<String>> cells, int droppedRows, int droppedCols}) tabularCells(
    List<List<String>> parsed) {
  // A lone empty trailing field from `a,b,\n` is data; a fully empty row from
  // a blank line is not.
  final rows = [
    for (final r in parsed)
      if (r.any((c) => c.trim().isNotEmpty)) r
  ];
  if (rows.isEmpty) return (cells: const [], droppedRows: 0, droppedCols: 0);

  final width = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
  final keptW = width > kCsvMaxCols ? kCsvMaxCols : width;
  final keptRows = rows.length > kCsvMaxRows ? kCsvMaxRows : rows.length;
  final cells = [
    for (var i = 0; i < keptRows; i++)
      [
        for (var j = 0; j < keptW; j++)
          j < rows[i].length ? rows[i][j] : '',
      ]
  ];
  return (
    cells: cells,
    droppedRows: rows.length - keptRows,
    droppedCols: width - keptW,
  );
}

({List<List<String>> cells, int droppedRows, int droppedCols}) csvCells(
        String text) =>
    tabularCells(parseCsv(text));

/// Decode, parse and place a table block at [at].
///
/// [placed] is false when the file held no rows — the caller decides the
/// fallback (a drop becomes an attachment instead, so it never vanishes).
/// [note] is a human sentence when something was cut; the caller SHOWS it,
/// because silent truncation reads as "imported everything" when it did not.
({bool placed, String? note}) insertCsvTable(
    AppState app, Uint8List bytes, Offset at) {
  final text = utf8.decode(bytes, allowMalformed: true);
  return _placeCells(app, csvCells(text), at);
}

/// Any tabular file this app can read — csv/tsv by parsing, .xlsx through
/// the minimal reader — placed as a table block. One entry point, so the
/// drop path and the menu item cannot drift in what they accept.
({bool placed, String? note}) insertTableFromFile(
    AppState app, String name, Uint8List bytes, Offset at) {
  if (name.toLowerCase().endsWith('.xlsx')) {
    final rows = readXlsxRows(bytes);
    if (rows == null) return (placed: false, note: null);
    return _placeCells(app, tabularCells(rows), at);
  }
  return insertCsvTable(app, bytes, at);
}

({bool placed, String? note}) _placeCells(
    AppState app,
    ({List<List<String>> cells, int droppedRows, int droppedCols}) r,
    Offset at) {
  if (r.cells.isEmpty) return (placed: false, note: null);
  final b = app.addBlock(Block(
    type: BlockType.table,
    x: at.dx,
    y: at.dy,
    w: (r.cells.first.length * 120).clamp(240, 960).toDouble(),
    content: {'cells': r.cells},
  ));
  app.select(b.id);
  if (r.droppedRows > 0 || r.droppedCols > 0) {
    final parts = [
      if (r.droppedRows > 0) '${r.droppedRows} more rows',
      if (r.droppedCols > 0) '${r.droppedCols} more columns',
    ];
    return (
      placed: true,
      note: 'Imported the first ${r.cells.length} rows — the file has '
          '${parts.join(' and ')} (a table block caps at $kCsvMaxRows×'
          '$kCsvMaxCols to keep the page fast).',
    );
  }
  return (placed: true, note: null);
}

/// Does this filename look like tabular data this importer should take?
bool looksLikeCsv(String name) {
  final n = name.toLowerCase();
  return n.endsWith('.csv') || n.endsWith('.tsv') || n.endsWith('.xlsx');
}
