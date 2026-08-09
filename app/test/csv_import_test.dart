// CSV → table block ("import data (csv)" from PLANNING.md).
//
// The parser is where real files go to die, so it gets the awkward cases:
// quoted commas, escaped quotes, embedded newlines, CRLF, European
// semicolons, tab-separated "CSV", ragged rows. The drop path gets an
// end-to-end: a .csv on the canvas becomes the same editable table block the
// table button makes.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/canvas/media_drop.dart';
import 'package:openote/export/csv_import.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('the parser against real-world CSV', () {
    test('plain rows and columns', () {
      expect(parseCsv('a,b,c\n1,2,3'), [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ]);
    });

    test('quoted fields keep their commas, quotes and newlines', () {
      expect(parseCsv('name,notes\n"Smith, Jane","said ""hi""\nthen left"'), [
        ['name', 'notes'],
        ['Smith, Jane', 'said "hi"\nthen left'],
      ]);
    });

    test('CRLF line ends and a trailing newline add no phantom rows', () {
      expect(parseCsv('a,b\r\n1,2\r\n'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('European Excel semicolons are detected', () {
      expect(parseCsv('ort;wert\nwien;3,14'), [
        ['ort', 'wert'],
        ['wien', '3,14'],
      ]);
    });

    test('tab-separated pasteboard "CSV" is detected', () {
      expect(parseCsv('a\tb\t"c d"\n1\t2\t3'), [
        ['a', 'b', 'c d'],
        ['1', '2', '3'],
      ]);
    });

    test('a delimiter inside quotes does not vote in detection', () {
      // One semicolon outside quotes, two commas inside them: semicolon wins.
      expect(detectCsvDelimiter('"a,b,c";x'), ';');
    });

    test('ragged rows pad to the widest, blank lines vanish', () {
      final r = csvCells('a,b,c\n1\n\n2,3');
      expect(r.cells, [
        ['a', 'b', 'c'],
        ['1', '', ''],
        ['2', '3', ''],
      ]);
      expect(r.droppedRows, 0);
    });

    test('the caps cut visibly, never silently', () {
      final big = List.generate(kCsvMaxRows + 40, (i) => '$i,x').join('\n');
      final r = csvCells(big);
      expect(r.cells.length, kCsvMaxRows);
      expect(r.droppedRows, 40,
          reason: 'the caller shows this — truncation must have a number');
    });
  });

  group('dropped onto the canvas', () {
    late Repository repo;
    late Directory tmp;
    late AppState app;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_csv_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Data');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      await app
          .selectPage(app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
    });

    tearDown(() {
      AppState.syncLogEnabled = true;
      if (!haveSqlite) return;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('a .csv becomes an editable table block where it landed', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final f = File('${tmp.path}/marks.csv')
        ..writeAsStringSync('unit,mark\n"maths, discrete",82\nphysics,74');
      final before = app.blocks.length;

      final n = await dropFilesOntoCanvas(
          app, [f.path], const Offset(120, 140));

      expect(n, 1);
      expect(app.blocks.length, before + 1);
      final table = app.blocks.last;
      expect(table.type, BlockType.table,
          reason: 'tabular data becomes a TABLE, not an attachment');
      expect(table.x, 120);
      expect(table.content['cells'], [
        ['unit', 'mark'],
        ['maths, discrete', '82'],
        ['physics', '74'],
      ]);
    });

    test('an empty csv falls back to an attachment, never vanishes', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final f = File('${tmp.path}/empty.csv')..writeAsStringSync('\n\n');
      final before = app.blocks.length;
      await dropFilesOntoCanvas(app, [f.path], const Offset(50, 50));
      expect(app.blocks.length, before + 1);
      expect(app.blocks.last.type, BlockType.file,
          reason: 'the drop must land as SOMETHING the user can see');
    });

    test('insertCsvTable reports what the caps cut', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final big = List.generate(kCsvMaxRows + 8, (i) => '$i,x').join('\n');
      final r = insertCsvTable(
          app, Uint8List.fromList(utf8.encode(big)), const Offset(0, 0));
      expect(r.placed, isTrue);
      expect(r.note, contains('8 more rows'));
    });
  });
}
