// Opening a notebook Openote was HANDED — `openote path/to/notebook.onote`,
// or a double-click on a .onote in the file manager (backlog: "Open a notebook
// passed on the command line").
//
// Three layers, each exercised through its real entry point rather than
// reasoned about:
//
//   1. `notebookPathFromArgs` — raw argv in, an absolute path out. Relative
//      paths, spaces, engine switches, `file://` URLs.
//   2. `notebookFileProblem` — the header sniff that has to happen BEFORE
//      anything copies or opens the file, because `openOnote` seeds a blank
//      notebook into any file whose application_id is zero and
//      `openExistingNotebook` copies first and opens second.
//   3. `AppState.init(notebookPath:)` / `AppState.openNotebookFile` — the five
//      cases the task names: relative path, spaces, missing, not a notebook,
//      already open.
//
// Layers 1 and 2 need nothing but the filesystem. Layer 3 opens real SQLite
// containers, so it skips when the bundled sqlite3.dll isn't built — the same
// guard notebook_lifecycle_test.dart uses.
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/open.dart';

import 'package:openote/core/startup_args.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/database.dart';
import 'package:openote/store/repository.dart';

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

  // ── 1. What the process was asked to open ────────────────────────────────

  group('notebookPathFromArgs', () {
    const cwd = r'/home/e/notes';

    test('a plain launch asks for nothing', () {
      expect(notebookPathFromArgs(const [], workingDirectory: cwd), isNull);
    });

    test('a relative path is resolved against the working directory', () {
      expect(
        notebookPathFromArgs(const ['term1/Physics.onote'],
            workingDirectory: cwd),
        p.normalize(p.join(cwd, 'term1/Physics.onote')),
      );
    });

    test('an absolute path is left alone', () {
      final abs = p.join(cwd, 'Physics.onote');
      expect(notebookPathFromArgs([abs], workingDirectory: cwd),
          p.normalize(abs));
    });

    // Explorer runs `openote.exe "C:\My Notes\Term 1.onote"` and
    // CommandLineToArgvW has already removed the quotes; the space must
    // survive untouched, and the app must not "helpfully" re-strip anything.
    test('a path with spaces arrives as one argument, intact', () {
      final got = notebookPathFromArgs(const ['My Notes/Term 1.onote'],
          workingDirectory: cwd);
      expect(got, endsWith('Term 1.onote'));
      expect(got, contains('My Notes'));
    });

    test('engine switches and Finder process serials are skipped', () {
      expect(
        notebookPathFromArgs(
            const ['--enable-dart-profiling', '-psn_0_1234', 'Physics.onote'],
            workingDirectory: cwd),
        p.normalize(p.join(cwd, 'Physics.onote')),
      );
    });

    test('after -- a hyphen is part of the filename', () {
      expect(
        notebookPathFromArgs(const ['--', '-notes.onote'],
            workingDirectory: cwd),
        p.normalize(p.join(cwd, '-notes.onote')),
      );
    });

    // Some launchers and desktop portals hand over a URL even when the desktop
    // entry asked for `%f`. `file:///home/e/My%20Notes.onote` is not a filename.
    test('a file:// URL is decoded into a path', () {
      final got = notebookPathFromArgs(
          const ['file:///home/e/My%20Notes.onote'],
          workingDirectory: cwd);
      expect(got, isNotNull);
      expect(p.basename(got!), 'My Notes.onote');
    });

    test('an http URL is not a notebook on this machine', () {
      expect(
        notebookPathFromArgs(const ['https://example.com/x.onote'],
            workingDirectory: cwd),
        isNull,
      );
    });

    test('only the first notebook wins', () {
      expect(
        notebookPathFromArgs(const ['a.onote', 'b.onote'],
            workingDirectory: cwd),
        p.normalize(p.join(cwd, 'a.onote')),
      );
    });
  });

  // ── 2. Is that file a notebook at all? ───────────────────────────────────

  group('notebookFileProblem', () {
    /// A 72-byte SQLite header with [appId] at offset 68. Enough to answer the
    /// question, and it needs no sqlite3 to build.
    File headerFile(Directory dir, String name, int appId) {
      final bytes = Uint8List(72);
      const magic = 'SQLite format 3';
      for (var i = 0; i < magic.length; i++) {
        bytes[i] = magic.codeUnitAt(i);
      }
      bytes[15] = 0;
      bytes[68] = (appId >> 24) & 0xFF;
      bytes[69] = (appId >> 16) & 0xFF;
      bytes[70] = (appId >> 8) & 0xFF;
      bytes[71] = appId & 0xFF;
      final f = File(p.join(dir.path, name))..writeAsBytesSync(bytes);
      return f;
    }

    test('nothing at that path', () {
      final dir = tempDir('onote_sniff_');
      expect(notebookFileProblem(p.join(dir.path, 'gone.onote')),
          NotebookFileProblem.missing);
    });

    test('a folder is not a file we can open', () {
      final dir = tempDir('onote_sniff_');
      final sub = Directory(p.join(dir.path, 'Physics.onote'))..createSync();
      expect(notebookFileProblem(sub.path), NotebookFileProblem.notAFile);
    });

    test('a text file renamed .onote is refused', () {
      final dir = tempDir('onote_sniff_');
      final f = File(p.join(dir.path, 'Physics.onote'))
        ..writeAsStringSync('these are my notes, not a notebook');
      expect(notebookFileProblem(f.path), NotebookFileProblem.notANotebook);
    });

    // The one that matters most: `openOnote` reads an application_id of zero as
    // "a fresh file" and SEEDS a notebook into it. Without this guard a stray
    // empty file becomes a permanent blank notebook in the sidebar.
    test('an empty file is refused rather than seeded', () {
      final dir = tempDir('onote_sniff_');
      final f = File(p.join(dir.path, 'Physics.onote'))..writeAsBytesSync([]);
      expect(notebookFileProblem(f.path), NotebookFileProblem.notANotebook);
    });

    test("another program's SQLite database is refused", () {
      final dir = tempDir('onote_sniff_');
      final f = headerFile(dir, 'contacts.onote', 0x12345678);
      expect(notebookFileProblem(f.path), NotebookFileProblem.notANotebook);
    });

    test('the ONOT application id is what makes it ours', () {
      final dir = tempDir('onote_sniff_');
      final f = headerFile(dir, 'Physics.onote', onoteApplicationId);
      expect(notebookFileProblem(f.path), isNull);
    });

    // An un-checkpointed container still reads as zeros here. Calling a real
    // notebook a stranger because the app once crashed is the wrong way to be
    // wrong, so a `-wal` beside it defers the decision to the real open.
    test('a zero id with a -wal beside it is given the benefit of the doubt',
        () {
      final dir = tempDir('onote_sniff_');
      final f = headerFile(dir, 'Physics.onote', 0);
      expect(notebookFileProblem(f.path), NotebookFileProblem.notANotebook);
      File('${f.path}-wal').writeAsBytesSync([0]);
      expect(notebookFileProblem(f.path), isNull);
    });

    test('a real notebook made by Repository passes', () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final dir = tempDir('onote_sniff_real_');
      final repo = await Repository.openAt(dir);
      final ref = await repo.createNotebook('Physics');
      repo.dispose(); // checkpoints the WAL back into the container
      expect(notebookFileProblem(ref.file), isNull);
    });
  });

  // ── 3. Opening it ────────────────────────────────────────────────────────

  group('AppState opens what it is handed', () {
    /// A workspace with two notebooks, Beta open — so Alpha is a notebook that
    /// exists and is NOT on screen, which is what "open this one instead" needs
    /// to be a real switch. (`init` alone lands on the first notebook.)
    Future<(Repository, AppState)> workspace(Directory dir) async {
      final repo = await Repository.openAt(dir);
      await repo.createNotebook('Alpha');
      final beta = await repo.createNotebook('Beta');
      final app = AppState(repo);
      await app.init();
      await app.selectNotebook(beta.id);
      addTearDown(() {
        app.dispose();
        repo.dispose();
      });
      return (repo, app);
    }

    /// Containers only. Opening a notebook leaves `-wal` and `-shm` beside it,
    /// so a raw file count answers a different question than the one asked.
    int containers(Directory dir) => dir
        .listSync()
        .whereType<File>()
        .where((f) => p.extension(f.path).toLowerCase() == '.onote')
        .length;

    test('a notebook already in the workspace is switched to, not copied',
        () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final dir = tempDir('onote_open_');
      final (repo, app) = await workspace(dir);
      final alpha = repo.notebooks.firstWhere((n) => n.title == 'Alpha');
      final before = repo.notebooks.length;

      final result = await app.openNotebookFile(alpha.file);

      expect(result.outcome, OpenNotebookOutcome.opened);
      expect(app.notebookId, alpha.id);
      expect(repo.notebooks.length, before,
          reason: 'switching must not register a second copy');
    });

    // The un-normalised form a shortcut or a shell can produce. `p.normalize`
    // in `_resolveNotebookFile` is what makes it match the registry entry
    // instead of looking like a stranger's file that needs copying in.
    test('a path with .. segments still matches the registry', () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final dir = tempDir('onote_open_');
      final (repo, app) = await workspace(dir);
      final alpha = repo.notebooks.firstWhere((n) => n.title == 'Alpha');
      Directory(p.join(dir.path, 'sub')).createSync();
      final roundabout =
          p.join(dir.path, 'sub', '..', p.basename(alpha.file));
      final before = repo.notebooks.length;

      final result = await app.openNotebookFile(roundabout);

      expect(result.outcome, OpenNotebookOutcome.opened);
      expect(app.notebookId, alpha.id);
      expect(repo.notebooks.length, before);
    });

    test('opening the notebook already on screen says so and changes nothing',
        () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final dir = tempDir('onote_open_');
      final (repo, app) = await workspace(dir);
      final current = repo.notebooks.firstWhere((n) => n.id == app.notebookId);

      final result = await app.openNotebookFile(current.file);

      expect(result.outcome, OpenNotebookOutcome.alreadyOpen);
      expect(result.ok, isTrue);
      expect(app.notebookId, current.id);
      expect(app.pendingOpenNotice, isNull,
          reason: 'no dialog for the notebook that is already open');
    });

    test('a path that is not there is a sentence, not an exception', () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final dir = tempDir('onote_open_');
      final (repo, app) = await workspace(dir);
      final was = app.notebookId;
      final before = repo.notebooks.length;

      final result = await app.openNotebookFile(p.join(dir.path, 'Gone.onote'));

      expect(result.outcome, OpenNotebookOutcome.notFound);
      expect(result.ok, isFalse);
      expect(result.message, isNot(contains('Exception')));
      expect(result.message, isNot(contains('#0 ')));
      expect(result.message, isNot(contains(dir.path)),
          reason: 'the path belongs under Advanced, not in the sentence');
      expect(result.details, contains('Gone.onote'));
      expect(app.pendingOpenNotice?.outcome, OpenNotebookOutcome.notFound);
      expect(app.notebookId, was, reason: 'a bad path must not close anything');
      expect(repo.notebooks.length, before);
    });

    // The consequence of sniffing before copying: the workspace is untouched.
    test('a file that is not a notebook is refused before anything is copied',
        () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final dir = tempDir('onote_open_');
      final outside = tempDir('onote_elsewhere_');
      final (repo, app) = await workspace(dir);
      final impostor = File(p.join(outside.path, 'Physics.onote'))
        ..writeAsStringSync('not a notebook');
      final before = repo.notebooks.length;

      final result = await app.openNotebookFile(impostor.path);

      expect(result.outcome, OpenNotebookOutcome.notANotebook);
      expect(repo.notebooks.length, before);
      expect(
        dir.listSync().whereType<File>().where(
            (f) => p.basename(f.path).toLowerCase().startsWith('physics')),
        isEmpty,
        reason: 'nothing may land in the workspace before the file is checked',
      );
    });

    test('a notebook from outside the workspace is copied in, and says so',
        () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final dir = tempDir('onote_open_');
      final outside = tempDir('onote_elsewhere_');
      final (repo, app) = await workspace(dir);

      // A notebook that genuinely exists somewhere else — built by a second
      // workspace so it is a real container, not a hand-made header.
      final other = await Repository.openAt(outside);
      final made = await other.createNotebook('Lectures');
      other.dispose();

      final before = repo.notebooks.length;
      final result = await app.openNotebookFile(made.file);

      expect(result.outcome, OpenNotebookOutcome.copiedIn);
      expect(result.ok, isTrue);
      expect(repo.notebooks.length, before + 1);
      expect(app.notebookId, repo.notebooks.last.id);
      expect(File(made.file).existsSync(), isTrue,
          reason: 'the file they double-clicked stays where it is');
      expect(p.isWithin(dir.path, repo.notebooks.last.file), isTrue);
      // The user has to be told, because their edits now go to the copy.
      expect(app.pendingOpenNotice?.outcome, OpenNotebookOutcome.copiedIn);
    });

    // Opening a notebook a friend emailed you must not tell the app that
    // ~/Downloads is "where my notes sync" — the sync chip would then repeat
    // that claim on every launch. The onboarding flow reaches the same
    // repository call and DOES record the folder, because there the user has
    // just browsed to their Drive folder and said so.
    test('a notebook with no shared log folder is not a sync location',
        () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final dir = tempDir('onote_open_');
      final downloads = tempDir('onote_downloads_');
      final (_, app) = await workspace(dir);

      final other = await Repository.openAt(downloads);
      final made = await other.createNotebook('Lectures');
      other.dispose();
      // Whatever the container's own log folder was, it is not beside the file
      // the way a folder-synced notebook's would be.
      final sibling = Directory('${p.withoutExtension(made.file)}.onotebook');
      if (sibling.existsSync()) sibling.deleteSync(recursive: true);

      await app.openNotebookFile(made.file);

      expect(app.syncRoots.any((f) => p.equals(f.path, downloads.path)), isFalse,
          reason: 'double-clicking a file is not choosing a sync folder');
    });

    test('a notebook that IS in a shared folder still records it', () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final dir = tempDir('onote_open_');
      final drive = tempDir('onote_drive_');
      final (_, app) = await workspace(dir);

      final other = await Repository.openAt(drive);
      final made = await other.createNotebook('Lectures');
      other.dispose();
      // The mark of a folder-synced notebook: its op logs sit beside it.
      Directory('${p.withoutExtension(made.file)}.onotebook')
          .createSync(recursive: true);

      await app.openNotebookFile(made.file);

      expect(app.syncRoots.any((f) => p.equals(f.path, drive.path)), isTrue);
    });

    // Dropping a .onote into Documents/Openote by hand and double-clicking it
    // must not produce `Physics-1.onote` beside `Physics.onote`, with the
    // user's edits going to the one they did not open.
    test('a stray notebook inside the workspace is adopted where it lies',
        () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final dir = tempDir('onote_open_');
      final source = tempDir('onote_source_');
      final (repo, app) = await workspace(dir);

      final other = await Repository.openAt(source);
      final made = await other.createNotebook('Lectures');
      other.dispose();
      final stray = p.join(dir.path, 'Lectures.onote');
      File(made.file).copySync(stray);

      final before = containers(dir);
      final result = await app.openNotebookFile(stray);

      expect(result.outcome, OpenNotebookOutcome.opened);
      expect(repo.notebooks.last.file, stray,
          reason: 'registered where it already is');
      expect(repo.notebooks.last.logDir, isNull,
          reason: 'the workspace folder must not become a sync location');
      expect(containers(dir), before,
          reason: 'no second container beside the one they double-clicked');
    });

    test('double-clicking a deleted notebook restores it', () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final dir = tempDir('onote_open_');
      final (repo, app) = await workspace(dir);
      // Alpha, not the open one: restoring is only interesting when the
      // notebook has to come back AND be switched to.
      final alpha = repo.notebooks.firstWhere((n) => n.title == 'Alpha');
      await repo.trashNotebook(alpha.id);
      expect(repo.trashedNotebooks.map((n) => n.id), contains(alpha.id));

      final result = await app.openNotebookFile(alpha.file);

      expect(result.outcome, OpenNotebookOutcome.opened);
      expect(app.notebookId, alpha.id);
      expect(repo.trashedNotebooks, isEmpty);
      expect(repo.notebooks.map((n) => n.id), contains(alpha.id));
    });
  });

  // ── 4. Startup, which is where the command line actually lands ───────────

  group('AppState.init(notebookPath:)', () {
    test('opens the notebook it was launched with, not the last one', () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final dir = tempDir('onote_boot_');
      final repo = await Repository.openAt(dir);
      final alpha = await repo.createNotebook('Alpha');
      await repo.createNotebook('Beta');
      // Pretend the last session ended in Beta.
      repo.setSetting('lastNotebook', repo.notebooks.last.id);

      final app = AppState(repo);
      addTearDown(() {
        app.dispose();
        repo.dispose();
      });
      await app.init(notebookPath: alpha.file);

      expect(app.notebookId, alpha.id);
      expect(app.pendingOpenNotice, isNull);
    });

    // A desktop shortcut that outlived the file it pointed at must not make
    // the app unlaunchable — it comes up on the last notebook and explains.
    test('a bad path still starts the app, with something to say', () async {
      if (!haveSqlite) {
        markTestSkipped('sqlite3.dll not built');
        return;
      }
      final dir = tempDir('onote_boot_');
      final repo = await Repository.openAt(dir);
      final alpha = await repo.createNotebook('Alpha');

      final app = AppState(repo);
      addTearDown(() {
        app.dispose();
        repo.dispose();
      });
      await app.init(notebookPath: p.join(dir.path, 'Missing.onote'));

      expect(app.notebookId, alpha.id, reason: 'the app still came up');
      expect(app.pendingOpenNotice?.outcome, OpenNotebookOutcome.notFound);
      expect(app.pendingOpenNotice!.message, isNot(contains('Missing.onote')));
    });
  });
}
