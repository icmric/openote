// The import ENTRY POINTS — the wiring between "user clicks Import" and the
// job actually starting.
//
// This exists because that wiring broke twice in the same way, and neither
// break was visible in a unit test of the import itself. Both times a dialog
// popped itself and then handed the popped route's `BuildContext` to the code
// that does the work; every `context.mounted` guard inside was then false, so
// the file picker opened, the user chose their notebook, and nothing happened
// at all. Silent, and indistinguishable from a slow import.
//
// The fix is structural — the entry points take a `ScaffoldMessengerState`,
// which outlives any route — and these tests hold that line at the seam where
// it actually matters.

import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/export/import_job.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/notebook_manager.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  tearDown(() => ImportJob.current = null);

  /// An in-memory pick. `XFile(path)` would do REAL file I/O in
  /// `readAsBytes`, which never completes under `testWidgets`' fake clock —
  /// the same trap as the repository above, one layer along.
  XFile picked(String name) => XFile.fromData(
        Uint8List.fromList(List.filled(64, 7)),
        name: name,
        path: name,
      );

  /// A picker that TAKES TIME, like the real one. This matters: the route the
  /// old code depended on is not defunct the instant `Navigator.pop` is
  /// called — it dies once its exit animation finishes. In the real app the
  /// OS file dialog sits in that gap for seconds, which is exactly why
  /// `context.mounted` was false by the time the import looked at it. A picker
  /// that returns instantly would let a stale-context check pass and the test
  /// would prove nothing.
  Future<XFile?> Function() slowPick(String name) => () async {
        await Future<void>.delayed(const Duration(seconds: 2));
        return picked(name);
      };

  /// **`tester.runAsync`, not a bare `await`.** A `testWidgets` body runs
  /// under a fake clock, and real filesystem futures only complete on the real
  /// event loop — so opening a repository with a plain `await` here hangs the
  /// test forever rather than failing it.
  Future<AppState> fixture(WidgetTester tester, String name) async {
    final tmp = Directory.systemTemp.createTempSync(name);
    late Repository repo;
    late AppState app;
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Existing');
      app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
    });
    return app;
  }

  testWidgets(
      'the package import reaches the job even when the dialog that started '
      'it has been popped', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await fixture(tester, 'onote_entry_');

    // A sentinel job already in flight. `ImportJob.start` refuses it and says
    // so — which is the point: reaching that refusal proves the flow ran all
    // the way to `start`, and it does so WITHOUT depending on whether this
    // build has the native core linked or spawning a real parse isolate.
    ImportJob.current = ImportJob.debugCreate(app, 'First.onepkg');

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(
        body: Builder(builder: (inner) {
          return TextButton(
            onPressed: () async {
              // The exact shape that broke: capture, pop, then run.
              final m = ScaffoldMessenger.of(inner);
              await showDialog<void>(
                context: inner,
                builder: (d) => TextButton(
                  onPressed: () async {
                    Navigator.pop(d); // the route the import used to depend on
                    await importOneNotePackageWithFeedback(m, app,
                        pickFile: slowPick('Discrete Maths.onepkg'));
                  },
                  child: const Text('go'),
                ),
              );
            },
            child: const Text('open'),
          );
        }),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('go'));
    // Past the pop animation AND past the slow picker, in that order — the
    // route is genuinely gone by the time the import looks at anything.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // Before the fix this screen was empty: no snackbar, no job, no error —
    // the flow returned one line after the picker because the dialog it was
    // handed had just been popped.
    expect(find.byType(SnackBar), findsOneWidget,
        reason: 'the import must report SOMETHING; silence is the bug');
  });

  testWidgets('a second import is refused rather than interleaved',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await fixture(tester, 'onote_entry2_');

    ImportJob.current = ImportJob.debugCreate(app, 'First.onepkg');

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(
        body: Builder(builder: (context) {
          return TextButton(
            onPressed: () => importOneNotePackageWithFeedback(
                ScaffoldMessenger.of(context), app,
                pickFile: () async => picked('Second.onepkg')),
            child: const Text('go'),
          );
        }),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.textContaining('already running'), findsOneWidget);
    expect(ImportJob.current!.fileName, 'First.onepkg',
        reason: 'the running job must not be replaced');
  });

  testWidgets('cancelling the picker is silent, not an error', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await fixture(tester, 'onote_entry3_');

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(
        body: Builder(builder: (context) {
          return TextButton(
            onPressed: () => importOneNotePackageWithFeedback(
                ScaffoldMessenger.of(context), app,
                pickFile: () async => null),
            child: const Text('go'),
          );
        }),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(ImportJob.current, isNull);
  });
}
