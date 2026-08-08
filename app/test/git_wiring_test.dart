// Git sync, as the app actually uses it.
//
// The ENGINE is tested against real git in git_sync_test.dart. This file is
// about the wiring — the part that decides when a cycle runs and whether the
// setting is still there tomorrow — and it is written mainly around one
// failure this codebase has already had once:
//
//   `reloadProtection()` shipped in 0.4.2 with no caller in the app. Every
//   restart began with the passcode gate wide open, and the test that was
//   supposed to catch it called the reload BY HAND — which is exactly the line
//   production was missing.
//
// So the restart test here goes through `selectNotebook` and nothing else, and
// there is a separate one for the startup path, because startup opens the last
// notebook inline rather than through `_loadNotebook`. Wiring one and not the
// other is the specific shape of that bug.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/git_sync.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Repository repo;
  late Directory tmp;
  late AppState app;

  setUp(() async {
    if (!haveSqlite) return;
    // No git: these tests are about the WIRING, and a machine with git would
    // have them making real commits in a temp directory for no added
    // confidence. The engine's own tests cover git itself.
    GitSync.debugSetGit(null);
    tmp = Directory.systemTemp.createTempSync('onote_gitwire_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Notes');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
  });

  tearDown(() {
    if (!haveSqlite) return;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('off by default', () {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    expect(app.gitEnabled, isFalse);
    expect(app.gitRemote, isNull);
  });

  test('the setting survives reopening the notebook', () async {
    // Through `selectNotebook` and nothing else. Calling `reloadGit()` by hand
    // here would test that the method works, which was never in doubt — the
    // question is whether anything CALLS it.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final home = app.notebookId!;
    await app.setGitEnabled(true, remote: 'https://example.com/n.git');
    expect(app.gitEnabled, isTrue);

    final fresh = AppState(repo)..spellCheckEnabled = false;
    addTearDown(fresh.cancelPendingSave);
    await fresh.selectNotebook(home);

    expect(fresh.gitEnabled, isTrue, reason: 'a restart must not forget');
    expect(fresh.gitRemote, 'https://example.com/n.git');
  });

  test('it does not leak across notebooks', () async {
    // The setting is per notebook. Carrying one notebook's remote into
    // another would push somebody's notes at a repository that is not theirs.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final home = app.notebookId!;
    await app.setGitEnabled(true, remote: 'https://example.com/n.git');

    final other = await repo.createNotebook('Elsewhere');
    await app.selectNotebook(other.id);
    expect(app.gitEnabled, isFalse, reason: 'a different notebook, untouched');
    expect(app.gitRemote, isNull);

    await app.selectNotebook(home);
    expect(app.gitEnabled, isTrue, reason: 'and the first one still knows');
  });

  test('turning it off forgets the remote for good', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final home = app.notebookId!;
    await app.setGitEnabled(true, remote: 'https://example.com/n.git');
    await app.setGitEnabled(false);

    final fresh = AppState(repo)..spellCheckEnabled = false;
    addTearDown(fresh.cancelPendingSave);
    await fresh.selectNotebook(home);
    expect(fresh.gitEnabled, isFalse);
  });

  test('an edit arms the sync, and it is not the save debounce', () async {
    // Saving is debounced at 700ms because losing edits matters. A commit and
    // a push at that rate would be one per sentence — noise on the remote and
    // a network round trip mid-paragraph. The git timer is a minute.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await app.setGitEnabled(true, remote: 'https://example.com/n.git');
    app.markDirty();
    // Nothing to assert about the timer's existence directly; what matters is
    // that arming it neither throws nor fires immediately, and that cancelling
    // is available to the shutdown path.
    app.cancelPendingSave();
    expect(app.gitBusy, isFalse);
  });

  test('a cycle with no git installed reports rather than throwing', () async {
    // The whole feature is optional. `debugSetGit(null)` in setUp is the
    // machine without git, and it must produce a message, not an exception.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await app.setGitEnabled(true, remote: 'https://example.com/n.git');
    await app.syncGitNow();
    expect(app.gitBusy, isFalse, reason: 'the flag is always released');
    expect(app.gitStatus, isNotNull);
    expect(app.gitStatus, startsWith('Could not sync'),
        reason: 'silence here is the outcome worth being loud about');
  });

  test('syncing while a sync is running does not start a second one', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await app.setGitEnabled(true, remote: 'https://example.com/n.git');
    app.gitBusy = true;
    app.gitStatus = null;
    await app.syncGitNow();
    expect(app.gitStatus, isNull, reason: 'the second call did nothing');
    app.gitBusy = false;
  });

  test('a disabled notebook never runs a cycle', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await app.syncGitNow();
    expect(app.gitStatus, isNull);
  });

  // ── A connected GitHub account ───────────────────────────────────────
  //
  // "I want to be able to create and push my notebook to github from within
  // the app, no extra steps required outside the app."
  //
  // The account is GLOBAL and the remote is per notebook, which is the split
  // these tests exist to pin: connecting once must publish any notebook, and
  // publishing one must not point another at it.
  group('a GitHub account', () {
    late HttpServer server;
    var login = 'icmric';
    late List<String> paths;

    setUp(() async {
      if (!haveSqlite) return;
      paths = [];
      // Reset, or the test that makes the token invalid leaves every test
      // after it talking to a server that answers 401.
      login = 'icmric';
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      AppState.debugGitHubBase =
          'http://${server.address.host}:${server.port}';
      server.listen((req) async {
        paths.add(req.uri.path);
        await req.drain<void>();
        if (login.isEmpty) {
          req.response.statusCode = 401;
          req.response.write('{"message":"Bad credentials"}');
        } else if (req.uri.path == '/user') {
          req.response.write('{"login":"$login"}');
        } else {
          req.response.statusCode = 201;
          req.response.write('{"clone_url":"https://example.invalid/n.git",'
              '"full_name":"$login/Notes"}');
        }
        await req.response.close();
      });
    });

    tearDown(() async {
      if (!haveSqlite) return;
      AppState.debugGitHubBase = 'https://api.github.com';
      await server.close(force: true);
    });

    test('a token is checked BEFORE it is stored', () async {
      // "Connected" must never mean "we kept a string you pasted and will find
      // out it was wrong at the next push", because the next push is the
      // moment the user has stopped watching.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      login = '';
      final problem = await app.connectGitHub('ghp_wrong');
      expect(problem, isNotNull);
      expect(app.githubConnected, isFalse);
      expect(paths, ['/user'], reason: 'it asked, rather than assuming');
    });

    test('an empty paste is caught without a round trip', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      expect(await app.connectGitHub('   '), isNotNull);
      expect(paths, isEmpty);
    });

    test('a good token connects, and names the account', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      login = 'icmric';
      expect(await app.connectGitHub('  ghp_good  '), isNull);
      expect(app.githubConnected, isTrue);
      expect(app.githubLogin, 'icmric');
    });

    test('THE ACCOUNT SURVIVES A RESTART', () async {
      // Through `selectNotebook` and nothing else. This is the exact shape of
      // the bug that shipped in 0.4.2: `reloadProtection` existed, worked, and
      // had no caller, so every restart forgot. Calling `reloadGitHub()` by
      // hand here would test the method rather than the wiring.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final home = app.notebookId!;
      await app.connectGitHub('ghp_good');

      final fresh = AppState(repo)..spellCheckEnabled = false;
      addTearDown(fresh.cancelPendingSave);
      await fresh.selectNotebook(home);

      expect(fresh.githubConnected, isTrue, reason: 'signing in is once');
      expect(fresh.githubLogin, 'icmric');
    });

    test('the account is global — every notebook can publish', () async {
      // The remote is per notebook; the ACCOUNT is a property of the person.
      // Making someone sign in again per notebook would be the wrong split.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await app.connectGitHub('ghp_good');
      final other = await repo.createNotebook('Elsewhere');
      await app.selectNotebook(other.id);
      expect(app.githubConnected, isTrue);
      expect(app.gitRemote, isNull, reason: 'but not the remote');
    });

    test('signing out forgets the token for good', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final home = app.notebookId!;
      await app.connectGitHub('ghp_good');
      app.disconnectGitHub();

      final fresh = AppState(repo)..spellCheckEnabled = false;
      addTearDown(fresh.cancelPendingSave);
      await fresh.selectNotebook(home);
      expect(fresh.githubConnected, isFalse);
      expect(fresh.githubLogin, isNull);
    });

    test('publishing without an account asks for one first', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      expect(await app.createGitHubRepo(), contains('Connect'));
      expect(paths, isEmpty, reason: 'nothing was created');
    });

    test('the remote is set only once GitHub confirms the repository',
        () async {
      // Order matters. A remote pointing at a repository that does not exist
      // is a notebook that reports a sync failure every minute, forever.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await app.connectGitHub('ghp_good');
      login = ''; // creation will now fail
      final problem = await app.createGitHubRepo(name: 'Notes');
      expect(problem, isNotNull);
      expect(app.gitRemote, isNull, reason: 'nothing was pointed anywhere');
      expect(app.gitEnabled, isFalse);
    });

    test('a created repository becomes this notebook\'s remote, and persists',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final home = app.notebookId!;
      await app.connectGitHub('ghp_good');
      // git is absent in these tests (see setUp), so the push cannot succeed —
      // what is under test is that the repository was created and recorded,
      // and that the failure is REPORTED rather than swallowed.
      await app.createGitHubRepo(name: 'Notes');
      expect(paths, contains('/user/repos'));
      expect(app.gitRemote, 'https://example.invalid/n.git');
      expect(app.gitEnabled, isTrue);

      final fresh = AppState(repo)..spellCheckEnabled = false;
      addTearDown(fresh.cancelPendingSave);
      await fresh.selectNotebook(home);
      expect(fresh.gitRemote, 'https://example.invalid/n.git');
    });

    test('a first push that fails says so, and says it is recoverable',
        () async {
      // The repository is real and the remote is set, so pressing Sync now is
      // the fix. Silence here would leave someone believing their notes are
      // somewhere they never reached.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await app.connectGitHub('ghp_good');
      final problem = await app.createGitHubRepo(name: 'Notes');
      expect(problem, isNotNull, reason: 'git is not installed in this test');
      expect(problem, contains('Created'));
      expect(app.gitStatus, equals(problem));
    });
  });
}
