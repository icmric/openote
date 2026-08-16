/// What a path handed to Openote from OUTSIDE the app actually names.
///
/// `startup_args.dart` answers *which argument is the path*; this answers *and
/// what is at the other end of it*. Two files because the first question is
/// decidable without touching the disk and every question here is a `statSync`
/// or a 72-byte read.
///
/// **Why this exists (v0.17 plan, Step 8b, decision 2 — "register the folder
/// instead").** Until v0.17 a notebook was a `.onote` file and double-clicking
/// one was the whole story. From v0.17 the notebook is the **`.onotebook`
/// directory**: the container beside it became a local-only working copy that
/// is never synced and, after Step 7, no longer holds a single picture. So the
/// thing a student double-clicks is a folder — or the small pointer file
/// inside it — and the thing they must NOT be able to open is the container.
///
/// Both answers have to be given before anything opens or copies, for the same
/// reason `notebookFileProblem` runs before `openExistingNotebook`: by the time
/// SQLite has an opinion, a copy has already landed in the workspace.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

// The container's identity, defined once. A second copy of "ONOT" and of the
// format major here would be a second chance to disagree with the file that
// WRITES them, and `isOpenoteWorkingCopy` below is only correct while the two
// agree. Importing this does not load sqlite3 — only `sqlite3.open` does — so
// a test that never touches a database still runs.
import '../store/database.dart'
    show onoteApplicationId, onoteFormatMajor, onoteWorkingCopyVersion;

/// The extension on the notebook itself, which is a directory.
const notebookFolderExtension = '.onotebook';

/// The pointer file's extension — and the whole reason a pointer file exists.
///
/// **Windows associates EXTENSIONS, and a directory name has none.** The two
/// mechanisms Windows does offer are a `Directory\shell\<verb>` entry, which
/// puts "Open with Openote" on the context menu of *every folder on the
/// machine* and still does not change what a double-click does, and a
/// registered shell namespace extension, which is a COM DLL and far outside
/// what a per-user Inno install can or should do. So the folder gets a small
/// file inside it with an extension of its own, associated the ordinary way.
///
/// Deliberately **not** `.onote`: that association is being retired in the same
/// release (packaging/windows/openote.iss), and reusing it would resurrect the
/// exact hazard the retirement exists to close.
const notebookPointerExtension = '.onotelink';

/// The pointer file's name, in the words a student reads in Explorer.
///
/// Fixed rather than derived from the title, because the title changes and a
/// renamed notebook must not leave a second stale pointer beside the first —
/// and because nothing ever reads this name to find the notebook. The folder
/// the file SITS IN is the notebook; the name is a label for a human.
const notebookPointerFileName = 'Open this notebook$notebookPointerExtension';

/// The container's name once it is a working copy (v0.17 Step 8). Matched
/// case-insensitively: Windows and macOS both hand back whatever case the user
/// typed.
///
/// **It is NOT inside the `.onotebook`, and that correction matters.** ADR-0006
/// §3 draws `cache.onote` inside the notebook folder, and an earlier draft of
/// this comment repeated it. For a shared notebook that folder *is* the Drive
/// folder, so the drawing puts a live WAL SQLite database back into the
/// replicated tree — the exact 31,954,368 bytes commit 435b2bd took out of the
/// owner's own Drive, and the hazard the plan's §1.2 forbids. The working copy
/// lives in a per-notebook cache directory under the workspace instead; see
/// `Repository.cacheDirFor`. The ADR is what is wrong and is amended alongside
/// this.
const workingCopyFileName = 'cache.onote';

/// The `.onotebook` directory [path] names, or null when it names none.
///
/// Accepts the directory itself and the pointer file inside it, because those
/// are the two things a file manager can hand over and they mean the same
/// thing. Returns a normalised path so the caller can compare it against the
/// registry without wondering about a trailing separator — a Linux file
/// manager's `%f` quite happily supplies one.
String? notebookFolderNamedBy(String path) {
  final normalised = p.normalize(path);
  // The pointer file FIRST: it is a file, so the directory test below would
  // answer "no" about the one thing Windows can actually associate.
  if (p.extension(normalised).toLowerCase() == notebookPointerExtension) {
    final holder = p.dirname(normalised);
    return _looksLikeNotebookFolder(holder) ? holder : null;
  }
  return _looksLikeNotebookFolder(normalised) ? normalised : null;
}

