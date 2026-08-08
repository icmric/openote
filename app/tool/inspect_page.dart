// Read one page out of a real .onote and print what it holds.
//
// Read-only. For answering "is the content actually missing from the notebook
// on disk, or does it just look wrong on screen" without guessing.
//
//   dart run tool/inspect_page.dart <file.onote> <title substring>
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('usage: dart run tool/inspect_page.dart <file.onote> <title>');
    exit(2);
  }
  for (final rel in const [
    'build/windows/x64/runner/Debug/sqlite3.dll',
    'build/windows/x64/runner/Release/sqlite3.dll',
  ]) {
    if (File(rel).existsSync()) {
      open.overrideForAll(() => DynamicLibrary.open(File(rel).absolute.path));
      break;
    }
  }
  final db = sqlite3.open(args[0], mode: OpenMode.readOnly);
  final rows = db.select(
      "SELECT id, title FROM nodes WHERE kind='page' AND deleted_at IS NULL "
      'AND lower(title) LIKE ?',
      ['%${args[1].toLowerCase()}%']);
  if (rows.isEmpty) {
    stdout.writeln('no page matching "${args[1]}"');
    return;
  }
  for (final r in rows) {
    final id = r['id'] as String;
    stdout.writeln('== "${r['title']}"  ($id)');
    final pm = db.select(
        'SELECT json, LENGTH(json) AS n FROM page_mirror WHERE page_id=?', [id]);
    if (pm.isEmpty) {
      stdout.writeln('   NO page_mirror ROW — the page has no content at all');
      continue;
    }
    stdout.writeln('   page JSON: ${pm.first['n']} bytes');
    final j = jsonDecode(pm.first['json'] as String) as Map<String, dynamic>;
    final blocks = (j['blocks'] as List? ?? const []);
    stdout.writeln('   blocks: ${blocks.length}');
    for (final raw in blocks) {
      final b = (raw as Map).cast<String, dynamic>();
      final c = (b['content'] as Map?)?.cast<String, dynamic>() ?? {};
      final where = '(${(b['x'] as num?)?.round()},${(b['y'] as num?)?.round()})'
          ' w=${(b['w'] as num?)?.round()} h=${(b['h'] as num?)?.round()}';
      final type = b['type'];
      String what;
      if (type == 'ink') {
        final ink = c['ink'];
        what = ink is Map
            ? 'ink ref n=${ink['n']}'
            : 'ink inline strokes=${(c['strokes'] as List?)?.length}';
      } else if (type == 'image') {
        what = 'image blob=${c['blob']}';
      } else {
        final t = (c['text'] as String? ?? '').replaceAll('\n', ' | ');
        what = t.length > 90 ? '${t.substring(0, 90)}…' : t;
      }
      stdout.writeln('   ${type.toString().padRight(6)} $where  $what');
    }
  }
  db.dispose();
}
