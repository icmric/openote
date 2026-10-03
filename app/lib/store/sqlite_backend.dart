/// Which SQLite the app is talking to, and the one door that opens a database.
///
/// **Why this file exists.** `package:sqlite3/sqlite3.dart` is the `dart:ffi`
/// entrypoint, and `dart:ffi` is a hard compile error in a browser build — it
/// was 5,234 of the 8,284 errors a web build reported, more than every other
/// cause put together. But the package already ships the answer: everything
/// the store actually uses is declared in `package:sqlite3/common.dart` and
/// implemented by **both** backends, the native one and the WebAssembly one.
/// So the type the store passes around becomes [CommonDatabase], the factory
/// moves behind a conditional import, and that is the whole change — 17 uses
/// of `Database` and two calls to `sqlite3.open`.
///
/// This file re-exports `common.dart`, so a caller swaps
/// `import 'package:sqlite3/sqlite3.dart'` for this and keeps everything else:
/// [SqliteException], `ResultSet`, `StatementParameters` and the rest are the
/// same declarations they always were.
///
/// **The web build is deliberately amnesiac.** [openSqliteFile] on the web
/// opens inside an [InMemoryFileSystem], so the container, the op log and the
/// FTS index are all real — the genuine storage layer, exercised rather than
/// bypassed — and all of it lives in the tab's heap and is gone on refresh.
/// That is the demo's defining property, not a limitation of it: see
/// `docs/planning/v1.0.2.md` §16.
library;

export 'package:sqlite3/common.dart';

import 'package:sqlite3/common.dart';

import 'sqlite_backend_native.dart'
    if (dart.library.js_interop) 'sqlite_backend_web.dart';

/// Get the SQLite implementation ready. Call once, before any [openSqliteFile].
///
/// A no-op on native, where the library is linked by `sqlite3_flutter_libs`
/// and loaded on first use. On the web this fetches and instantiates
/// `sqlite3.wasm`, which is why it is async and why it is called from `main`
/// rather than from the first `open`.
Future<void> initSqlite() => platformInitSqlite();

/// Open (or create) the database at [path].
///
/// On the web [path] names a file in an in-memory filesystem rather than on
/// disk; see the library comment.
CommonDatabase openSqliteFile(String path) => platformOpenSqliteFile(path);

/// A scratch database with no file behind it. Used by the SQL code block.
CommonDatabase openSqliteInMemory() => platformOpenSqliteInMemory();

/// Point `package:sqlite3` at a specific shared library.
///
/// A development and test door: an isolate gets a fresh set of statics, so a
/// spawned worker has to be told again where the library is. A no-op on the
/// web, where there is no library to point at — and harmless there, because
/// the callers that use it pass a path they only have on a desktop.
void useSqliteLibraryAt(String path) => platformUseSqliteLibraryAt(path);

/// True when the backend can be told where its library lives — i.e. when
/// [useSqliteLibraryAt] does something. Lets a caller skip assembling a path
/// it cannot use.
bool get sqliteLibraryIsSelectable => platformSqliteLibraryIsSelectable;
