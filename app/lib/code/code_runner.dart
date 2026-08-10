/// Run a code cell — SQL and JavaScript, sandboxed (v0.14 plan §1–3).
///
/// The rules this file exists to enforce, in the order they matter:
///
///  1. **Nothing here is ever called except by a click** (or Ctrl+Enter on
///     the block being edited). Opening, syncing and importing pages never
///     touch this file.
///  2. **The engines have no ambient authority.** SQL runs in a fresh
///     in-memory SQLite with nothing attached; JS runs in a bare QuickJS
///     (JavaScriptCore on Apple) constructed DIRECTLY — deliberately not
///     through flutter_js's `getJavascriptRuntime()`, whose default enables
///     a fetch() bridge. The JS world is exactly the globals the prelude
///     installs: `tables`, `console.log`, `print`.
///  3. **Bounded**: a wall-clock timeout enforced by killing the run's
///     isolate, an output cap so a print loop cannot manufacture megabytes
///     that would sync everywhere, and a row cap on result tables.
///
/// The honest residual: `Isolate.kill` takes effect at a Dart safepoint,
/// and a single native call that never returns (a pathological recursive
/// CTE inside one sqlite3_step, an infinite JS loop inside one eval) has
/// none — the UI gets its timeout answer on time, but that thread burns CPU
/// until its call completes or the app exits. Closing it needs the engines'
/// own interrupt hooks (sqlite3_progress_handler, JS_SetInterruptHandler),
/// which the current bindings do not expose. "A stranger's cell can waste
/// CPU, and nothing else" still holds; the five-second bound on the waste
/// does not yet, and this comment is the record of that.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_js/javascriptcore/jscore_runtime.dart';
import 'package:flutter_js/quickjs/quickjs_runtime2.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

/// How long a run may take before it is stopped.
const kCodeRunTimeout = Duration(seconds: 5);

/// Output text cap: past this the output is truncated with a notice. The
/// output PERSISTS in the block and syncs, so this is a format guard, not a
/// UI nicety.
const kMaxOutputChars = 64 * 1024;

/// Result-table row cap, same reasoning as the CSV import cap: the result
/// becomes a widget the canvas lays out.
const kMaxOutputRows = 200;

/// Languages the Run button appears for.
bool isRunnableLanguage(String? language) =>
    language == 'sql' || language == 'js' || language == 'javascript';

/// A page table handed to the run: [name] is the raw first header cell (the
/// runner sanitises), [cells] the padded rectangular grid, header first.
typedef CodeTable = ({String name, List<List<String>> cells});

/// What a run produced. Stored in the block's content as
/// `{output: toJson(), ranAt: …}` — additively, so older builds render the
/// source untouched and simply show no output.
class CodeOutput {
  const CodeOutput.text(String this.text)
      : kind = 'text',
        cells = null,
        truncated = false;
  const CodeOutput.error(String this.text)
      : kind = 'error',
        cells = null,
        truncated = false;
  const CodeOutput.table(List<List<String>> this.cells,
      {this.truncated = false})
      : kind = 'table',
        text = null;
  CodeOutput._(this.kind, this.text, this.cells, this.truncated);

  final String kind; // text | table | error
  final String? text;
  final List<List<String>>? cells;
  final bool truncated;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        if (text != null) 'text': text,
        if (cells != null) 'cells': cells,
        if (truncated) 'truncated': true,
      };

  static CodeOutput? fromJson(Object? j) {
    if (j is! Map) return null;
    final kind = j['kind'];
    if (kind is! String) return null;
    return CodeOutput._(
      kind,
      j['text'] as String?,
      (j['cells'] as List?)
          ?.map((r) => [for (final c in (r as List)) '$c'])
          .toList(),
      j['truncated'] == true,
    );
  }
}

/// Run [source] as [language] against [tables].
///
/// [sqliteLibrary] tells the run's isolate where the native SQLite lives —
/// needed under `flutter test`, where the override the harness installs is
/// per-isolate; null in the app, where the bundled library resolves by name.
Future<CodeOutput> runCode({
  required String language,
  required String source,
  List<CodeTable> tables = const [],
  String? sqliteLibrary,
  Duration timeout = kCodeRunTimeout,
}) async {
  final receive = ReceivePort();
  final errors = ReceivePort();
  final Isolate isolate;
  try {
    isolate = await Isolate.spawn(
      _entry,
      [
        receive.sendPort,
        {
          'language': language,
          'source': source,
          'tables': [
            for (final t in tables) {'name': t.name, 'cells': t.cells}
          ],
          'sqlite': sqliteLibrary,
        },
      ],
      onError: errors.sendPort,
      debugName: 'onote-code-run',
    );
  } catch (e) {
    receive.close();
    errors.close();
    return CodeOutput.error('Could not start the run: $e');
  }
  try {
    final first = await Future.any([
      receive.first,
      errors.first.then((e) => {'kind': 'error', 'text': '${(e as List)[0]}'}),
    ]).timeout(timeout);
    return CodeOutput.fromJson(first) ??
        const CodeOutput.error('The run produced nothing readable.');
  } on TimeoutException {
    isolate.kill(priority: Isolate.immediate);
    return CodeOutput.error(
        'Stopped — the run was still going after ${timeout.inSeconds} s.');
  } finally {
    receive.close();
    errors.close();
    isolate.kill(priority: Isolate.immediate);
  }
}

