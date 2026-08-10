// The sandboxed code runner (v0.14 phases 1–2).
//
// SQL is tested fully — the engine ships with the app, and the test harness
// hands the runner's isolate the same native library it uses itself. The JS
// half probes its engine first: QuickJS arrives via the Flutter build, so
// under a bare `flutter test` the probe fails fast and the JS tests skip —
// the same honest arrangement as pdfium.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/code/code_runner.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  CodeTable marks() => (
        name: 'unit',
        cells: [
          ['unit', 'mark'],
          ['maths', '82'],
          ['physics', '74'],
          ['history', '91'],
        ]
      );

  Future<CodeOutput> sql(String source, {List<CodeTable> tables = const []}) =>
      runCode(
        language: 'sql',
        source: source,
        tables: tables,
        sqliteLibrary: sqliteLibraryPathForTests,
      );

  group('SQL against the page', () {
    test('A PAGE TABLE IS A SQL TABLE, by its header name and as t1', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final byName =
          await sql('SELECT unit FROM unit ORDER BY mark DESC', tables: [marks()]);
      expect(byName.kind, 'table');
      expect(byName.cells![0], ['unit']);
      expect(byName.cells![1], ['history'], reason: '91 sorts first');

      final byIndex =
          await sql('SELECT COUNT(*) AS n FROM t1', tables: [marks()]);
      expect(byIndex.cells![1], ['3']);
    });

    test('numbers behave as numbers — AVG works on imported text', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final r = await sql('SELECT ROUND(AVG(mark), 1) FROM unit',
          tables: [marks()]);
      expect(r.cells![1], ['82.3'],
          reason: 'cells were strings on the page; the mount parses them');
    });

    test('a scratch cell: create, insert, select — last SELECT is the output',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final r = await sql('''
        CREATE TABLE scratch (a, b);
        INSERT INTO scratch VALUES (1, 2), (3, 4);
        SELECT SUM(a) AS sa, SUM(b) AS sb FROM scratch;
      ''');
      expect(r.kind, 'table');
      expect(r.cells![0], ['sa', 'sb']);
      expect(r.cells![1], ['4', '6']);
    });

    test('no SELECT → a quiet Done', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final r = await sql('CREATE TABLE x (y)');
      expect(r.kind, 'text');
      expect(r.text, 'Done.');
    });

    test('a wrong table name names the tables that DO exist', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final r = await sql('SELECT * FROM nope', tables: [marks()]);
      expect(r.kind, 'error');
      expect(r.text, contains('no such table'));
      expect(r.text, contains('unit (t1)'),
          reason: 'the first question after this error is always "then what '
              'are they called"');
    });

    test('the row cap cuts visibly', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final r = await sql('''
        WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM c LIMIT 500)
        SELECT x FROM c;
      ''');
      expect(r.kind, 'table');
      expect(r.cells!.length, kMaxOutputRows + 1, reason: 'header + cap');
      expect(r.truncated, isTrue);
    });
  });

  test('THE TIMEOUT KILLS A RUNAWAY RUN', () async {
    // '_stall' spins in Dart, which — unlike a stuck native call — the kill
    // can actually reap; it exists to prove the timeout machinery, and the
    // library comment records why a stuck NATIVE call is still only bounded
    // at the UI, not on its thread.
    final r = await runCode(
      language: '_stall',
      source: '',
      timeout: const Duration(seconds: 2),
    );
    expect(r.kind, 'error');
    expect(r.text, contains('Stopped'));
  }, timeout: const Timeout(Duration(seconds: 15)));

  group('JavaScript', () {
    var haveJs = false;
    setUpAll(() async {
      // QuickJS ships with the Flutter build, not the test VM: probe once,
      // skip honestly when it is not there.
      final probe = await runCode(language: 'js', source: '1 + 1');
      haveJs = probe.kind == 'text' && probe.text!.contains('2');
    });

    test('expressions evaluate, console is captured', () async {
      if (!haveJs) return markTestSkipped('QuickJS unavailable under test VM');
      final r = await runCode(
          language: 'js',
          source: 'console.log("hi", {a: 1}); [1,2,3].length');
      expect(r.kind, 'text');
      expect(r.text, contains('hi {"a":1}'));
      expect(r.text, contains('3'));
    });

    test('page tables arrive as data', () async {
      if (!haveJs) return markTestSkipped('QuickJS unavailable under test VM');
      final r = await runCode(
        language: 'js',
        source:
            'tables.unit.filter(r => r.mark > 80).map(r => r.unit).join(",")',
        tables: [marks()],
      );
      expect(r.text, contains('maths,history'));
    });

    test('THE WORLD IS ONLY WHAT WE INSTALLED — no fetch, no require',
        () async {
      if (!haveJs) return markTestSkipped('QuickJS unavailable under test VM');
      final r = await runCode(
          language: 'js',
          source: '[typeof fetch, typeof require, typeof XMLHttpRequest]'
              '.join(",")');
      expect(r.text, contains('undefined,undefined,undefined'),
          reason: 'ambient authority is the thing the engine choice exists '
              'to not have');
    });
  });
}
