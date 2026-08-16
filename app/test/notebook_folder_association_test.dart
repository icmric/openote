// What a student double-clicks, from v0.17 on (plan Step 8b, decision 2 —
// "register the folder instead"), and what they must NOT be able to open.
//
// Four things are asserted here, and each one is a hazard rather than a
// preference:
//
//   1. A `.onotebook` DIRECTORY on argv routes to the join path, not to
//      `openOnote` (matrix row G8). Before this, the sniff answered `notAFile`
//      and the app said "That's a folder, not a notebook" about the notebook.
//   2. The pointer file inside it means the same thing, because Windows
//      associates extensions and a directory name has none.
//   3. NEGATIVE CONTROL — a real `.onote` notebook still opens and is still
//      copied in. The shipped path must not break before the folder path works.
//   4. NEGATIVE CONTROL — a working copy is refused by BOTH checks: the new
//      one on the double-click path (by name, and by `user_version`), and the
//      old one already shipped inside `openOnote`. That is the plan's
//      mitigation 2, and it is what stops somebody cloning a dead copy whose
//      blobs table Step 7 emptied.
//
// Plus the packaging guards, which are the only part of Step 8b that can be
// checked at all from a machine that is not the target platform: the `.onote`
// retirement is registry deletions in an Inno script, and forgetting them is
// the failure the whole retirement half exists to prevent.
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' show Database, sqlite3;

