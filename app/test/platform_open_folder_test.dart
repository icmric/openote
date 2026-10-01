// Opening a FOLDER, which is not the same call as opening a file.
//
// Reported: *"the open folder button doesnt work at all, ill press it and
// nothing happens"*. `PlatformOpen.file` guards with
// `File(path).existsSync()`, and that is **false for a directory** — so both
// of the sync dialog's folder buttons handed it a directory, got `false`, and
// did nothing. Silently, because neither looked at the result.
//
// These tests assert the guard, not the hand-off: actually launching a file
// manager is the OS's job and not something a test should do. What can be
// pinned is which paths each call is willing to open, which is the whole of
// the bug.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/core/platform_open.dart';

void main() {
  late Directory tmp;

  late List<String> handedOff;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('onote_openfolder_');
    // Nothing is actually launched: proving the positive case for real would
    // open Explorer here and run `xdg-open` against a temp directory on CI.
    handedOff = [];
    PlatformOpen.debugHandOff = (target) async {
      handedOff.add(target);
      return true;
    };
  });
  tearDown(() {
    PlatformOpen.debugHandOff = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('file() refuses a directory — which is why the button did nothing',
      () async {
    // Not a quirk to work around: this is the contract `file()` should have.
    // Its other callers open an attachment or a video, where a directory is
    // the wrong thing and refusing is correct. The fix was a second call, not
    // a looser guard here.
    expect(await PlatformOpen.file(tmp.path), isFalse);
    expect(handedOff, isEmpty, reason: 'it never reached the platform');
  });

  test('folder() opens a directory that exists', () async {
    expect(await PlatformOpen.folder(tmp.path), isTrue);
    expect(handedOff, [tmp.path],
        reason: 'the whole bug was this path never being handed over');
  });

  test('folder() refuses a path that is not there', () async {
    expect(await PlatformOpen.folder('${tmp.path}${Platform.pathSeparator}nope'),
        isFalse);
    expect(handedOff, isEmpty);
  });

  test('folder() refuses a FILE', () async {
    // The mirror image of the first test, and it matters: a caller that means
    // "show me this in the file manager" passing a file would otherwise launch
    // whatever application owns it.
    final f = File('${tmp.path}${Platform.pathSeparator}notes.txt')
      ..writeAsStringSync('x');
    expect(await PlatformOpen.folder(f.path), isFalse);
    expect(handedOff, isEmpty);
  });
}
