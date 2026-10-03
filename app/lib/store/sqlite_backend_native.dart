/// The `dart:ffi` half of [sqlite_backend]: the real SQLite, on a real disk.
///
/// `sqlite3_flutter_libs` links the library (FTS5 included, which is why that
/// package is in the pubspec at all) and `package:sqlite3` loads it on first
/// use, so there is nothing to initialise here.
library;

import 'dart:ffi';

import 'package:sqlite3/common.dart';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart';

Future<void> platformInitSqlite() async {}

CommonDatabase platformOpenSqliteFile(String path) => sqlite3.open(path);

CommonDatabase platformOpenSqliteInMemory() => sqlite3.openInMemory();

const bool platformSqliteLibraryIsSelectable = true;

/// `open.overrideForAll` is a static, and statics are per-isolate — so a
/// worker spawned to do import or query work has to be told again where the
/// library is, even though the isolate that spawned it already knew.
void platformUseSqliteLibraryAt(String path) {
  sqlite_open.open.overrideForAll(() => DynamicLibrary.open(path));
}
