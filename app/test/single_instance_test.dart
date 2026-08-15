// One Openote per workspace, and the hand-off that lets a second launch open a
// notebook in the one already running (backlog: "Open a notebook passed on the
// command line", second-instance behaviour).
//
// The decision under test: a `.onote` double-clicked while Openote is running
// must NOT start a second process. Two processes share `workspace.json` — which
// is rewritten wholesale, so a notebook created in one vanishes when the other
// saves — and, the moment both land on one notebook, the same WAL SQLite
// container. That is the corruption ADR-0006 §3 is written against.
//
// Everything here is real files in a real temp directory. The window-raising
// half cannot be tested (it needs two Openotes on a desktop) and is passed in
// as a no-op — deliberately, because `WindowFocus.raiseSelf` finds a window by
// class and title and would otherwise un-minimise the developer's own Openote
// every time the suite ran.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/core/single_instance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory tempDir() {
    final d = Directory.systemTemp.createTempSync('onote_instance_');
    addTearDown(() {
      try {
        d.deleteSync(recursive: true);
      } catch (_) {/* Windows may still hold the lock file a moment */}
    });
    return d;
  }

  test('nothing pending means nothing to do', () {
    expect(SingleInstance.takeRequest(tempDir()), isNull);
  });

  test('a request is delivered once and then gone', () async {
    final dir = tempDir();
    // Written by the launching process; the holder consumes it.
    unawaited(SingleInstance.handOff(dir, r'C:\notes\Physics.onote',
        timeout: const Duration(seconds: 2)));
    // Give the write + rename a moment to land.
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(SingleInstance.takeRequest(dir), r'C:\notes\Physics.onote');
    expect(SingleInstance.takeRequest(dir), isNull,
        reason: 'taking it is what acknowledges it');
    expect(SingleInstance.requestFile(dir).existsSync(), isFalse);
  });

  test('an empty path is a request to come forward, not nothing', () async {
    final dir = tempDir();
    unawaited(SingleInstance.handOff(dir, null,
        timeout: const Duration(seconds: 2)));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    // '' and null mean different things: '' is "you were launched with no
    // notebook, just show yourself", null is "there was no request".
    expect(SingleInstance.takeRequest(dir), '');
  });

  // The safety valve. A lock holder that is wedged, or a lock the OS somehow
  // did not release, must never make Openote unlaunchable — the sender gives
  // up and starts its own instance, which is exactly the behaviour that
  // existed before any of this.
  test('an unanswered hand-off gives up, and takes its request back', () async {
    final dir = tempDir();
    final answered = await SingleInstance.handOff(dir, '/tmp/Physics.onote',
        timeout: const Duration(milliseconds: 250));

    expect(answered, isFalse);
    expect(SingleInstance.requestFile(dir).existsSync(), isFalse,
        reason: 'a stale request must not be acted on by a later Openote');
  });

  test('a request older than its shelf life is dropped, not obeyed', () {
    final dir = tempDir();
    SingleInstance.requestFile(dir).writeAsStringSync(jsonEncode({
      'path': '/tmp/Ancient.onote',
      'at': DateTime.now()
          .subtract(const Duration(hours: 3))
          .millisecondsSinceEpoch,
    }));

    expect(SingleInstance.takeRequest(dir), isNull);
    expect(SingleInstance.requestFile(dir).existsSync(), isFalse,
        reason: 'consumed either way, so it cannot be found again tomorrow');
  });

  test('the first instance takes the lock, and gives it back on the way out',
      () async {
    final dir = tempDir();
    final first = await SingleInstance.claim(dir);
    expect(first, isNotNull);
    expect(first!.holdsLock, isTrue);
    await first.dispose();

    final second = await SingleInstance.claim(dir);
    expect(second, isNotNull);
    expect(second!.holdsLock, isTrue,
        reason: 'a closed Openote must not keep the workspace to itself');
    await second.dispose();
  });

  test('a running instance answers a hand-off and is told which notebook',
      () async {
    final dir = tempDir();
    final running = await SingleInstance.claim(dir);
    addTearDown(() => running!.dispose());
    final opened = <String>[];
    // `raise: () => false` — see the file header.
    running!.listen(opened.add, raise: () => false);

    final answered = await SingleInstance.handOff(dir, '/tmp/Physics.onote');

    expect(answered, isTrue, reason: 'the sender may now exit');
    // The callback fires on the same poll tick that acknowledged.
    await Future<void>.delayed(SingleInstance.pollInterval);
    expect(opened, ['/tmp/Physics.onote']);
  });

  // The whole flow, through the entry point `main()` actually calls. Windows
  // only, and not a portability gap in the app: Windows file locks are held
  // per HANDLE, so a second `claim` in this one process is refused exactly as a
  // second process would be. POSIX locks are per PROCESS, so the same test
  // would hand the lock straight back to itself and prove nothing. The
  // behaviour under test is the same on both; only this way of provoking it is
  // Windows-specific.
  test('a second launch hands over and exits instead of starting', () async {
    if (!Platform.isWindows) {
      markTestSkipped('same-process lock contention is a Windows behaviour');
      return;
    }
    final dir = tempDir();
    final running = await SingleInstance.claim(dir);
    addTearDown(() => running!.dispose());
    final opened = <String>[];
    running!.listen(opened.add, raise: () => false);

    final second =
        await SingleInstance.claim(dir, openPath: r'C:\notes\Physics.onote');

    expect(second, isNull,
        reason: 'null is main() being told to exit without painting a window');
    await Future<void>.delayed(SingleInstance.pollInterval);
    expect(opened, [r'C:\notes\Physics.onote']);
  });
}
