// Syncing a notebook through a git remote.
//
// The ask: "For those more techincal, maybe we add git/github integration?
// Would need to all be automated by default as most people wont remeber to
// save and push changes."
//
// These run against REAL git — a bare repository in a temp directory standing
// in for GitHub — because the interesting claims are all about what git
// actually does. A mock would let me assert my own assumptions back at myself,
// and the whole reason this design works is a property of git's behaviour:
// two devices write DIFFERENT files (one op log each, content-addressed
// blobs), so a merge has nothing to resolve. That is either true or it is not,
// and only real git can say.
//
// Every test skips when git is not installed. A machine without it is not a
// failing machine; it is one where the feature is not offered.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/sync/git_sync.dart';

void main() {
  late Directory root;
  var haveGit = false;

  setUpAll(() async => haveGit = await GitSync.gitExecutable() != null);

  setUp(() {
    root = Directory.systemTemp.createTempSync('onote_git_');
  });

  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {
      // Windows keeps git's pack files locked for a moment after a push.
    }
  });

  /// A bare repository standing in for the remote.
  Future<String> remote() async {
    final dir = Directory('${root.path}/remote.git')..createSync();
    final git = (await GitSync.gitExecutable())!;
    await Process.run(git, ['init', '--bare', '--initial-branch=main'],
        workingDirectory: dir.path);
    return dir.path;
  }

  /// A device: its own `.onotebook` directory, with an identity set so commits
  /// are possible on a machine with no global git config (CI is one).
  Future<GitSync> device(String name) async {
    final dir = Directory('${root.path}/$name.onotebook')
      ..createSync(recursive: true);
    final g = GitSync(dir.path);
    await g.init();
    final git = (await GitSync.gitExecutable())!;
    await Process.run(git, ['config', 'user.email', 'test@openote.invalid'],
        workingDirectory: dir.path);
    await Process.run(git, ['config', 'user.name', 'Openote Test'],
        workingDirectory: dir.path);
    return g;
  }

  void write(GitSync g, String rel, String body) =>
      File('${g.dir}/$rel')
        ..createSync(recursive: true)
        ..writeAsStringSync(body);

  group('setting one up', () {
    test('init makes a repository and writes the ignore rules', () async {
      if (!haveGit) return markTestSkipped('git not installed');
      final g = await device('a');
      expect(g.isRepo, isTrue);
      final ignore = File('${g.dir}/.gitignore').readAsStringSync();
      expect(ignore, contains('*.onote'));
    });

    test('init is safe to run again', () async {
      if (!haveGit) return markTestSkipped('git not installed');
      final g = await device('a');
      write(g, 'ops/a.oplog', 'one');
      await g.commitAll('first');
      expect((await g.init()).ok, isTrue);
      expect(File('${g.dir}/ops/a.oplog').existsSync(), isTrue);
    });

    test('THE CONTAINER IS NEVER COMMITTED', () async {
      // ADR-0006 §3: the `.onote` is a local WAL cache. In git it would be a
      // large opaque binary in every commit, and two machines pulling each
      // other's copy is the corruption the op logs exist to prevent.
      if (!haveGit) return markTestSkipped('git not installed');
      final g = await device('a');
      write(g, 'ops/a.oplog', 'real data');
      write(g, 'Notes.onote', 'PRETEND SQLITE');
      write(g, 'Notes.onote-wal', 'wal');
      await g.commitAll('first');

      final git = (await GitSync.gitExecutable())!;
      final tracked = await Process.run(git, ['ls-files'], workingDirectory: g.dir);
      final files = '${tracked.stdout}';
      expect(files, contains('ops/a.oplog'));
      expect(files, isNot(contains('.onote')));
    });
  });

  group('committing', () {
    test('a commit with nothing to commit is a no-op, not a failure', () async {
      // This runs on a timer. If an idle notebook reported an error every
      // cycle, the status would be permanently red and nobody would read it.
      if (!haveGit) return markTestSkipped('git not installed');
      final g = await device('a');
      write(g, 'ops/a.oplog', 'one');
      expect((await g.commitAll('first')).ok, isTrue);

      final again = await g.commitAll('nothing changed');
      expect(again.ok, isTrue);
      expect(again.noop, isTrue);
    });
  });

  group('two devices', () {
    test('both devices\' logs survive, with no conflict to resolve', () async {
      // The claim the whole design rests on. Append-only, one file per device,
      // so device B never touches device A's log — git has nothing to merge.
      if (!haveGit) return markTestSkipped('git not installed');
      final url = await remote();

      final a = await device('a');
      await a.setRemote(url);
      write(a, 'ops/device-a.oplog', 'A wrote this');
      final first = await a.syncOnce(message: 'a');
      expect(first.ok, isTrue, reason: 'A first push: ${first.message}');

      final b = await device('b');
      await b.setRemote(url);
      // B starts empty and pulls A's work.
      final bFirst = await b.syncOnce(message: 'b first');
      expect(bFirst.ok, isTrue, reason: 'B join: ${bFirst.message}');
      expect(File('${b.dir}/ops/device-a.oplog').existsSync(), isTrue,
          reason: "B has A's log");

      // Now both write, without either having seen the other's new work.
      write(a, 'ops/device-a.oplog', 'A wrote this, and more');
      write(b, 'ops/device-b.oplog', 'B wrote this');
      expect((await b.syncOnce(message: 'b')).ok, isTrue);
      final aResult = await a.syncOnce(message: 'a again');
      expect(aResult.ok, isTrue, reason: aResult.message);

      // A pulled B's file and merged without a conflict; both logs are there.
      expect(File('${a.dir}/ops/device-b.oplog').readAsStringSync(),
          'B wrote this');
      expect(File('${a.dir}/ops/device-a.oplog').readAsStringSync(),
          'A wrote this, and more');
    });

    test('a blob only needs to be sent once', () async {
      // Blobs are content-addressed, so the same picture from two devices is
      // the same path with the same bytes — git deduplicates it for free.
      if (!haveGit) return markTestSkipped('git not installed');
      final url = await remote();
      final a = await device('a');
      await a.setRemote(url);
      write(a, 'blobs/abc123', 'PICTURE BYTES');
      await a.syncOnce(message: 'a');

      final b = await device('b');
      await b.setRemote(url);
      await b.syncOnce(message: 'b');
      write(b, 'blobs/abc123', 'PICTURE BYTES');
      final r = await b.commitAll('same picture');
      expect(r.noop, isTrue,
          reason: 'identical content is not a change to commit');
    });
  });

  group('failing honestly', () {
    test('a bad remote reports the failure rather than claiming success',
        () async {
      // A push that silently did not happen is worse than one that says so:
      // the user believes their notes are somewhere they are not.
      if (!haveGit) return markTestSkipped('git not installed');
      final g = await device('a');
      await g.setRemote('${root.path}/definitely-not-a-repo');
      write(g, 'ops/a.oplog', 'one');
      final r = await g.syncOnce(message: 'x');
      expect(r.ok, isFalse);
      expect(r.message, isNotEmpty);
    });

    test('with no remote it still commits locally', () async {
      // Version history on this machine is worth having on its own, and it is
      // what makes adding a remote later a push rather than a fresh start.
      if (!haveGit) return markTestSkipped('git not installed');
      final g = await device('a');
      write(g, 'ops/a.oplog', 'one');
      final r = await g.syncOnce(message: 'local only');
      expect(r.ok, isTrue, reason: r.message);
      expect(await g.remoteUrl(), isNull);
    });

    test('syncing a directory that is not a repository is refused', () async {
      if (!haveGit) return markTestSkipped('git not installed');
      final plain = Directory('${root.path}/plain')..createSync();
      final r = await GitSync(plain.path).syncOnce(message: 'x');
      expect(r.ok, isFalse);
    });

    test('no git installed is reported, not thrown', () async {
      // The whole feature is optional. A machine without git must degrade to
      // "not offered", never to a crash.
      final saved = await GitSync.gitExecutable();
      GitSync.debugSetGit(null);
      addTearDown(() => GitSync.debugSetGit(saved));
      final r = await GitSync('${root.path}/anywhere').syncOnce(message: 'x');
      expect(r.ok, isFalse);
      expect(r.message, isNotEmpty);
    });
  });

  group('joining a notebook someone shared', () {
    test('clone brings the logs down', () async {
      if (!haveGit) return markTestSkipped('git not installed');
      final url = await remote();
      final a = await device('a');
      await a.setRemote(url);
      write(a, 'ops/device-a.oplog', 'shared notes');
      await a.syncOnce(message: 'a');

      final into = '${root.path}/Joined.onotebook';
      final r = await GitSync.clone(url, into);
      expect(r.ok, isTrue, reason: r.message);
      expect(File('$into/ops/device-a.oplog').readAsStringSync(),
          'shared notes');
    });

    test('cloning onto something that already exists is refused', () async {
      if (!haveGit) return markTestSkipped('git not installed');
      final occupied = Directory('${root.path}/taken')..createSync();
      File('${occupied.path}/mine.txt').writeAsStringSync('do not clobber me');
      final r = await GitSync.clone(await remote(), occupied.path);
      expect(r.ok, isFalse);
      expect(File('${occupied.path}/mine.txt').existsSync(), isTrue);
    });
  });
}
