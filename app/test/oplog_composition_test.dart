// **What is actually in your op log** — the measurement v0.24 §0 asks for
// before anything is built.
//
// The finding it exists to settle: `block.set` carries the ENTIRE block, so
// every autosave rewrites it. Measured synthetically, 752 bytes of log per
// save for a 411-character text block and 2,534 for a 2,193-character one —
// linear in the block, plus about 340 bytes of envelope. One character added
// to a 2,000-character paragraph therefore costs ~2.5 KB of permanent,
// replicated log, and pays it again at every pause in the sentence.
//
// Ink already gets a per-stroke diff for exactly this reason (`OpKind.inkStrokes`
// says so: whole-block writes were "50-1000x write amplification"). Text never
// got the same treatment, and giving it the same treatment costs a `v: 2`
// envelope, which older builds refuse by going read-only. That is a bump worth
// spending before 1.0 and expensive after it.
//
// **But it must not be built on an inference.** The 64.56 MB log v0.13
// recorded was 63.14 MB of INLINE INK, and that has since been converted to
// bytes; the text share of a real log today is unknown. This prints it.
//
//     ONOTE_OPLOG=/path/to/MyNotebook.onotebook flutter test test/oplog_composition_test.dart
//
// Point it at a `.onotebook` directory, at a `.onote` file (the sibling log
// directory is found), or at a whole workspace folder to sweep every notebook
// in it. It only ever READS.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openote/sync/op.dart';

/// One kind's share of the log.
class _Tally {
  int ops = 0;
  int bytes = 0;
  /// For `block.set` only: bytes by the block's own `type`.
  final Map<String, int> byBlockType = {};
  final Map<String, int> opsByBlockType = {};
}

String _bytes(int n) {
  if (n >= 1 << 30) return '${(n / (1 << 30)).toStringAsFixed(2)} GB';
  if (n >= 1 << 20) return '${(n / (1 << 20)).toStringAsFixed(2)} MB';
  if (n >= 1 << 10) return '${(n / (1 << 10)).toStringAsFixed(1)} KB';
  return '$n B';
}

String _pct(int part, int whole) =>
    whole == 0 ? '  0.0%' : '${(100 * part / whole).toStringAsFixed(1).padLeft(5)}%';

/// Every `ops/` directory under [root], however it was pointed at.
List<Directory> _logDirs(String root) {
  final entity = FileSystemEntity.typeSync(root);
  if (entity == FileSystemEntityType.notFound) return const [];
  final out = <Directory>[];
  void consider(String path) {
    final ops = Directory(p.join(path, 'ops'));
    if (ops.existsSync()) out.add(ops);
  }

  if (entity == FileSystemEntityType.file) {
    // A `.onote` container: its log is the sibling `.onotebook`.
    consider('${p.withoutExtension(root)}.onotebook');
    return out;
  }
  if (root.endsWith('.onotebook')) {
    consider(root);
    return out;
  }
  // A workspace: every notebook in it.
  for (final e in Directory(root).listSync()) {
    if (e is Directory && e.path.endsWith('.onotebook')) consider(e.path);
  }
  return out;
}

void main() {
  final target = Platform.environment['ONOTE_OPLOG'];

  test('what the op log is made of', () {
    if (target == null || target.isEmpty) {
      return markTestSkipped(
          'set ONOTE_OPLOG to a .onotebook, a .onote, or a workspace folder');
    }
    final dirs = _logDirs(target);
    expect(dirs, isNotEmpty,
        reason: 'no ops/ directory under $target — point this at a '
            '.onotebook, at its .onote, or at the workspace holding them');

    final byKind = <String, _Tally>{};
    var totalBytes = 0, totalOps = 0, undecodable = 0;

    for (final ops in dirs) {
      for (final f in ops.listSync().whereType<File>()) {
        if (!f.path.endsWith('.oplog')) continue;
        for (final line in const LineSplitter()
            .convert(f.readAsStringSync(encoding: utf8))) {
          if (line.trim().isEmpty) continue;
          // +1 for the newline the file actually carries.
          final size = utf8.encode(line).length + 1;
          totalBytes += size;
          totalOps++;
          final op = Op.decode(line);
          if (op == null) {
            undecodable += size;
            continue;
          }
          final name = op.rawTag ?? op.kind.tag;
          final t = byKind.putIfAbsent(name, _Tally.new)
            ..ops += 1
            ..bytes += size;
          if (op.kind == OpKind.blockSet) {
            final block = (op.map['block'] as Map?)?.cast<String, dynamic>();
            final type = (block?['type'] as String?) ?? '(none)';
            t.byBlockType[type] = (t.byBlockType[type] ?? 0) + size;
            t.opsByBlockType[type] = (t.opsByBlockType[type] ?? 0) + 1;
          }
        }
      }
    }

    final rows = byKind.entries.toList()
      ..sort((a, b) => b.value.bytes.compareTo(a.value.bytes));

    final out = StringBuffer()
      ..writeln('')
      ..writeln('OP LOG COMPOSITION — $target')
      ..writeln('  ${dirs.length} log director${dirs.length == 1 ? 'y' : 'ies'}, '
          '$totalOps ops, ${_bytes(totalBytes)}')
      ..writeln('');
    for (final e in rows) {
      out.writeln('  ${e.key.padRight(16)} ${_pct(e.value.bytes, totalBytes)}  '
          '${_bytes(e.value.bytes).padLeft(10)}  ${e.value.ops} ops  '
          '(${e.value.ops == 0 ? 0 : e.value.bytes ~/ e.value.ops} B each)');
      final split = e.value.byBlockType.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final b in split) {
        out.writeln('      ${b.key.padRight(12)} ${_pct(b.value, totalBytes)}  '
            '${_bytes(b.value).padLeft(10)}  '
            '${e.value.opsByBlockType[b.key]} ops');
      }
    }
    if (undecodable > 0) {
      out.writeln('  ${'(undecodable)'.padRight(16)} '
          '${_pct(undecodable, totalBytes)}  ${_bytes(undecodable).padLeft(10)}');
    }

    // THE NUMBER THE DECISION TURNS ON.
    final textSet = byKind['block.set']?.byBlockType['text'] ?? 0;
    out
      ..writeln('')
      ..writeln('  ── the v0.24 §0 question ─────────────────────────────')
      ..writeln('  text block.set is ${_pct(textSet, totalBytes)} of this log '
          '(${_bytes(textSet)}).')
      ..writeln(textSet * 5 > totalBytes
          ? '  Over a fifth. A per-edit text diff would pay for itself; spend\n'
              '  the v:2 envelope bump BEFORE 1.0, while it is cheap.'
          : '  Under a fifth. Not worth a format bump on this evidence —\n'
              '  re-run it after a few months of real writing.')
      ..writeln('');
    // ignore: avoid_print
    print(out);
  });
}
