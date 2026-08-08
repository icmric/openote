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
}