import 'package:openote/core/open_target.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/database.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/op_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var haveSqlite = false;
  setUpAll(() {
    for (final rel in [
      'build/windows/x64/runner/Debug/sqlite3.dll',
      'build/windows/x64/runner/Release/sqlite3.dll',
    ]) {
      final f = File(rel);
      if (f.existsSync()) {
        open.overrideForAll(() => DynamicLibrary.open(f.absolute.path));
        haveSqlite = true;
        break;
      }
    }
  });

  Directory tempDir(String prefix) {
    final d = Directory.systemTemp.createTempSync(prefix);
    addTearDown(() {
      try {
        d.deleteSync(recursive: true);
      } catch (_) {/* Windows can hold a handle a moment longer */}
    });
    return d;
  }

  /// A 72-byte SQLite header with [appId] at 68 and [userVersion] at 60 —
  /// enough for both header questions, and it needs no sqlite3 to build.
  File headerFile(Directory dir, String name,
      {int appId = onoteApplicationId, int userVersion = 1}) {
    final bytes = Uint8List(72);
    const magic = 'SQLite format 3';
    for (var i = 0; i < magic.length; i++) {
      bytes[i] = magic.codeUnitAt(i);
    }
    void be32(int at, int v) {
      bytes[at] = (v >> 24) & 0xFF;
      bytes[at + 1] = (v >> 16) & 0xFF;
      bytes[at + 2] = (v >> 8) & 0xFF;
      bytes[at + 3] = v & 0xFF;
    }

    be32(60, userVersion);
    be32(68, appId);
    return File(p.join(dir.path, name))..writeAsBytesSync(bytes);
  }

  /// A `.onotebook` on disk with nothing but its logs — `folderOnly:` in the
  /// plan's fixture vocabulary, and exactly what the double-click path gets.
  Directory folderNotebook(Directory parent, String title) {
    final store = OpLogStore(Directory(p.join(parent.path, '$title.onotebook')));
    store.ensureInitialised(notebookId: 'nb-$title', title: title);
    return store.dir;
  }

  // ── 1. The classifier ────────────────────────────────────────────────────

  group('what the path names', () {
    test('a .onotebook directory is the notebook', () {
      final drive = tempDir('onote_folder_');
      final folder = folderNotebook(drive, 'Physics');
      expect(notebookFolderNamedBy(folder.path), p.normalize(folder.path));
    });

    // A file manager's `%f` will hand over a trailing separator without a
    // second thought, and the answer has to match the registry either way.
    test('a trailing separator does not change the answer', () {
      final drive = tempDir('onote_folder_');
      final folder = folderNotebook(drive, 'Physics');
      expect(notebookFolderNamedBy('${folder.path}${p.separator}'),
          p.normalize(folder.path));
    });

    test('the pointer file inside it means the same folder', () {
      final drive = tempDir('onote_folder_');
      final folder = folderNotebook(drive, 'Physics');
      final pointer = p.join(folder.path, notebookPointerFileName);
      expect(File(pointer).existsSync(), isTrue,
          reason: 'the folder must carry the one thing Windows can associate');
      expect(notebookFolderNamedBy(pointer), p.normalize(folder.path));
    });

    // An empty directory somebody named by hand is not a notebook. Adopting
    // one registers a permanently empty entry with no ops behind it.
    test('an empty folder with the right name is not a notebook', () {
      final drive = tempDir('onote_folder_');
      final bare = Directory(p.join(drive.path, 'Physics.onotebook'))
        ..createSync();
      expect(notebookFolderNamedBy(bare.path), isNull);
    });

    test('an ordinary folder is not a notebook', () {
      final drive = tempDir('onote_folder_');
      expect(notebookFolderNamedBy(drive.path), isNull);
    });

    test('the working copy is known by its name', () {
      final ws = tempDir('onote_cache_');
      final f = headerFile(ws, 'cache.onote', userVersion: 2);
      expect(isOpenoteWorkingCopy(f.path), isTrue);
    });

    // The name is defeated by a rename; the stamp is not. After Step 8 there is
    // no such thing as a v2 notebook FILE — v2 exists only on working copies.
    test('and by its user_version after a rename', () {
      final ws = tempDir('onote_cache_');
      final f = headerFile(ws, 'Physics.onote', userVersion: 2);
      expect(isOpenoteWorkingCopy(f.path), isTrue);
    });

    test('a real notebook is not a working copy', () {
      final ws = tempDir('onote_cache_');
      final f = headerFile(ws, 'Physics.onote');
      expect(isOpenoteWorkingCopy(f.path), isFalse);
    });

    test("another program's database is not a working copy", () {
      final ws = tempDir('onote_cache_');
      final f = headerFile(ws, 'contacts.onote',
          appId: 0x12345678, userVersion: 9);
      expect(isOpenoteWorkingCopy(f.path), isFalse);
    });
  });

  // ── 2. G8: a directory on argv ───────────────────────────────────────────

  group('a notebook folder handed to the app', () {
    Future<(Repository, AppState)> workspace(Directory dir) async {
      final repo = await Repository.openAt(dir);
      await repo.createNotebook('Alpha');
      final app = AppState(repo);
      await app.init();
      addTearDown(() {
        app.dispose();
        repo.dispose();
      });
      return (repo, app);
    }

    test('routes to the join path, not to openOnote', () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final ws = tempDir('onote_g8_');
      final drive = tempDir('onote_g8_drive_');
      final (repo, app) = await workspace(ws);
      final folder = folderNotebook(drive, 'Lectures');
      final before = repo.notebooks.length;

      final result = await app.openNotebookFile(folder.path);

      expect(result.outcome, OpenNotebookOutcome.opened);
      expect(result.ok, isTrue);
      expect(repo.notebooks.length, before + 1);
      final joined = repo.notebooks.last;
      expect(joined.logDir, isNotNull,
          reason: 'a folder is JOINED — the logs stay where the user put them');
      expect(p.equals(joined.logDir!, folder.path), isTrue);
      expect(p.isWithin(ws.path, joined.file), isTrue,
          reason: 'the local container is made in the workspace, not in Drive');
      // The claim of row G8's last column: the layout is untouched.
      expect(File(p.join(folder.path, 'manifest.json')).existsSync(), isTrue);
      expect(Directory(p.join(folder.path, 'ops')).existsSync(), isTrue);
      expect(
          folder
              .listSync()
              .map((e) => p.basename(e.path))
              .contains(notebookPointerFileName),
          isTrue);
    });

    test('the pointer file inside it opens the same notebook', () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final ws = tempDir('onote_g8_');
      final drive = tempDir('onote_g8_drive_');
      final (repo, app) = await workspace(ws);
      final folder = folderNotebook(drive, 'Lectures');
      final before = repo.notebooks.length;

      final result = await app
          .openNotebookFile(p.join(folder.path, notebookPointerFileName));

      expect(result.outcome, OpenNotebookOutcome.opened);
      expect(repo.notebooks.length, before + 1);
      expect(p.equals(repo.notebooks.last.logDir!, folder.path), isTrue);
    });

    // Idempotent, because a student double-clicks twice when nothing seems to
    // happen. A second entry for the same folder is two sidebar rows writing
    // into one log.
    test('opening the same folder twice registers it once', () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final ws = tempDir('onote_g8_');
      final drive = tempDir('onote_g8_drive_');
      final (repo, app) = await workspace(ws);
      final folder = folderNotebook(drive, 'Lectures');

      await app.openNotebookFile(folder.path);
      final after = repo.notebooks.length;
      final result = await app.openNotebookFile(folder.path);

      // `alreadyOpen`, since both shapes share one resolution funnel: the
      // second click finds the notebook on screen, and the right response is
      // the same as double-clicking an open `.onote` — raise the window, no
      // dialog, register nothing. (`ok` is true either way.)
      expect(result.outcome, OpenNotebookOutcome.alreadyOpen);
      expect(result.ok, isTrue);
      expect(repo.notebooks.length, after);
    });

    test('a folder that is not a notebook is declined in plain words',
        () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final ws = tempDir('onote_g8_');
      final elsewhere = tempDir('onote_g8_other_');
      final (repo, app) = await workspace(ws);
      final before = repo.notebooks.length;

      final result = await app.openNotebookFile(elsewhere.path);

      expect(result.ok, isFalse);
      expect(repo.notebooks.length, before);
      expect(result.message, isNot(contains('Exception')));
      expect(result.message, isNot(contains(elsewhere.path)));
    });
  });

  // ── 2b. Cold start is the same door ──────────────────────────────────────
  //
  // The association launches `openote.exe <pointer file>` precisely when the
  // app is CLOSED, and `init(notebookPath:)` used to feed that path straight
  // to the container sniff — skipping both the folder branch and the
  // working-copy refusal that `openNotebookFile` had. So the flow the
  // association exists for said "That file isn't an Openote notebook" about
  // the user's own notebook, and only when Openote wasn't already running;
  // and `openote D:\backup\cache.onote` at a cold start adopted the
  // picture-less clone a running app refuses. Both doors now go through one
  // resolution funnel, and these cells hold the two branches cold start
  // lacked, plus the copy-in path that must not break.

  group('cold start opens what a double-click delivers', () {
    test('the pointer file opens the notebook at launch', () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final ws = tempDir('onote_cold_');
      final drive = tempDir('onote_cold_drive_');
      final repo = await Repository.openAt(ws);
      final app = AppState(repo);
      addTearDown(() {
        app.dispose();
        repo.dispose();
      });
      final folder = folderNotebook(drive, 'Physics');
      final pointer = File(p.join(folder.path, notebookPointerFileName))
        ..writeAsStringSync(notebookPointerText('Physics'));

      await app.init(notebookPath: pointer.path);

      // MUTATION: point `init` back at `_resolveNotebookFile` and this is the
      // notice that appears — `notANotebook`, about a prose file whose whole
      // job is to be double-clicked.
      expect(app.pendingOpenNotice, isNull,
          reason: 'a notebook that opened is its own confirmation');
      final joined = repo.notebooks.where((n) => n.logDir != null).single;
      expect(p.equals(joined.logDir!, folder.path), isTrue,
          reason: 'JOINED where it lies, exactly as the hand-off path does');
      expect(app.notebookId, joined.id);
    });

    test('a working copy on argv is refused at launch, not adopted', () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final ws = tempDir('onote_cold_cache_');
      final elsewhere = tempDir('onote_cold_cache_src_');
      final repo = await Repository.openAt(ws);
      final alpha = await repo.createNotebook('Alpha');
      final app = AppState(repo);
      addTearDown(() {
        app.dispose();
        repo.dispose();
      });
      // A carried-off working copy: satisfies the SQLite magic and the
      // application_id exactly as a notebook does, so the sniff alone calls
      // it one — which is why cold start bypassing the refusal adopted it.
      final cache = p.join(elsewhere.path, 'cache.onote');
      File(alpha.file).copySync(cache);
      final before = repo.notebooks.length;

      await app.init(notebookPath: cache);

      // MUTATION: point `init` back at `_resolveNotebookFile` and the outcome
      // is `copiedIn` — a clone with every picture missing, registered.
      expect(app.pendingOpenNotice?.outcome, OpenNotebookOutcome.notANotebook);
      expect(app.pendingOpenNotice!.message, contains('working copy'));
      expect(repo.notebooks.length, before, reason: 'nothing was registered');
      expect(app.notebookId, alpha.id, reason: 'the app still came up');
    });

    // NEGATIVE CONTROL for the funnel itself: the path shape cold start
    // always handled keeps its exact behaviour — copied in, and said so.
    test('a real notebook on argv still cold-opens, and is still copied in',
        () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final ws = tempDir('onote_cold_neg_');
      final outside = tempDir('onote_cold_neg_out_');
      final repo = await Repository.openAt(ws);
      await repo.createNotebook('Alpha');
      final app = AppState(repo);
      addTearDown(() {
        app.dispose();
        repo.dispose();
      });
      final other = await Repository.openAt(outside);
      final made = await other.createNotebook('Lectures');
      other.dispose();
      final before = repo.notebooks.length;

      await app.init(notebookPath: made.file);

      expect(app.pendingOpenNotice?.outcome, OpenNotebookOutcome.copiedIn);
      expect(repo.notebooks.length, before + 1);
      expect(app.notebookId, repo.notebooks.last.id);
      expect(p.isWithin(ws.path, repo.notebooks.last.file), isTrue);
      expect(File(made.file).existsSync(), isTrue,
          reason: 'the file they launched stays where it is');
    });
  });

  // ── 3. Negative control: the shipped path still works ────────────────────

  group('the .onote path this must not break', () {
    test('a real notebook file still opens, and is still copied in', () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final ws = tempDir('onote_neg_');
      final outside = tempDir('onote_neg_out_');
      final repo = await Repository.openAt(ws);
      await repo.createNotebook('Alpha');
      final app = AppState(repo);
      await app.init();
      addTearDown(() {
        app.dispose();
        repo.dispose();
      });

      final other = await Repository.openAt(outside);
      final made = await other.createNotebook('Lectures');
      other.dispose();
      final before = repo.notebooks.length;

      final result = await app.openNotebookFile(made.file);

      expect(result.outcome, OpenNotebookOutcome.copiedIn,
          reason: 'the shipped double-click flow, unchanged');
      expect(repo.notebooks.length, before + 1);
      expect(app.notebookId, repo.notebooks.last.id);
    });
  });

  // ── 4. Negative control: the working copy, refused twice ─────────────────

  group('a working copy is refused', () {
    test('by the NEW check, on the double-click path, before anything copies',
        () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final ws = tempDir('onote_cache_open_');
      final elsewhere = tempDir('onote_cache_src_');
      final repo = await Repository.openAt(ws);
      final alpha = await repo.createNotebook('Alpha');
      final app = AppState(repo);
      await app.init();
      addTearDown(() {
        app.dispose();
        repo.dispose();
      });

      // A real container, renamed the way Step 8 names it and carried onto
      // this machine — the "clone a dead copy" hazard exactly.
      final cache = p.join(elsewhere.path, 'cache.onote');
      File(alpha.file).copySync(cache);
      final before = repo.notebooks.length;

      final result = await app.openNotebookFile(cache);

      expect(result.outcome, OpenNotebookOutcome.notANotebook);
      expect(result.ok, isFalse);
      expect(repo.notebooks.length, before,
          reason: 'nothing may be registered');
      expect(
          ws
              .listSync()
              .whereType<File>()
              .where((f) => p.basename(f.path).startsWith('cache')),
          isEmpty,
          reason: 'nothing may land in the workspace either');
      // The sentence the plan drafted, and the jargon bar it has to clear.
      expect(result.message,
          "This is Openote's working copy, not your notebook. Open the "
          'notebook folder instead.');
      for (final jargon in ['container', 'cache', 'format', 'v2', 'SQLite']) {
        expect(result.message.toLowerCase(), isNot(contains(jargon.toLowerCase())),
            reason: '"$jargon" is jargon by any reading of the bar');
      }
      expect(app.pendingOpenNotice?.outcome, OpenNotebookOutcome.notANotebook);
    });

    // **Both directions of the cross-version story, in one test**, because
    // Step 8's stamp made them different numbers rather than one.
    //
    // A student will not upgrade both machines the same day. The October laptop
    // migrates a notebook and stamps its working copy 2; the Christmas desktop
    // is still running a build whose only accepted value is 1. That build's gate
    // is `user_version > onoteFormatMajor`, shipped and unchanged since the
    // format existed, so it says *"newer than this app supports"* and stops —
    // failing safe rather than adopting a cache whose `blobs` table Step 7 has
    // already emptied. This build has to accept the same file, because it wrote
    // it.
    test('by the OLD check already shipped in openOnote, on user_version',
        () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final ws = tempDir('onote_cache_old_');
      final repo = await Repository.openAt(ws);
      final alpha = await repo.createNotebook('Alpha');
      repo.dispose();

      // Stamped the way `Repository.demoteContainerToCache` stamps it.
      final db = sqliteOpenForTest(alpha.file);
      db.execute('PRAGMA user_version = $onoteWorkingCopyVersion;');
      db.execute('PRAGMA wal_checkpoint(TRUNCATE);');
      db.dispose();

      // The OLD build's rule, written out as the expression it evaluates. Its
      // constants are not in this source any more, so this is the one honest way
      // to assert what a build nobody can run here would do.
      expect(onoteWorkingCopyVersion > onoteFormatMajor, isTrue,
          reason: 'a build that accepts only v1 refuses a working copy');

      // THIS build accepts it — it has to, the cache is its own — and refuses
      // anything beyond it, which is the same gate one number along.
      final ok = openOnote(alpha.file, notebookId: 'x', title: 'x');
      expect(ok.select('PRAGMA user_version;').first.columnAt(0),
          onoteWorkingCopyVersion);
      ok.dispose();

      final ahead = sqliteOpenForTest(alpha.file);
      ahead.execute('PRAGMA user_version = ${onoteWorkingCopyVersion + 1};');
      ahead.execute('PRAGMA wal_checkpoint(TRUNCATE);');
      ahead.dispose();
      // MUTATION: widen the gate to `>= 0` and this passes — after which a
      // container written by a future Openote is edited as though it were
      // understood, which is the fault commit fcf2500 fixed for the log.
      expect(
          () => openOnote(alpha.file, notebookId: 'x', title: 'x'),
          throwsA(isA<StateError>().having((e) => '$e', 'message',
              contains('newer than this app supports'))));
    });
  });

  // ── 5. Packaging: the retirement that cannot be an omission ──────────────
  //
  // Inno deletes registry entries at UNINSTALL, and never merely because a line
  // has vanished from the script — and the in-app updater runs the same setup
  // with /SILENT under the same AppId. So an upgrade that dropped the old lines
  // would leave `.onote` pointing at Openote on every existing machine for
  // ever. Matrix row G7 proves this on a Windows runner; this proves the only
  // half a test on any machine can: that the deletions are in the script.

  group('packaging', () {
    Directory repoRoot() {
      var dir = Directory.current;
      for (var i = 0; i < 6; i++) {
        if (File(p.join(dir.path, 'packaging', 'windows', 'openote.iss'))
            .existsSync()) {
          return dir;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
      fail('could not locate the repo root from ${Directory.current.path}');
    }

    /// One entry per line, comments dropped, `\` continuations rejoined and
    /// `{#Macro}` references expanded.
    ///
    /// All three matter. Inno comments start with `;`, and a retirement is
    /// exactly the kind of thing that gets commented out "for a moment" and
    /// shipped that way. Every entry in this script is split across two or
    /// three physical lines, so a check that read them raw would look for a
    /// flag on the line that does not carry it and pass for the wrong reason.
    /// And the keys are written through `#define`s, so the registry key this
    /// really deletes — `Openote.Notebook.1`, the one already on people's
    /// machines — appears nowhere in the entry until the macro is expanded.
    List<String> entries(String script) {
      final defines = <String, String>{};
      for (final m in RegExp(r'^#define\s+(\w+)\s+"([^"]*)"', multiLine: true)
          .allMatches(script)) {
        defines[m.group(1)!] = m.group(2)!;
      }
      String expand(String s) {
        var out = s;
        defines.forEach((k, v) => out = out.replaceAll('{#$k}', v));
        return out;
      }

      final out = <String>[];
      var pending = '';
      for (final raw in script.split('\n')) {
        final line = raw.trim();
        if (pending.isEmpty && (line.isEmpty || line.startsWith(';'))) continue;
        if (line.endsWith(r'\')) {
          pending += '${line.substring(0, line.length - 1).trim()} ';
          continue;
        }
        out.add(expand('$pending$line'.trim()));
        pending = '';
      }
      return out;
    }

    /// The one entry containing [needle], or `''` — spelled as a string rather
    /// than a null so a missing entry fails the flag assertion below with the
    /// same message as a wrong one.
    String find(List<String> live, String needle) =>
        live.firstWhere((l) => l.contains(needle), orElse: () => '');

    test('the Windows installer DELETES the old .onote association', () {
      final live = entries(
          File(p.join(repoRoot().path, 'packaging', 'windows', 'openote.iss'))
              .readAsStringSync());

      // The value on the shared extension key, not the key: another program
      // may have put its own entries under `.onote`.
      expect(find(live, r'Subkey: "Software\Classes\.onote"; ValueType: none'),
          contains('deletevalue'));
      expect(find(live, r'Software\Classes\.onote\OpenWithProgids'),
          contains('deletevalue'));
      expect(find(live, r'SupportedTypes"; ValueType: none'),
          allOf(contains('.onote'), contains('deletevalue')));
      // Ours entirely, so the whole key goes with its icon and its command.
      expect(find(live, r'Software\Classes\Openote.Notebook.1'),
          contains('deletekey'));
    });

    test('and no longer REGISTERS anything against .onote', () {
      final live = entries(
          File(p.join(repoRoot().path, 'packaging', 'windows', 'openote.iss'))
              .readAsStringSync());
      for (final line in live) {
        if (!line.contains('.onote')) continue;
        if (line.contains('.onotelink') || line.contains('.onotebook')) continue;
        expect(line, anyOf(contains('deletevalue'), contains('deletekey')),
            reason: 'a live .onote registration is the whole hazard: $line');
      }
    });

    test('the Linux MIME package drops the magic that matched a working copy',
        () {
      final xml =
          File(p.join(repoRoot().path, 'packaging', 'linux', 'openote.xml'))
              .readAsStringSync();
      final live = xml.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
      expect(live, isNot(contains('<magic')),
          reason: 'SQLite + ONOT identifies a working copy just as well');
      expect(live, isNot(contains('"application/x-onote"')));
      expect(live, isNot(contains('*.onote"')));
      expect(live, contains('application/x-onote-notebook'));
      expect(live, contains('<sub-class-of type="inode/directory"/>'));
      expect(live, contains('*.onotebook'));
      expect(live, contains('*.onotelink'));
    });

    test('the desktop entry claims the new types and not the old one', () {
      final desktop = File(p.join(repoRoot().path, 'packaging', 'linux',
              'org.openote.openote.desktop'))
          .readAsStringSync();
      final mime = desktop
          .split('\n')
          .map((l) => l.trim())
          .firstWhere((l) => l.startsWith('MimeType='));
      expect(mime, contains('application/x-onote-notebook'));
      expect(mime, contains('application/x-onote-link'));
      expect(mime, isNot(contains('application/x-onote;')));
    });
  });
}

/// A raw handle on a container, for the one test that has to stamp a pragma the
/// app itself never writes. Deliberately not a helper in `database.dart`: the
/// app has no reason to open a notebook without its schema, and a shortcut that
/// existed would eventually be used.
Database sqliteOpenForTest(String path) => sqlite3.open(path);
