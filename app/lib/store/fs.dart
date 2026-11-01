/// The filesystem the workspace is stored on.
///
/// On every desktop build this is `dart:io`, re-exported unchanged — so the
/// storage layer runs exactly the code it always ran, and no test of it is
/// testing a stand-in. In a browser build it is `memory_fs.dart`, which keeps
/// the demo's workspace in a map that dies with the tab.
///
/// A file in the storage layer swaps
///
/// ```dart
/// import 'dart:io';
/// ```
///
/// for
///
/// ```dart
/// import 'dart:io' hide Directory, File, FileSystemEntity, FileStat,
///     FileSystemEntityType, FileSystemException;
/// import 'fs.dart';
/// ```
///
/// — `dart:io` stays for the things that are not the filesystem (`Platform`,
/// `Process`, `IOSink`), which compile in a web build and throw only if
/// called. Those are the ones to leave alone and grey out; see
/// `core/capabilities.dart`.
library;

export 'fs_native.dart' if (dart.library.js_interop) 'memory_fs.dart';