/// Whether [path] is Openote's own working copy rather than anybody's notebook.
///
/// Two independent tests, because either one alone has a hole:
///
/// * **By name.** `cache.onote` is what Step 8 calls the container, and the
///   name survives a copy onto a USB stick, an email attachment and a rename
///   of the folder around it.
/// * **By `user_version`.** A student who renames the file defeats the first
///   test, and the second still holds: the container is stamped
///   [onoteWorkingCopyVersion] by Step 8's migration and a notebook file never
///   is. Every other producer of a container stamps [onoteFormatMajor]:
///   `_seedNotebook` on a fresh file, and `duplicateNotebook`, which stamps a
///   copy back down to 1 precisely so that duplicating a migrated notebook
///   cannot mint a v2 file that is not a cache.
///
/// This is the *new* half of the plan's mitigation 2. The old half is already
/// shipped and is `openOnote`'s `user_version` gate, which is what makes a
/// build that predates all of this refuse the same file — a pre-v0.17 build
/// accepts 1 and nothing else, so it says *"newer than this app supports"* and
/// stops, which is failing safe rather than failing quietly.
///
/// What it prevents, concretely: after Step 7 the container's `blobs` table is
/// empty, so cloning one produces a notebook whose every picture is missing —
/// and it passes `integrity_check`, and `notebookFileProblem` calls it "looks
/// like a notebook", because a cache satisfies the SQLite magic and the
/// `application_id` just as a notebook does.
bool isOpenoteWorkingCopy(String path) {
  if (p.basename(path).toLowerCase() == workingCopyFileName) return true;
  final head = _sqliteHeader(path);
  if (head == null) return false;
  // Only ours. Another program's SQLite database with a high user_version is
  // not a working copy of anything, and `notebookFileProblem` already has the
  // right sentence for it.
  if (_be32(head, 68) != onoteApplicationId) return false;
  // Offset 60 is `user_version`, four bytes big-endian like every multi-byte
  // field in a SQLite header — the same header `notebookFileProblem` reads
  // application_id out of at 68.
  return _be32(head, 60) >= onoteWorkingCopyVersion;
}

/// The pointer file's contents.
///
/// Plain UTF-8 prose and nothing else. It is not a database, not JSON and not
/// parsed by anything: [notebookFolderNamedBy] uses the directory the file sits
/// in and never opens it. That is deliberate — a pointer file that had to be
/// read correctly would be a second thing that can be corrupt, in the one
/// directory that must survive a cloud client's worst day. It also means the
/// title below going stale after a rename costs nothing but a wrong word, and
/// the last line says so rather than pretending otherwise.
String notebookPointerText(String title) => '''
Openote notebook — "$title"

Double-click this file to open the notebook in Openote.

The notebook is this whole folder, not any one file in it. Keep the folder
together, and keep it in the folder you sync (Drive, OneDrive, Dropbox) if you
want your notes on more than one computer.

Openote only needs to know which folder this file is in. You can change or
delete the words above and it will still open.
''';

/// Put the pointer file in [folder] if it is not already there.
///
/// Best-effort on purpose. A read-only volume, a full disk or a cloud client
/// holding the directory must never stop a notebook being written — the notes
/// are the point and this file is a convenience — so a failure here is
/// swallowed exactly the way `_dropBlobRefsBlobsFk` swallows its own.
///
/// Never rewritten once present: this file lives in the synced folder, so
/// rewriting it on every open would be a write every other device has to pull
/// for no change anybody asked for.
void ensureNotebookPointer(String folder, {required String title}) {
  try {
    final f = File(p.join(folder, notebookPointerFileName));
    if (f.existsSync()) return;
    f.writeAsStringSync(notebookPointerText(title), flush: true);
  } catch (_) {
    // See above: a notebook that saves is worth more than a shortcut that does.
  }
}

/// A directory that is really one of ours.
///
/// The extension alone is not enough. An empty directory somebody named
/// `Physics.onotebook` by hand would otherwise be adopted as a notebook, and
/// what that registers is a permanently empty entry with no ops behind it that
/// never syncs anywhere and never goes away — the same ghost
/// `Repository.adoptLogDirectory` refuses to seed for the git-clone case.
///
/// The two marks are `manifest.json` or `ops/`, which is exactly what
/// `sync_dialog.dart` looks for when it scans a shared folder. Either, not
/// both: a folder that has been pulled but never written has no `ops/` of its
/// own yet, and one written by a build that predates the manifest has no
/// manifest.
bool _looksLikeNotebookFolder(String path) {
  if (p.extension(path).toLowerCase() != notebookFolderExtension) return false;
  if (!Directory(path).existsSync()) return false;
  return File(p.join(path, 'manifest.json')).existsSync() ||
      Directory(p.join(path, 'ops')).existsSync();
}

/// The first 72 bytes of [path], or null when there is no file there or it is
/// too short to have a SQLite header at all.
Uint8List? _sqliteHeader(String path) {
  try {
    if (FileSystemEntity.typeSync(path, followLinks: true) !=
        FileSystemEntityType.file) {
      return null;
    }
    final handle = File(path).openSync();
    try {
      final head = handle.readSync(72);
      return head.length < 72 ? null : head;
    } finally {
      handle.closeSync();
    }
  } catch (_) {
    // Unreadable is not "is a working copy". The caller's next step is the
    // sniff in `notebookFileProblem`, which has the right sentence for a file
    // this process cannot read.
    return null;
  }
}

int _be32(Uint8List b, int at) =>
    (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];
