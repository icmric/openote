// A generous per-test timeout, because these spawn REAL git.
//
// The `test` package's default is 30 seconds, which was never a decision
// about these — it is the framework's number for an ordinary unit test. One
// case here runs `git init`, three `git config`s, a clone, a commit and a
// push, each its own process: 20 s for this file on an idle sixteen-core
// machine, and the ceiling is per test rather than per file. On a two-core CI
// runner that is a coin flip, and it landed exactly as you would expect —
// intermittently, on Windows, one test at a time, with an error
// ("TimeoutException after 0:00:30") that says nothing about git.
//
// Three minutes is not a performance bar; it is a hang guard. A remote that
// wants a password already fails fast (GIT_TERMINAL_PROMPT=0), so anything
// still running at three minutes is genuinely stuck.
@Timeout(Duration(minutes: 3))
library;

// Joining a notebook from a git URL — the other end of publishing one.
//
// "Seems like the push side of things works. Work on pulling from it now."
//
// These run against REAL git, with a bare repository in a temp directory
// standing in for GitHub, and they go all the way through: device A creates a
// notebook and pushes it, device B joins from the URL and must end up with
// A's pages, tree and pictures. A mock would prove nothing here — the claim is
// that a clone plus one pull reconstructs a notebook from its logs, and only
// the real machinery can say.
//
// Device B is a SEPARATE workspace (its own Repository over its own temp
// directory), because that is what a second machine is. Sharing one repository
// would let the test pass on state that only exists because device A put it
// there.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/git_sync.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  var haveGit = false;

  setUpAll(() async {
    haveSqlite = initSqliteForTests();
    haveGit = await GitSync.gitExecutable() != null;
  });

  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('onote_join_'));
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {
      // Windows holds git's pack files open for a moment after a push.
    }
  });

  bool skip() => !haveSqlite || !haveGit;

  /// A bare repository standing in for GitHub.
  Future<String> remote() async {
    final dir = Directory('${root.path}/remote.git')..createSync();
    final git = (await GitSync.gitExecutable())!;
    await Process.run(git, ['init', '--bare', '--initial-branch=main'],
        workingDirectory: dir.path);
    return dir.path;
  }

  /// Publish a device's open notebook to [url].
  ///
  /// Deliberately NO `git config user.name/email` here. This helper used to
  /// inject an identity "because a machine with no global git config cannot
  /// commit — CI is one, and so is a fresh container" — which was the product
  /// bug itself, papered over where only the tests could benefit: on a
  /// student's fresh Linux install, "create and push" made the repository
  /// over the API and then every commit died on "Author identity unknown",
  /// so nothing ever synced. GitSync now carries its own identity in the
  /// environment, and running these tests WITHOUT the workaround is what
  /// proves it — CI has no global git config, exactly like that laptop.
  Future<void> publish(AppState app, String url) async {
    final dir = app.currentNotebook.logDirPath;
    Directory(dir).createSync(recursive: true);
    final git = (await GitSync.gitExecutable())!;
    await Process.run(git, ['init', '--initial-branch=main'],
        workingDirectory: dir);
    await app.setGitEnabled(true, remote: url);
  }

  /// A workspace: its own Repository, its own AppState. This is a device.
  Future<(Repository, AppState, Directory)> device(String name) async {
    final dir = Directory('${root.path}/$name')..createSync(recursive: true);
    final repo = await Repository.openAt(dir);
    final app = AppState(repo)..spellCheckEnabled = false;
    return (repo, app, dir);
  }

  test('a second machine joins from the URL and has the notes', () async {
    if (skip()) return markTestSkipped('sqlite or git unavailable');
    final url = await remote();

    // ── Device A: write a notebook and publish it.
    final (repoA, appA, _) = await device('A');
    addTearDown(() {
      appA.cancelPendingSave();
      repoA.dispose();
    });

    final nb = await repoA.createNotebook('Physics');
    appA.notebookId = nb.id;
    appA.reloadNodes();
    final pageId = appA.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
    appA.pageId = pageId;
    appA.renameNode(pageId, 'Waves');
    appA.blocks = [
      Block(
          id: 'a-1',
          type: BlockType.text,
          x: 0,
          y: 0,
          content: {'text': 'v = f lambda'})
    ];
    appA.markDirty();
    await appA.flushSave();

    await publish(appA, url);
    expect(appA.gitStatus, isNot(startsWith('Could not')),
        reason: 'A must publish before B can join: ${appA.gitStatus}');

    // ── Device B: a different machine, a different workspace, one URL.
    final (repoB, appB, _) = await device('B');
    addTearDown(() {
      appB.cancelPendingSave();
      repoB.dispose();
    });
    expect(repoB.notebooks, isEmpty, reason: 'B starts with nothing');

    final problem = await appB.joinNotebookFromGit(url);
    expect(problem, isNull, reason: 'join failed: $problem');

    // The notebook is registered, named from the manifest rather than the URL.
    expect(repoB.notebooks, hasLength(1));
    expect(repoB.notebooks.single.title, 'Physics',
        reason: "the manifest's name beats the repository's");
    expect(appB.notebookId, repoB.notebooks.single.id,
        reason: 'and it is the one now open');

    // The tree came through. This is the assertion the FK ordering exists for:
    // B's container was created EMPTY, so every node and every page is written
    // by that first pull, and pages before nodes would have rolled the whole
    // thing back.
    final page = appB.nodes.firstWhere((n) => n.kind == NodeKind.page);
    expect(page.title, 'Waves');
    expect(appB.nodes.where((n) => n.kind == NodeKind.section), isNotEmpty);

    // And the content, out of the container rather than out of memory.
    final stored = repoB.readPage(appB.notebookId!, page.id);
    expect(stored.blocks.map((b) => b.content['text']), contains('v = f lambda'));

    // Git is already set up, so B keeps in step without being told to.
    expect(appB.gitEnabled, isTrue);
    expect(appB.gitRemote, url);
  });

  test('a picture survives the trip', () async {
    // The half that used to go missing: op logs referenced blobs whose BYTES
    // had never been copied out of the container, because git did not count as
    // "shared". Text arrived and every image did not.
    if (skip()) return markTestSkipped('sqlite or git unavailable');
    final url = await remote();
    final (repoA, appA, _) = await device('A');
    addTearDown(() {
      appA.cancelPendingSave();
      repoA.dispose();
    });

    final nb = await repoA.createNotebook('Art');
    appA.notebookId = nb.id;
    appA.reloadNodes();
    final pageId = appA.nodes.firstWhere((n) => n.kind == NodeKind.page).id;
    appA.pageId = pageId;

    // A tiny PNG-shaped blob. The bytes need not decode — what is under test
    // is whether they reach the other machine at all.
    final bytes = Uint8List.fromList(List<int>.generate(64, (i) => (i * 7) % 251));
    final hash = repoA.putBlob(nb.id, bytes, 'image/png');
    appA.blocks = [
      Block(
          id: 'img-1',
          type: BlockType.image,
          x: 0,
          y: 0,
          content: {'hash': hash, 'mime': 'image/png'})
    ];
    appA.markDirty();
    await appA.flushSave();

    await publish(appA, url);
    // The bytes must be in the repository, not only in A's container.
    final blobsDir = Directory('${appA.currentNotebook.logDirPath}/blobs');
    expect(blobsDir.existsSync(), isTrue,
        reason: 'a git remote makes a notebook shared');
    expect(blobsDir.listSync(), isNotEmpty,
        reason: 'the blob bytes were materialised before the push');

    final (repoB, appB, _) = await device('B');
    addTearDown(() {
      appB.cancelPendingSave();
      repoB.dispose();
    });
    expect(await appB.joinNotebookFromGit(url), isNull);

    final page = appB.nodes.firstWhere((n) => n.kind == NodeKind.page);
    final stored = repoB.readPage(appB.notebookId!, page.id);
    final img = stored.blocks.firstWhere((b) => b.type == BlockType.image);
    final got = repoB.getBlob(appB.notebookId!, img.content['hash'] as String);
    expect(got, isNotNull, reason: 'the picture must exist on B, not just its id');
    expect(got, equals(bytes));
  });

  group('refusing sensibly', () {
    test('an empty address is caught before anything happens', () async {
      if (skip()) return markTestSkipped('sqlite or git unavailable');
      final (repo, app, _) = await device('E');
      addTearDown(() {
        app.cancelPendingSave();
        repo.dispose();
      });
      expect(await app.joinNotebookFromGit('   '), contains('Paste'));
      expect(repo.notebooks, isEmpty);
    });

    test('a repository that is not a notebook says so, and leaves nothing',
        () async {
      // Somebody's code repository, pasted by mistake. It clones fine — the
      // failure is that there is no `ops/` in it — and the half-clone must not
      // be left behind as a notebook that can never work.
      if (skip()) return markTestSkipped('sqlite or git unavailable');
      final url = await remote();
      final seed = Directory('${root.path}/seed')..createSync();
      final git = (await GitSync.gitExecutable())!;
      await Process.run(git, ['init', '--initial-branch=main'],
          workingDirectory: seed.path);
      await Process.run(git, ['config', 'user.email', 'test@openote.invalid'],
          workingDirectory: seed.path);
      await Process.run(git, ['config', 'user.name', 'Openote Test'],
          workingDirectory: seed.path);
      File('${seed.path}/README.md').writeAsStringSync('not a notebook');
      await Process.run(git, ['add', '-A'], workingDirectory: seed.path);
      await Process.run(git, ['commit', '-m', 'x'], workingDirectory: seed.path);
      await Process.run(git, ['push', url, 'main'], workingDirectory: seed.path);

      final (repo, app, dir) = await device('N');
      addTearDown(() {
        app.cancelPendingSave();
        repo.dispose();
      });
      final problem = await app.joinNotebookFromGit(url);
      expect(problem, contains('ops'));
      expect(repo.notebooks, isEmpty, reason: 'nothing was registered');
      expect(
          dir.listSync().where((e) => e.path.endsWith('.onotebook')), isEmpty,
          reason: 'and the clone was cleaned up');
    });

    test('an address that goes nowhere reports it and cleans up', () async {
      if (skip()) return markTestSkipped('sqlite or git unavailable');
      final (repo, app, dir) = await device('X');
      addTearDown(() {
        app.cancelPendingSave();
        repo.dispose();
      });
      final problem =
          await app.joinNotebookFromGit('${root.path}/definitely-not-there');
      expect(problem, isNotNull);
      expect(repo.notebooks, isEmpty);
      expect(dir.listSync().where((e) => e.path.endsWith('.onotebook')), isEmpty);
    });

    test('joining the same notebook twice opens it instead of cloning again',
        () async {
      // A second ~100 MB copy of one notebook, each with its own review
      // history and favourites, is the failure the folder-join dedupe already
      // exists to prevent. The URL route needs its own.
      if (skip()) return markTestSkipped('sqlite or git unavailable');
      final url = await remote();
      final (repoA, appA, _) = await device('A');
      addTearDown(() {
        appA.cancelPendingSave();
        repoA.dispose();
      });
      final nb = await repoA.createNotebook('Twice');
      appA.notebookId = nb.id;
      appA.reloadNodes();
      await publish(appA, url);

      final (repoB, appB, _) = await device('B');
      addTearDown(() {
        appB.cancelPendingSave();
        repoB.dispose();
      });
      expect(await appB.joinNotebookFromGit(url), isNull);
      expect(repoB.notebooks, hasLength(1));

      expect(await appB.joinNotebookFromGit(url), isNull);
      expect(repoB.notebooks, hasLength(1), reason: 'still one notebook');
    });

    test('a paused notebook is still recognised by its address', () async {
      // Turning the git switch off KEEPS the remote on disk. Reading only
      // enabled notebooks would miss this one and clone a duplicate of a
      // notebook the user had merely paused.
      if (skip()) return markTestSkipped('sqlite or git unavailable');
      final url = await remote();
      final (repoA, appA, _) = await device('A');
      addTearDown(() {
        appA.cancelPendingSave();
        repoA.dispose();
      });
      final nb = await repoA.createNotebook('Paused');
      appA.notebookId = nb.id;
      appA.reloadNodes();
      await publish(appA, url);

      final (repoB, appB, _) = await device('B');
      addTearDown(() {
        appB.cancelPendingSave();
        repoB.dispose();
      });
      expect(await appB.joinNotebookFromGit(url), isNull);
      await appB.setGitEnabled(false);
      expect(appB.gitEnabled, isFalse);

      expect(await appB.joinNotebookFromGit(url), isNull);
      expect(repoB.notebooks, hasLength(1),
          reason: 'paused is not gone — it must be reopened, not re-cloned');
    });

    test('the same repository written three ways is one notebook', () async {
      // https, a trailing .git, and a differently-cased path all name the same
      // place. Matching them literally would clone three copies.
      if (skip()) return markTestSkipped('sqlite or git unavailable');
      final (repo, app, _) = await device('U');
      addTearDown(() {
        app.cancelPendingSave();
        repo.dispose();
      });
      // Exercised through the public surface that uses the same comparison.
      const a = 'https://github.com/You/Notes.git';
      const b = 'https://github.com/you/notes';
      const c = 'git@github.com:you/notes.git';
      expect(const SyncStatus(folder: null, devices: 1, mirrors: 0, gitRemote: a)
              .gitLabel,
          'github.com/You/Notes');
      expect(const SyncStatus(folder: null, devices: 1, mirrors: 0, gitRemote: c)
              .gitLabel,
          'github.com/you/notes');
      expect(const SyncStatus(folder: null, devices: 1, mirrors: 0, gitRemote: b)
              .gitLabel,
          'github.com/you/notes');
    });
  });
}