// ── Inside the run isolate ────────────────────────────────────────────────

void _entry(List<Object?> args) {
  final out = args[0] as SendPort;
  final p = (args[1] as Map).cast<String, Object?>();
  Map<String, dynamic> result;
  try {
    result = switch (p['language']) {
      'sql' => _runSql(p),
      'js' || 'javascript' => _runJs(p),
      // The timeout machinery's own test hook: a Dart-level spin, which —
      // unlike a stuck native call — kill() can actually reap.
      '_stall' => _stall(),
      _ => {'kind': 'error', 'text': 'No runner for ${p['language']}.'},
    };
  } catch (e) {
    result = {'kind': 'error', 'text': '$e'};
  }
  out.send(result);
}

Map<String, dynamic> _stall() {
  while (true) {}
}

List<CodeTable> _tablesOf(Map<String, Object?> p) => [
      for (final t in (p['tables'] as List? ?? const []))
        (
          name: '${(t as Map)['name']}',
          cells: [
            for (final r in (t['cells'] as List))
              [for (final c in (r as List)) '$c']
          ]
        ),
    ];

/// `Marks!` → `marks`, `2024 results` → `t_2024_results`, `` → fallback.
String _identifier(String raw, String fallback) {
  var s = raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
  s = s.replaceAll(RegExp(r'^_+|_+$'), '');
  if (s.isEmpty) return fallback;
  if (RegExp(r'^[0-9]').hasMatch(s)) s = 't_$s';
  return s;
}

Map<String, dynamic> _runSql(Map<String, Object?> p) {
  final lib = p['sqlite'] as String?;
  if (lib != null) {
    open.overrideForAll(() => DynamicLibrary.open(lib));
  }
  final db = sqlite3.openInMemory();
  try {
    // Every table block on the page, mounted twice: as t1…tn (predictable)
    // and, when the first header cell yields a usable name, as a view under
    // that name (readable). Numbers are inserted AS numbers so AVG and
    // ORDER BY behave; everything else stays text.
    final taken = <String>{};
    final mounted = <String>[];
    var i = 0;
    for (final t in _tablesOf(p)) {
      i++;
      final tn = 't$i';
      final header = t.cells.isNotEmpty ? t.cells.first : const <String>[];
      final cols = <String>[];
      for (var c = 0; c < header.length; c++) {
        var name = _identifier(header[c], 'c${c + 1}');
        while (cols.contains(name)) {
          name = '${name}_';
        }
        cols.add(name);
      }
      if (cols.isEmpty) continue;
      db.execute('CREATE TABLE "$tn" (${cols.map((c) => '"$c"').join(', ')})');
      final insert = db.prepare(
          'INSERT INTO "$tn" VALUES (${List.filled(cols.length, '?').join(', ')})');
      for (final row in t.cells.skip(1)) {
        insert.execute([
          for (var c = 0; c < cols.length; c++)
            c < row.length ? (num.tryParse(row[c]) ?? row[c]) : ''
        ]);
      }
      insert.dispose();
      final alias = _identifier(t.name, '');
      var shown = tn;
      if (alias.isNotEmpty && alias != tn && taken.add(alias)) {
        db.execute('CREATE VIEW "$alias" AS SELECT * FROM "$tn"');
        shown = '$alias ($tn)';
      }
      mounted.add(shown);
    }

    // Every statement runs; the LAST one that yields columns is the output.
    // That is how a scratch `CREATE TABLE …; INSERT …; SELECT …` cell reads.
    //
    // One statement at a time, NOT prepareMultiple: preparing eagerly parses
    // the INSERT against a table the un-run CREATE has not made yet, and the
    // whole scratch-cell shape fails with "no such table" before anything
    // executes.
    List<List<String>>? outCells;
    for (final sql in _splitSql(p['source'] as String? ?? '')) {
      final s = db.prepare(sql);
      try {
        final rs = s.select();
        if (rs.columnNames.isNotEmpty &&
            (rs.rows.isNotEmpty || _looksLikeSelect(sql))) {
          outCells = [
            rs.columnNames.map((c) => '$c').toList(),
            for (final row in rs.rows) [for (final v in row) _cell(v)],
          ];
        }
      } finally {
        s.dispose();
      }
    }
    if (outCells == null) {
      return const CodeOutput.text('Done.').toJson();
    }
    var truncated = false;
    if (outCells.length - 1 > kMaxOutputRows) {
      outCells = outCells.sublist(0, kMaxOutputRows + 1);
      truncated = true;
    }
    return CodeOutput.table(outCells, truncated: truncated).toJson();
  } on SqliteException catch (e) {
    // The one everyone hits first is a table name; answer it in the error.
    final hint = e.message.contains('no such table')
        ? '\nTables on this page: '
            '${_tablesOf(p).isEmpty ? '(none — put a table block on the page)' : _mountedNames(p)}'
        : '';
    return CodeOutput.error('${e.message}$hint').toJson();
  } finally {
    db.dispose();
  }
}

