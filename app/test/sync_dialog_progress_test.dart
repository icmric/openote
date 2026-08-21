// The wait after you pick a cloud folder, and what the dialog does with it.
//
// Reported: "poor feedback given when selecting a cloud folder to sync with.
// Options to grey out however as the process can sometimes take some time for
// larger notebooks a spinner icon where the select button was… would be
// great". Greying the button was the whole of it, and a greyed button with
// nothing moving is not distinguishable from an app that has frozen.
//
// Two things are easy to get wrong here and neither is visible by reading the
// code, so both are measured rather than eyeballed:
//
//  1. **Nothing may move.** The obvious fix — swap the label for the spinner —
//     shrinks the button to 13px mid-press and drags the row and the dialog
//     around with it. A dialog rearranging itself while you wait reads as a
//     second thing going wrong. So the button's rect and the dialog's rect are
//     compared for EQUALITY across the moment the spinner appears.
//  2. **The spinner may not outlive the work.** One still turning beside the
//     red failure line says the app is still trying when it has already given
//     up — a worse lie than the silence it replaced. So the failing path is
//     driven too, not just the happy one.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/sync_dialog.dart';

import 'support/sqlite.dart';

/// An [AppState] whose folder move is held open until the test lets go.
///
/// The move is the only slow part, and a real one finishes long before a frame
/// can be looked at — so there would be no "while it runs" to assert anything
/// about. Holding it open IS the test subject.
class _GatedApp extends AppState {
  _GatedApp(super._repo);

  /// Non-null once a move has started; complete it to let the move finish.
  Completer<String>? gate;

  @override
  Future<String> moveNotebookToFolder(String nb, String targetDir) =>
      (gate = Completer<String>()).future;
}

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  final spinner = find.byType(CircularProgressIndicator);

  /// The "Choose a folder…" button — the dialog's only [OutlinedButton].
  ///
  /// Deliberately NOT found through its label. The implementation this file
  /// exists to rule out is "replace the label with the spinner", and a finder
  /// that goes through the label loses the button exactly when that happens —
  /// so the rect comparison below, the assertion that matters, would never
  /// run. (Nor `find.byType`: `OutlinedButton.icon` builds a private subclass,
  /// whose runtimeType a byType finder does not match.)
  final chooser = find.byWidgetPredicate((w) => w is OutlinedButton,
      description: 'the "Choose a folder…" button');

  Future<_GatedApp> newApp(WidgetTester tester) async {
    late _GatedApp app;
    late Repository repo;
    final tmp = Directory.systemTemp.createTempSync('onote_syncprog_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    // `tester.runAsync`, not a bare await: a `testWidgets` body runs on a fake
    // clock and real filesystem futures only complete on the real event loop.
    await tester.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Progress');
      app = _GatedApp(repo)..notebookId = nb.id;
      app.reloadNodes();
      await app.selectPage(
          app.nodes.where((n) => n.kind == NodeKind.page).first.id);
    });
    return app;
  }

  /// The folder the OS picker will "return", and how long it takes to do it.
  ///
  /// **The picker takes time on purpose.** In the real app the native dialog
  /// sits there for as long as the user browses, and nothing is happening yet
  /// — a spinner during THAT would be a lie about work that has not started.
  /// A picker that returned instantly could not tell the two waits apart.
  const pickerTakes = Duration(seconds: 2);

  String mockPicker() {
    final dir = Directory.systemTemp.createTempSync('onote_picked_');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    const channel = MethodChannel('plugins.flutter.io/file_selector');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      await Future<void>.delayed(pickerTakes);
      return call.method == 'getDirectoryPath' ? dir.path : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    return dir.path;
  }

  Future<void> openDialog(WidgetTester tester, AppState app) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSyncDialog(context, app),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    // The debounced workspace write (400ms) is drained too, so the dialog is
    // not opened on top of a pending timer.
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
  }

  /// Press "Choose a folder…", wait out the picker, and stop with the move in
  /// flight. Returns the button's rect and the dialog's rect as they were
  /// BEFORE the press.
  Future<(Rect, Rect)> startMove(WidgetTester tester, _GatedApp app) async {
    expect(spinner, findsNothing,
        reason: 'nothing has been asked for yet, so nothing may be turning');
    expect(chooser, findsOneWidget);
    expect(find.descendant(of: chooser, matching: find.text('Choose a folder…')),
        findsOneWidget,
        reason: 'the finder is pointed at the right button');

    final button = tester.getRect(chooser);
    final dialog = tester.getRect(find.byType(AlertDialog));

    await tester.tap(chooser);
    // Mid-picker: the OS dialog is up and Openote is not doing anything.
    await tester.pump(pickerTakes ~/ 2);
    expect(spinner, findsNothing,
        reason: 'the picker is still open — no work has started to report');
    expect(app.gate, isNull);

    // Past it. One pump to deliver the picker's reply, one to rebuild.
    await tester.pump(pickerTakes);
    await tester.pump();
    expect(app.gate, isNotNull, reason: 'the move should have started');
    // No `pumpAndSettle` from here on: a CircularProgressIndicator never
    // settles, so it would pump until the timeout instead of failing.
    return (button, dialog);
  }

  testWidgets('choosing a cloud folder turns a spinner where the label was, '
      'and moves nothing', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    mockPicker();
    await openDialog(tester, app);

    final (button, dialog) = await startMove(tester, app);

    expect(find.descendant(of: chooser, matching: spinner), findsOneWidget,
        reason: 'the wait belongs on the button that started it');
    expect(spinner, findsOneWidget,
        reason: 'and nowhere else in the dialog');
    expect(tester.widget<OutlinedButton>(chooser).onPressed, isNull,
        reason: 'pressing it again mid-move must still do nothing');

    // THE ONE THAT IS MEASURED, NOT EYEBALLED: nothing moves. Rect equality,
    // to the pixel, across the frame the spinner arrived on.
    expect(tester.getRect(chooser), button,
        reason: 'the button changed size or position under the pointer');
    expect(tester.getRect(find.byType(AlertDialog)), dialog,
        reason: 'the dialog reflowed around the spinner');
    // And the mechanism that makes that true: the label is still in the tree,
    // measuring, just not painting.
    expect(find.descendant(of: chooser, matching: find.text('Choose a folder…')),
        findsOneWidget,
        reason: 'the label is what holds the button open');

    app.gate!.complete(r'C:\Cloud\Openote\Progress.onotebook');
    await tester.pump();
    expect(spinner, findsNothing, reason: 'the work is done');

    // Drain the "moved to…" snack bar (7s) and the workspace write behind it.
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
  });

  testWidgets('a move that fails takes the spinner away and says why',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final app = await newApp(tester);
    mockPicker();
    await openDialog(tester, app);

    final (button, _) = await startMove(tester, app);
    expect(spinner, findsOneWidget, reason: 'the move is running');

    app.gate!.completeError(
        const FileSystemException('the drive is full', 'D:/Cloud'));
    await tester.pump();

    expect(spinner, findsNothing,
        reason: 'a spinner beside a failure says it is still trying');
    expect(find.textContaining('the drive is full'), findsOneWidget,
        reason: 'the reason it failed has to be on screen');
    expect(tester.getRect(chooser), button,
        reason: 'the button is its old self again, in its old place');

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  });
}
