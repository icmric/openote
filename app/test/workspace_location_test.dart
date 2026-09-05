// Where the workspace lives, and what happens when it cannot be written to.
//
// The bug these pin, in one line from Windows Defender's own log:
//
//     Event 1123: openote.exe has been blocked from modifying
//     %userprofile%\Documents\Openote\ by Controlled Folder Access
//
// Controlled Folder Access guards Documents. It refused every write Openote
// made there, and because the old resolver only fell back when creating the
// directory THREW — and creating one that already exists succeeds whether it
// is guarded or not — the fallback could never fire. The app came up saying it
// could not read the notebook, which named neither the cause nor the folder.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/store/repository.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('onote-ws-');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {
      // The temp folder is the OS's problem after this.
    }
  });

  group('workspaceWriteProblem', () {
    test('says nothing about a folder it can write to', () {
      expect(Repository.workspaceWriteProblem(tmp), isNull);
    });

    test('leaves no probe file behind', () {
      Repository.workspaceWriteProblem(tmp);
      expect(tmp.listSync(), isEmpty,
          reason: 'the writability probe must clean up after itself');
    });

    test('a missing folder is reported plainly, not blamed on Defender', () {
      // Worth pinning because the first draft of this test assumed a missing
      // path would exercise the denied branch. It does not: Windows returns
      // errno 3 (path not found), not 5 (access denied), so the Defender
      // sentence would have been a lie for the commonest failure of all.
      final gone = Directory(p.join(tmp.path, 'Documents', 'Openote'));
      final msg = Repository.workspaceWriteProblem(gone);
      expect(msg, isNotNull);
      expect(msg, isNot(contains('Controlled folder access')));
    });
  });

  group('writeProblemSentence', () {
    // Controlled Folder Access cannot be reproduced in a test — it needs the
    // antivirus product and an administrator — so the decision it drives is
    // separated from the write and checked directly. The sentence is the part
    // that was wrong before: a student used to get a SQLite stack trace.
    final guarded = p.join('C:', 'Users', 'sam', 'Documents', 'Openote');
    final appData =
        p.join('C:', 'Users', 'sam', 'AppData', 'Local', 'Openote');

    test('a denied write into Documents names the feature doing it', () {
      final msg = Repository.writeProblemSentence(
          path: guarded, errorCode: 5, detail: 'Access is denied');
      expect(msg, contains('Controlled folder access'));
      expect(msg, contains('Windows Defender'));
    }, skip: !Platform.isWindows ? 'Windows-only wording' : null);

    test('a denied write somewhere unguarded does not blame Defender', () {
      final msg = Repository.writeProblemSentence(
          path: appData, errorCode: 5, detail: 'Access is denied');
      expect(msg, 'Openote is not allowed to save into this folder.');
    });

    test('a non-permission failure keeps the real reason', () {
      final msg = Repository.writeProblemSentence(
          path: guarded, errorCode: 112, detail: 'There is not enough space');
      expect(msg, contains('not enough space'));
      expect(msg, isNot(contains('Controlled folder access')));
    });

    test('the guarded list is the folders Defender actually protects', () {
      for (final name in const [
        'Documents',
        'Desktop',
        'Pictures',
        'Videos',
        'Music'
      ]) {
        expect(
            Repository.isGuardedFolderPath(
                p.join('C:', 'Users', 'sam', name, 'Openote')),
            isTrue,
            reason: '$name is on the default protected list');
      }
      expect(Repository.isGuardedFolderPath(appData), isFalse);
    }, skip: !Platform.isWindows ? 'path separators are Windows-only here' : null);
  });

  group('copyWorkspaceTo', () {
    test('copies every file and leaves the original in place', () async {
      final from = Directory(p.join(tmp.path, 'from'))..createSync();
      File(p.join(from.path, 'workspace.json')).writeAsStringSync('{"v":1}');
      Directory(p.join(from.path, 'Physics.onotebook', 'ops'))
          .createSync(recursive: true);
      File(p.join(from.path, 'Physics.onotebook', 'ops', 'a.oplog'))
          .writeAsStringSync('{"seq":1}\n');

      final to = Directory(p.join(tmp.path, 'to'));
      await Repository.copyWorkspaceTo(from, to);

      expect(File(p.join(to.path, 'workspace.json')).readAsStringSync(),
          '{"v":1}');
      expect(
          File(p.join(to.path, 'Physics.onotebook', 'ops', 'a.oplog'))
              .readAsStringSync(),
          '{"seq":1}\n');
      // The half that matters most: a guarded folder refuses deletion anyway,
      // and leaving the originals is what makes this safe to offer at all.
      expect(File(p.join(from.path, 'workspace.json')).existsSync(), isTrue);
    });

    test('refuses to write over a workspace that is already there', () async {
      final from = Directory(p.join(tmp.path, 'from'))..createSync();
      File(p.join(from.path, 'workspace.json')).writeAsStringSync('{"v":1}');
      final to = Directory(p.join(tmp.path, 'to'))..createSync();
      File(p.join(to.path, 'workspace.json')).writeAsStringSync('{"v":2}');

      await expectLater(
          Repository.copyWorkspaceTo(from, to), throwsA(isA<StateError>()));
      // Untouched, not merged: two workspaces meeting is a case for a human.
      expect(File(p.join(to.path, 'workspace.json')).readAsStringSync(),
          '{"v":2}');
    });

    test('copying a workspace onto itself is a no-op, not a wipe', () async {
      final dir = Directory(p.join(tmp.path, 'same'))..createSync();
      File(p.join(dir.path, 'workspace.json')).writeAsStringSync('{"v":1}');
      await Repository.copyWorkspaceTo(dir, dir);
      expect(File(p.join(dir.path, 'workspace.json')).readAsStringSync(),
          '{"v":1}');
    });
  });
}