/// Statements, split on `;` — but only OUTSIDE string literals, quoted
/// identifiers, and both comment forms, because a semicolon in a string is
/// data. The same shape of care the CSV parser takes with commas.
List<String> _splitSql(String source) {
  final out = <String>[];
  final buf = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    if (c == "'" || c == '"' || c == '`') {
      // A literal or quoted identifier runs to its closing quote; doubled
      // quotes inside are the escape.
      buf.write(c);
      i++;
      while (i < source.length) {
        buf.write(source[i]);
        if (source[i] == c) {
          if (i + 1 < source.length && source[i + 1] == c) {
            buf.write(c);
            i++;
          } else {
            break;
          }
        }
        i++;
      }
      i++;
    } else if (c == '-' && i + 1 < source.length && source[i + 1] == '-') {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
    } else if (c == '/' && i + 1 < source.length && source[i + 1] == '*') {
      i += 2;
      while (i + 1 < source.length &&
          !(source[i] == '*' && source[i + 1] == '/')) {
        i++;
      }
      i += 2;
    } else if (c == ';') {
      if (buf.toString().trim().isNotEmpty) out.add(buf.toString());
      buf.clear();
      i++;
    } else {
      buf.write(c);
      i++;
    }
  }
  if (buf.toString().trim().isNotEmpty) out.add(buf.toString());
  return out;
}

bool _looksLikeSelect(String sql) {
  final s = sql.trimLeft().toLowerCase();
  return s.startsWith('select') || s.startsWith('with') || s.startsWith('pragma');
}

String _mountedNames(Map<String, Object?> p) {
  final names = <String>[];
  var i = 0;
  for (final t in _tablesOf(p)) {
    i++;
    final alias = _identifier(t.name, '');
    names.add(alias.isEmpty ? 't$i' : '$alias (t$i)');
  }
  return names.join(', ');
}

String _cell(Object? v) {
  if (v == null) return '';
  if (v is double && v == v.roundToDouble()) return '${v.round()}';
  return '$v';
}

Map<String, dynamic> _runJs(Map<String, Object?> p) {
  // Constructed directly — see the library comment. macOS/iOS use the
  // system JavaScriptCore; everything else the bundled QuickJS.
  final rt = (Platform.isMacOS || Platform.isIOS)
      ? JavascriptCoreRuntime()
      : QuickJsRuntime2();
  try {
    // The whole world the cell gets. `tables` is data already on the page;
    // console/print capture into a buffer this side reads back.
    final tableJson = <String, List<Map<String, Object?>>>{};
    var i = 0;
    for (final t in _tablesOf(p)) {
      i++;
      final header = t.cells.isNotEmpty ? t.cells.first : const <String>[];
      final rows = [
        for (final row in t.cells.skip(1))
          {
            for (var c = 0; c < header.length; c++)
              (header[c].trim().isEmpty ? 'c${c + 1}' : header[c].trim()):
                  c < row.length ? (num.tryParse(row[c]) ?? row[c]) : ''
          }
      ];
      final alias = _identifier(t.name, 't$i');
      tableJson[alias] = rows;
    }
    rt.evaluate('''
globalThis.__onoteOut = [];
(function () {
  function fmt(x) {
    try { return (typeof x === 'object' && x !== null) ? JSON.stringify(x) : String(x); }
    catch (e) { return String(x); }
  }
  function log() {
    globalThis.__onoteOut.push(Array.prototype.slice.call(arguments).map(fmt).join(' '));
  }
  globalThis.console = { log: log, info: log, warn: log, error: log };
  globalThis.print = log;
})();
globalThis.tables = ${jsonEncode(tableJson)};
''');
    final res = rt.evaluate(p['source'] as String? ?? '');
    final captured = rt.evaluate('JSON.stringify(globalThis.__onoteOut)');
    final lines = <String>[];
    try {
      final decoded = jsonDecode(captured.stringResult);
      if (decoded is List) lines.addAll(decoded.map((e) => '$e'));
    } catch (_) {}
    if (res.isError) {
      final err = [...lines, res.stringResult].join('\n');
      return CodeOutput.error(_cap(err)).toJson();
    }
    final value = res.stringResult;
    if (value.isNotEmpty && value != 'undefined' && value != 'null') {
      lines.add(value);
    }
    return CodeOutput.text(
            _cap(lines.isEmpty ? 'Done — nothing printed.' : lines.join('\n')))
        .toJson();
  } finally {
    rt.dispose();
  }
}

String _cap(String s) => s.length <= kMaxOutputChars
    ? s
    : '${s.substring(0, kMaxOutputChars)}\n… output truncated at '
        '${kMaxOutputChars ~/ 1024} KB.';
