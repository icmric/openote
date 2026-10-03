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

import 'package:sqlite3/common.dart';
import 'package:sqlite3/wasm.dart';

WasmSqlite3? _sqlite;

/// Fetch and instantiate `sqlite3.wasm`, then point it at an in-memory disk.
///
/// Idempotent: `main` calls it once, but a test or a hot restart may arrive
/// here again and re-instantiating would silently discard the open databases.
Future<void> platformInitSqlite() async {
  if (_sqlite != null) return;
  final sqlite = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
  // `makeDefault` so an unprefixed path — which is every path the workspace
  // builds — lands here rather than in a VFS that would try to persist.
  sqlite.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
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

const bool platformSqliteLibraryIsSelectable = false;

/// Nothing to point at: the implementation is the wasm module already loaded.
void platformUseSqliteLibraryAt(String path) {}
