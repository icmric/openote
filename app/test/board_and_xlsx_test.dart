// Items 4 and 5 of PLANNING.md, the shipped slices:
//
//   Tables — "import data (xlxs)": the minimal xlsx reader, tested against a
//   file BUILT FROM RAW PARTS in the test, so every branch (shared strings,
//   inline strings, styled multi-run strings, numbers, booleans, formula
//   cells with cached values, sparse rows) is exercised without a fixture
//   binary checked into the repo.
//
//   Calendar and tasks — "a trello like task board": the board block's
//   content mutations driven through the real widget, because a board whose
//   drags update the screen but not the saved content would sync as an
//   unchanged page.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/board_block_view.dart';
import 'package:openote/export/csv_import.dart';
import 'package:openote/export/xlsx_import.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

/// A real .xlsx, assembled from its actual parts.
Uint8List _tinyXlsx() {
  const workbook = '''
<?xml version="1.0"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="Data" sheetId="1" r:id="rId7"/></sheets>
</workbook>''';
  const rels = '''
<?xml version="1.0"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId7" Type="…/worksheet" Target="worksheets/theSheet.xml"/>
</Relationships>''';
  const shared = '''
<?xml version="1.0"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <si><t>unit</t></si>
  <si><r><t>styled </t></r><r><t>runs</t></r></si>
</sst>''';
  const sheet = '''
<?xml version="1.0"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
    <row r="2"><c r="A2"><v>82.5</v></c><c r="C2" t="b"><v>1</v></c></row>
    <row r="3"><c r="A3"><f>SUM(A2)</f><v>82.5</v></c>
               <c r="B3" t="inlineStr"><is><t>inline</t></is></c></row>
  </sheetData>
</worksheet>''';
  final zip = Archive()
    ..addFile(ArchiveFile('xl/workbook.xml', workbook.length, utf8.encode(workbook)))
    ..addFile(ArchiveFile(
        'xl/_rels/workbook.xml.rels', rels.length, utf8.encode(rels)))
    ..addFile(ArchiveFile(
        'xl/sharedStrings.xml', shared.length, utf8.encode(shared)))
    ..addFile(ArchiveFile(
        'xl/worksheets/theSheet.xml', sheet.length, utf8.encode(sheet)));
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('the minimal xlsx reader', () {
    test('EVERY CELL KIND, AND THE SHEET IS FOUND BY ITS RELATIONSHIP', () {
      // The sheet is deliberately NOT worksheets/sheet1.xml — a reader that
      // guesses the filename instead of following the rels breaks on any
      // workbook whose sheets were reordered or renamed.
      final rows = readXlsxRows(_tinyXlsx());
      expect(rows, isNotNull);
      expect(rows![0], ['unit', 'styled runs']);
      expect(rows[1][0], '82.5');
      expect(rows[1][1], '', reason: 'sparse B2 pads as empty');
      expect(rows[1][2], 'TRUE');
      expect(rows[2][0], '82.5',
          reason: 'a formula cell imports its CACHED value — the numbers the '
              'user saw, not a formula engine');
      expect(rows[2][1], 'inline');
    });

    test('bytes that are not an xlsx are refused, not misread', () {
      expect(readXlsxRows(Uint8List.fromList(utf8.encode('a,b\n1,2'))), isNull);
      final emptyZip =
          Uint8List.fromList(ZipEncoder().encode(Archive()));
      expect(readXlsxRows(emptyZip), isNull,
          reason: 'a zip with no workbook is not a spreadsheet');
    });
  });

  group('on a page', () {
    late Repository repo;
    late Directory tmp;
    late AppState app;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_board_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Board');
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

    test('an .xlsx becomes the same table block a .csv does', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final r = insertTableFromFile(
          app, 'marks.xlsx', _tinyXlsx(), const Offset(50, 60));
      expect(r.placed, isTrue);
      final table = app.blocks.last;
      expect(table.type, BlockType.table);
      // Padded to the WIDEST row (row 2 reaches column C), same as CSV.
      expect((table.content['cells'] as List).first,
          ['unit', 'styled runs', '']);
    });

    Block board() => app.addBlock(Block(
        type: BlockType.board,
        x: 0,
        y: 0,
        w: 700,
        content: BoardBlockView.starterContent()));

    Widget host(Block b) => MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: app,
              builder: (_, __) => SizedBox(
                  width: 760, height: 500, child: BoardBlockView(block: b, app: app)),
            ),
          ),
        );

    testWidgets('ADDING A CARD CHANGES THE CONTENT, NOT JUST THE SCREEN',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = board();
      await t.pumpWidget(host(b));

      await t.tap(find.text('Add a card').first);
      await t.pump();
      await t.enterText(find.byType(TextField), 'revise chapter 3');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();

      final cols = b.content['columns'] as List;
      expect((cols[0] as Map)['cards'], ['revise chapter 3'],
          reason: 'a board whose drags only move pixels syncs as unchanged');
      expect(find.text('revise chapter 3'), findsOneWidget);
      app.cancelPendingSave();
    });

    testWidgets('A CARD DRAGS TO ANOTHER COLUMN, AND THE MOVE PERSISTS',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = board();
      (b.content['columns'] as List)[0]['cards'] = ['ship it'];
      await t.pumpWidget(host(b));

      // From the card in "To do" onto "Doing"'s add-a-card tail.
      final from = t.getCenter(find.text('ship it'));
      final to = t.getCenter(find.text('Add a card').at(1));
      final g = await t.startGesture(from);
      await t.pump(const Duration(milliseconds: 100));
      await g.moveTo(to);
      await t.pump();
      await g.up();
      await t.pump();

      final cols = b.content['columns'] as List;
      expect((cols[0] as Map)['cards'], isEmpty);
      expect((cols[1] as Map)['cards'], ['ship it']);
      app.cancelPendingSave();
    });

    testWidgets('emptying a card deletes it, like an emptied text box',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = board();
      (b.content['columns'] as List)[2]['cards'] = ['done thing'];
      await t.pumpWidget(host(b));

      await t.tap(find.text('done thing'));
      await t.pump();
      await t.enterText(find.byType(TextField), '');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();

      expect(((b.content['columns'] as List)[2] as Map)['cards'], isEmpty);
      app.cancelPendingSave();
    });
  });
}
