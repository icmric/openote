// A mirror must refuse a destination that overlaps its source.
//
// Found the hard way, on the owner's own machine (2026-10-05): a target set to
// a folder that contained the notebook's own log directory, so each run copied
// the last run's output and the recursive walk compounded it. Three
// generations were on disk before anyone noticed:
//
//     assets/demo/demo.onotebook/2026-10-05_133141/demo.onotebook/…
//     assets/demo/demo.onotebook/…
//     assets/demo/…
//
// Reported as "the backup copy also has a copy of all its backups". See
// docs/planning/v1.0.2.md §18b.
//
// The property is simple and worth stating plainly: **a copy must never be an
// input to the next copy.** Returning null rather than throwing, because a
// misconfigured target must not fail the save that triggered it — mirroring is
// a side effect of saving, and v1.0.2 §18 is full of the consequences of
// treating it as more than that.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/sync/mirrors.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory source;

  setUp(() {
    root = Directory.systemTemp.createTempSync('onote_mirror_overlap_');
    source = Directory(p.join(root.path, 'Notes.onotebook'))
      ..createSync(recursive: true);
    File(p.join(source.path, 'manifest.json')).writeAsStringSync('{}');
    Directory(p.join(source.path, 'ops')).createSync();
    File(p.join(source.path, 'ops', 'dev.oplog')).writeAsStringSync('{}\n');
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  MirrorTarget target(String path, {int keep = 0}) =>
      MirrorTarget(path: path, keepVersions: keep);

  test('a target inside the source is refused', () async {
    // The exact shape that compounded: the destination sits under the very
    // directory being walked.
    final inside = p.join(source.path, 'backups');
    expect(await mirrorNotebook(source.path, target(inside)), isNull);
    expect(Directory(inside).existsSync(), isFalse,
        reason: 'nothing should have been written');
  });

  test('a target that IS the source is refused', () async {
    expect(await mirrorNotebook(source.path, target(source.path)), isNull);
  });

  test('a source inside the target is refused', () async {
    // The same walk from the other end: mirroring a notebook into a folder
    // that already contains it.
    expect(await mirrorNotebook(source.path, target(root.path)), isNull);
  });

  test('`..` and a trailing separator cannot defeat it', () async {
    // Spelled differently, same place. Canonicalised before comparing, so a
    // path the user typed by hand is treated as what it resolves to.
    final sneaky = '${p.join(source.path, 'ops', '..')}${p.separator}';
    expect(await mirrorNotebook(source.path, target(sneaky)), isNull);
  });

  test('a separate target still works', () async {
    // The negative control, and it is not optional: every assertion above
    // passes on a build where `mirrorNotebook` returns null unconditionally.
    final away = Directory(p.join(root.path, 'elsewhere'))
      ..createSync(recursive: true);
    // `elsewhere` is inside `root`, and so is the source — siblings overlap
    // neither way, which is the common real arrangement.
    final out = await mirrorNotebook(source.path, target(away.path));

    expect(out, isNotNull, reason: 'a sibling destination is fine');
    expect(File(p.join(out!, 'manifest.json')).existsSync(), isTrue);
    expect(File(p.join(out, 'ops', 'dev.oplog')).existsSync(), isTrue);
  });

  test('running twice into a separate target does not nest', () async {
    // The behaviour the bug produced, asserted against directly: a second run
    // must refresh the copy, not copy the copy.
    final away = Directory(p.join(root.path, 'elsewhere'))
      ..createSync(recursive: true);
    final first = await mirrorNotebook(source.path, target(away.path));
    final second = await mirrorNotebook(source.path, target(away.path));

    expect(second, first, reason: 'the same destination, refreshed');
    expect(Directory(p.join(first!, 'Notes.onotebook')).existsSync(), isFalse,
        reason: 'a copy inside the copy is the bug');
  });
}
