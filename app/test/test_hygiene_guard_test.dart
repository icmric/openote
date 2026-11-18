// The suite's own rules, checked like any other behaviour. See
// `docs/writing-tests.md`.
//
// A fixed real-time sleep followed by an `expect` is a guess about how fast the
// machine is, and it was the shape of most of the "CI is red, the code is
// fine" failures in November 2026: right on a laptop, wrong on a loaded runner,
// and indistinguishable from a bug. New tests wait for the thing itself
// (`eventually`, `pumpUntil` in `support/wait.dart`) or run on a fake clock.
//
// The sleeps already here are counted per file and may only go DOWN. A sleep
// that is not a wait (a fake that is slow on purpose, a poll loop's step) is
// allowed with a `// sleep-ok: <why>` comment on the line above it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Sleeps that were here when the rule came in, by file. Lower a number when
/// you remove one; never raise it.
const _known = <String, int>{
  'blob_proof_test.dart': 1,
  'blob_read_through_test.dart': 1,
  'cloud_sync_test.dart': 4,
  'folder_join_test.dart': 5,
  'folder_publish_test.dart': 3,
  'folder_watch_test.dart': 1,
  'graph_giveup_test.dart': 2,
  'import_entry_test.dart': 1,
  'import_job_test.dart': 2,
  'math_parity_test.dart': 1,
  'nav_create_menu_test.dart': 2,
  'navigator_s7_test.dart': 1,
  'no_red_flash_test.dart': 2,
  'shared_delete_ui_test.dart': 1,
  'single_instance_test.dart': 2,
  'sync_dialog_progress_test.dart': 1,
  'sync_drive_card_test.dart': 1,
  'tool_follows_device_test.dart': 1,
  'undo_create_test.dart': 1,
  'undo_key_matches_button_test.dart': 1,
  'writing_menu_test.dart': 1,
};

final _sleep = RegExp(r'Future(?:<void>)?\.delayed\(\s*(?!Duration\.zero)');

/// Fixed sleeps in [src] that are not excused by a `sleep-ok:` comment on the
/// same line or the line above.
int sleepsIn(String src) {
  final lines = src.split('\n');
  var n = 0;
  for (var i = 0; i < lines.length; i++) {
    final hits = _sleep.allMatches(lines[i]).length;
    if (hits == 0) continue;
    final excused = lines[i].contains('sleep-ok:') ||
        (i > 0 && lines[i - 1].contains('sleep-ok:'));
    if (!excused) n += hits;
  }
  return n;
}

void main() {
  test('the rule sees what it is meant to', () {
    expect(sleepsIn('await Future<void>.delayed(const Duration(seconds: 1));'),
        1);
    expect(sleepsIn('await Future.delayed(d);'), 1);
    expect(sleepsIn('await Future<void>.delayed(Duration.zero);'), 0,
        reason: 'one turn of the event loop is not a guess about speed');
    expect(
        sleepsIn('// sleep-ok: slow on purpose\n'
            'await Future<void>.delayed(const Duration(seconds: 1));'),
        0);
  });

  test('no new fixed sleeps in tests', () {
    final dir = Directory('test');
    final problems = <String>[];
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final rel = f.path
          .substring(dir.path.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
      if (rel == 'support/wait.dart' || rel == 'test_hygiene_guard_test.dart') {
        continue;
      }
      final n = sleepsIn(f.readAsStringSync());
      final allowed = _known[rel] ?? 0;
      if (n > allowed) {
        problems.add('$rel: $n fixed sleep(s), $allowed allowed. Wait for the '
            'condition with eventually/pumpUntil (test/support/wait.dart), use '
            'a fake clock, or say why with `// sleep-ok:`.');
      } else if (n < allowed) {
        problems.add('$rel: down to $n from $allowed. Good: lower its number '
            'in _known in test/test_hygiene_guard_test.dart.');
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
