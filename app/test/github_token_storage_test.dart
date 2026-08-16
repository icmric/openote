// Where the GitHub token is allowed to live — and where it is not.
//
// Task #73: `workspace.json` used to carry the token in CLEAR TEXT. The file
// sits in the user's Documents folder, gets synced, backed up and screenshotted
// — none of which should ever include a credential that can push to (and, with
// classic scopes, read every repository of) somebody's GitHub account.
//
// The rule these tests pin:
//
//   * a freshly connected token goes into [SecretStore] (the OS password
//     store; an in-memory map here) and NEVER into workspace.json;
//   * a workspace written by an old build — token in the file — is scrubbed on
//     load: moved into the store, the file AND its .bak rewritten without it,
//     and the account still works, token and all.
//
// Both are mutation-proved: putting `'token': t` back into the setting map
// fails the first, removing the scrub call fails the second.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openote/core/secret_store.dart';
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
  late HttpServer server;

  /// Every Authorization header the fake GitHub has seen, in order.
  late List<String?> authHeaders;

  String registryText() =>
      File(p.join(tmp.path, 'workspace.json')).readAsStringSync();
  String backupText() =>
      File(p.join(tmp.path, 'workspace.json.bak')).readAsStringSync();

  setUp(() async {
    if (!haveSqlite) return;
    GitSync.debugSetGit(null); // wiring tests; git itself is tested elsewhere
    SecretStore.debugBackend = <String, String>{};
    tmp = Directory.systemTemp.createTempSync('onote_tokstore_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Notes');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();

    authHeaders = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    AppState.debugGitHubBase = 'http://${server.address.host}:${server.port}';
    server.listen((req) async {
      authHeaders.add(req.headers.value(HttpHeaders.authorizationHeader));
      await req.drain<void>();
      if (req.uri.path == '/user') {
        req.response.write('{"login":"icmric"}');
      } else {
        req.response.statusCode = 201;
        req.response.write('{"clone_url":"https://example.invalid/n.git",'
            '"full_name":"icmric/Notes"}');
      }
      await req.response.close();
    });
  });

  tearDown(() async {
    if (!haveSqlite) return;
    AppState.debugGitHubBase = 'https://api.github.com';
    await server.close(force: true);
    app.cancelPendingSave();
    repo.dispose();
    SecretStore.debugBackend = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a freshly connected token never lands in workspace.json', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    expect(await app.connectGitHub('ghp_fresh_secret_123'), isNull);
    await repo.flushWorkspace();

    final text = registryText();
    expect(text, isNot(contains('ghp_fresh_secret_123')),
        reason: 'the token must never be written to the workspace file');
    expect(text, contains('icmric'),
        reason: 'the login is a display name, not a secret — it stays');
    expect(SecretStore.debugBackend!['github'], 'ghp_fresh_secret_123',
        reason: 'the token went to the password store instead');
  });

  test('the store, not the file, is what a restart signs in from', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final home = app.notebookId!;
    await app.connectGitHub('ghp_fresh_secret_123');

    final fresh = AppState(repo)..spellCheckEnabled = false;
    addTearDown(fresh.cancelPendingSave);
    await fresh.selectNotebook(home);
    expect(fresh.githubConnected, isTrue);
    expect(fresh.githubLogin, 'icmric');
  });

  test('a login whose token has vanished from the store reads as signed out',
      () async {
    // Half a credential must not half-work: `githubConnected` false while a
    // dialog greets the user by name is the inconsistent middle this pins.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final home = app.notebookId!;
    await app.connectGitHub('ghp_fresh_secret_123');
    SecretStore.debugBackend!.remove('github');

    final fresh = AppState(repo)..spellCheckEnabled = false;
    addTearDown(fresh.cancelPendingSave);
    await fresh.selectNotebook(home);
    expect(fresh.githubConnected, isFalse);
    expect(fresh.githubLogin, isNull);
  });

  test('when the password store refuses, nothing is kept anywhere', () async {
    // The fallback is honesty, never a plain file: no store means the connect
    // FAILS with words, and neither the token nor the login is written.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    SecretStore.debugRefuseWrites = true;
    addTearDown(() => SecretStore.debugRefuseWrites = false);
    final problem = await app.connectGitHub('ghp_fresh_secret_123');
    expect(problem, contains('password storage'));
    expect(app.githubConnected, isFalse);
    await repo.flushWorkspace();
    expect(registryText(), isNot(contains('ghp_fresh_secret_123')));
    expect(registryText(), isNot(contains('icmric')));
  });

  test('signing out clears the store too', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await app.connectGitHub('ghp_fresh_secret_123');
    expect(SecretStore.debugBackend, isNotEmpty);
    app.disconnectGitHub();
    expect(SecretStore.debugBackend, isEmpty,
        reason: 'signing out must not leave the token behind in the store');
  });

  test('A LEGACY CLEAR-TEXT TOKEN IS SCRUBBED ON LOAD, and still works',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final home = app.notebookId!;
    // A workspace exactly as a pre-0.8 build left it: token in the file.
    repo.setSetting('github', {'token': 'ghp_legacy_secret_9', 'login': 'icmric'});
    await repo.flushWorkspace();
    expect(registryText(), contains('ghp_legacy_secret_9'),
        reason: 'the legacy shape really is on disk before the load');

    // Through `selectNotebook` and nothing else — same discipline as
    // git_wiring_test: calling reloadGitHub() by hand would test the method,
    // not the wiring that has been forgotten before (0.4.2).
    final fresh = AppState(repo)..spellCheckEnabled = false;
    addTearDown(fresh.cancelPendingSave);
    await fresh.selectNotebook(home);
    await fresh.debugGitHubScrub;

    expect(registryText(), isNot(contains('ghp_legacy_secret_9')),
        reason: 'the scrub rewrites workspace.json without the token');
    expect(backupText(), isNot(contains('ghp_legacy_secret_9')),
        reason: 'the atomic write keeps the OLD file as .bak — after a scrub '
            'that backup is exactly the copy still holding the secret, so it '
            'must be brought in line too');
    expect(registryText(), contains('icmric'), reason: 'the login survives');
    expect(SecretStore.debugBackend!['github'], 'ghp_legacy_secret_9');
    expect(fresh.githubConnected, isTrue);

    // "Still works" means the moved token actually reaches GitHub: create a
    // repository and check the request carried it. (The push after it fails —
    // no git in these tests — but the API call is the part that proves the
    // credential flowed.)
    await fresh.createGitHubRepo(name: 'Notes');
    expect(authHeaders, contains('Bearer ghp_legacy_secret_9'));
  });

  group('the real Windows credential store', () {
    test('round-trips, overwrites and deletes', () async {
      // The FLUTTER_TEST guard routes every ordinary call to memory, which
      // would leave the advapi32 FFI — struct offsets and all — never once
      // executed. This is the execution: a real credential named
      // Openote/selftest, written, read back, replaced, and always removed.
      if (!Platform.isWindows) return markTestSkipped('Windows only');
      const key = 'selftest';
      addTearDown(() => SecretStore.debugPlatformDelete(key));

      expect(await SecretStore.debugPlatformWrite(key, 'first ✓ utf8'), isTrue);
      expect(SecretStore.debugPlatformRead(key), 'first ✓ utf8');
      expect(await SecretStore.debugPlatformWrite(key, 'second'), isTrue,
          reason: 'CredWrite replaces an existing target');
      expect(SecretStore.debugPlatformRead(key), 'second');
      expect(SecretStore.debugPlatformDelete(key), isTrue);
      expect(SecretStore.debugPlatformRead(key), isNull);
    });
  });
}
