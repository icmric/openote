/// Minimal .xlsx → rows reader ("import data (xlsx)" from PLANNING.md).
///
/// An .xlsx is a zip of XML, and both the unzip and the XML parse were
/// ALREADY in this app's dependency tree — so this is a hand-rolled reader
/// of exactly the four parts a data import needs (workbook → first sheet,
/// its relationship target, the shared-string table, the cells), rather
/// than a spreadsheet package. What it reads: shared and inline strings,
/// numbers, booleans, and a formula cell's CACHED VALUE — which is the right
/// answer for an import, because the user wants the numbers they saw, not a
/// formula engine. What it does not read: dates as dates (they arrive as
/// Excel's serial numbers), styling, merged-cell geometry, other sheets.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// The first worksheet's rows, or null when [bytes] is not a readable xlsx.
/// Sparse cells land at their true column; callers pad/cap via the same
/// helper the CSV path uses.
List<List<String>>? readXlsxRows(Uint8List bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return null; // not a zip → not an xlsx
  }
  String? textOf(String path) {
    final f = zip.findFile(path);
    if (f == null) return null;
    return utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  final workbookXml = textOf('xl/workbook.xml');
  if (workbookXml == null) return null;

  try {
    // Which file IS the first sheet: workbook names it by relationship id,
    // the rels file maps the id to a path. Assuming `sheet1.xml` skips both
    // hops and is wrong exactly when someone reordered or renamed sheets —
    // which spreadsheets people actually use have usually had done to them.
    final workbook = XmlDocument.parse(workbookXml);
    final sheet = workbook.findAllElements('sheet').firstOrNull;
    if (sheet == null) return null;
    final rid = sheet.attributes
        .firstWhere((a) => a.name.local == 'id',
            orElse: () => XmlAttribute(XmlName('id'), ''))
        .value;

    var sheetPath = 'xl/worksheets/sheet1.xml';
    final relsXml = textOf('xl/_rels/workbook.xml.rels');
    if (relsXml != null && rid.isNotEmpty) {
      final rel = XmlDocument.parse(relsXml)
          .findAllElements('Relationship')
          .where((r) => r.getAttribute('Id') == rid)
          .firstOrNull;
      final target = rel?.getAttribute('Target');
      if (target != null && target.isNotEmpty) {
        sheetPath = target.startsWith('/')
            ? target.substring(1)
            : 'xl/${target.replaceFirst(RegExp('^\\./'), '')}';
      }
    }

    final sharedStrings = <String>[];
    final ssXml = textOf('xl/sharedStrings.xml');
    if (ssXml != null) {
      for (final si in XmlDocument.parse(ssXml).findAllElements('si')) {
        // Concatenate every text run: a styled cell stores its string as
        // several <r><t> runs, and taking only the first drops mid-cell text.
        sharedStrings
            .add(si.findAllElements('t').map((t) => t.innerText).join());
      }
    }

    final sheetXml = textOf(sheetPath);
    if (sheetXml == null) return null;
    final rows = <List<String>>[];
    for (final row in XmlDocument.parse(sheetXml).findAllElements('row')) {
      final cells = <String>[];
      for (final c in row.findAllElements('c')) {
        final col = _columnIndex(c.getAttribute('r'));
        final t = c.getAttribute('t');
        final v = c.findElements('v').firstOrNull?.innerText;
        final String value;
        if (t == 's') {
          final i = int.tryParse(v ?? '');
          value = (i != null && i >= 0 && i < sharedStrings.length)
              ? sharedStrings[i]
              : '';
        } else if (t == 'inlineStr') {
          value = c.findAllElements('t').map((e) => e.innerText).join();
        } else if (t == 'b') {
          value = v == '1' ? 'TRUE' : 'FALSE';
        } else {
          value = v ?? '';
        }
        // Sparse rows: place at the true column, padding the gap.
        final at = col ?? cells.length;
        while (cells.length < at) {
          cells.add('');
        }
        if (cells.length == at) {
          cells.add(value);
        } else {
          cells[at] = value;
        }
      }
      rows.add(cells);
    }
    return rows;
  } catch (_) {
    return null; // malformed XML anywhere → not a table we can honestly show
  }
}

/// `A1` → 0, `AB3` → 27. Null when the cell has no reference (legal; the
/// cell then lands after its predecessor).
int? _columnIndex(String? ref) {
  if (ref == null) return null;
  var col = 0;
  var seen = false;
  for (final ch in ref.codeUnits) {
    if (ch >= 0x41 && ch <= 0x5A) {
      col = col * 26 + (ch - 0x40);
      seen = true;
    } else {
      break;
    }
  }
  return seen ? col - 1 : null;
}
