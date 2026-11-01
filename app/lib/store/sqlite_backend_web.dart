/// The WebAssembly half of [sqlite_backend]: real SQLite, in RAM, gone on
/// refresh.
///
/// **This is the demo's architecture in one file.** The alternative was to
/// extract an interface over `Repository` and write a fake one, which means
/// touching a 2,000-line class that every test and the whole storage layer
/// depend on, and then showing people a lookalike instead of the editor. This
/// way the container is a real `.onote`, the op log is the real op log, the
/// search index is real FTS5 — only the disk is imaginary.
///
/// [InMemoryFileSystem] is registered as the default VFS, so every path the
/// workspace asks for resolves inside the tab's heap. Nothing is written
/// anywhere a browser could keep it: not OPFS, not IndexedDB, not
/// `localStorage`. "Nothing here is saved" is therefore a description of the
/// mechanism rather than a promise someone has to remember to keep.
///
/// `sqlite3.wasm` is fetched from the app's own origin at boot (see
/// `web/README.md` for where the file comes from and how to update it). It is
/// about 730 KB and the fetch happens once, in parallel with the first frame.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:sqlite3/common.dart';
import 'package:sqlite3/wasm.dart';
import 'package:typed_data/typed_buffers.dart';
import 'package:web/web.dart' as web;

/// Beside `index.html` in the build output, and committed in `web/`.
const kSqliteWasmFile = 'sqlite3.wasm';

WasmSqlite3? _sqlite;

/// Held on to so that [platformSeedSqliteFile] can put bytes into it. The VFS
/// owns the only copy of every database in the demo, so this reference is
/// also, quite literally, the whole workspace.
InMemoryFileSystem? _vfs;

/// Fetch and instantiate `sqlite3.wasm`, then point it at an in-memory disk.
///
/// Idempotent: `main` calls it once, but a test or a hot restart may arrive
/// here again and re-instantiating would silently discard the open databases.
Future<void> platformInitSqlite() async {
  if (_sqlite != null) return;
  final url = Uri.parse(kSqliteWasmFile);
  final WasmSqlite3 sqlite;
  try {
    sqlite = await WasmSqlite3.loadFromUrl(url);
  } catch (e) {
    // **This runs before `runApp`, so it is the one failure the app's own
    // in-window error screen cannot report** — it lands in the plain-HTML
    // handler in `web/index.html` instead, which has nothing but the message.
    // So the message has to carry the diagnosis, and `TypeError: Failed to
    // fetch` on its own does not: it names no URL and does not distinguish
    // "not deployed" from "cannot be requested at all".
    throw StateError(await _whyWasmFailed(url, e));
  }
  // `makeDefault` so an unprefixed path — which is every path the workspace
  // builds — lands here rather than in a VFS that would try to persist.
  final vfs = InMemoryFileSystem();
  sqlite.registerVirtualFileSystem(vfs, makeDefault: true);
  _vfs = vfs;
  _sqlite = sqlite;
}

CommonDatabase platformOpenSqliteFile(String path) {
  final sqlite = _sqlite;
  if (sqlite == null) {
    // Reachable only if something opens a notebook before `main` has awaited
    // `initSqlite`. Said out loud rather than lazily loading here, because a
    // lazy load would have to be synchronous and cannot be.
    throw StateError(
        'initSqlite() must be awaited before opening a database on the web.');
  }
  return sqlite.open(path);
}

CommonDatabase platformOpenSqliteInMemory() {
  final sqlite = _sqlite;
  if (sqlite == null) {
    throw StateError(
        'initSqlite() must be awaited before opening a database on the web.');
  }
  // `:memory:` rather than the in-memory VFS: this one is for the SQL code
  // block, which wants a scratch database with no filename at all.
  return sqlite.openInMemory();
}

/// Put a whole database into the VFS before anything opens it.
///
/// This is how the demo notebook arrives: it ships as `assets/demo/demo.onote`
/// — a real container, authored in Openote itself — and is handed to SQLite
/// here rather than being built row by row from Dart.
///
/// The key is whatever [InMemoryFileSystem.xFullPathName] would make of
/// [path], asked of the VFS rather than guessed, because that is the name
/// SQLite will look the file up by when it opens it.
void platformSeedSqliteFile(String path, Uint8List bytes) {
  final vfs = _vfs;
  if (vfs == null) {
    throw StateError('initSqlite() must be awaited before seeding a database.');
  }
  vfs.fileData[vfs.xFullPathName(path)] = Uint8Buffer()..addAll(bytes);
}

const bool platformSqliteLibraryIsSelectable = false;

/// Nothing to point at: the implementation is the wasm module already loaded.
void platformUseSqliteLibraryAt(String path) {}

/// Turn a failed wasm load into a sentence that says what to do about it.
///
/// Asks the question again with a plain `fetch`, because the three realistic
/// causes are told apart by the answer and not by the exception:
///
/// * **no answer at all** — the page is on a `file://` path, where fetch is
///   not allowed. This is the common one: `flutter build web` produces a
///   folder, and opening its `index.html` by double-clicking is the obvious
///   thing to try and cannot work.
/// * **an answer with a status** — the file is not where the page expects,
///   usually a build served from a sub-path without a matching `--base-href`.
/// * **an answer with the wrong content type** — the host does not know what
///   a `.wasm` is. WebAssembly refuses to compile anything but
///   `application/wasm`.
Future<String> _whyWasmFailed(Uri url, Object cause) async {
  final where = Uri.base.resolveUri(url);
  try {
    final r = await web.window.fetch(where.toString().toJS).toDart;
    if (!r.ok) {
      return 'Could not load $where — the server answered ${r.status}. '
          'It should sit beside index.html in the build output. ($cause)';
    }
    final type = r.headers.get('content-type') ?? 'nothing';
    return 'Could not load $where — the server sent it as "$type", and '
        'WebAssembly only accepts application/wasm. ($cause)';
  } catch (_) {
    return 'Could not request $where at all. The demo has to be served over '
        'http: a page opened straight from a file on disk is not allowed to '
        'fetch anything. From the build output, `python3 -m http.server` and '
        'then open the address it prints. ($cause)';
  }
}
