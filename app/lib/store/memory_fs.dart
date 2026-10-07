/// A filesystem that exists only in this tab, for the browser demo.
///
/// ## Why this is here and not `package:file`
///
/// `package:file` has a perfectly good `MemoryFileSystem`, but its entities
/// are made with `fs.file(path)` rather than `File(path)`. Adopting it would
/// mean rewriting every call site in the storage layer — about 230 of them,
/// most in `repository.dart`, which is the class a corrupted container is
/// written through. That is a large, risky edit to the most dangerous code in
/// the app, in exchange for a demo.
///
/// This file instead provides classes **named** `Directory` and `File` with
/// the same constructors, so a storage file swaps
///
/// ```dart
/// import 'dart:io';
/// ```
///
/// for `import 'fs.dart';` and nothing else changes. On a desktop build
/// `fs.dart` re-exports `dart:io` itself, so the native path is not merely
/// equivalent — it is the same code it has always been, and no test of it is
/// testing a replacement.
///
/// ## What it is not
///
/// Not a general-purpose filesystem, and it should never grow into one. It
/// serves the operations the workspace boot path actually performs; anything
/// else throws [UnimplementedError] rather than returning a plausible lie,
/// because a silent wrong answer here is a notebook that looks saved. If you
/// reach one, the honest fix is usually to grey the feature out rather than to
/// implement another method — see `core/capabilities.dart`.
///
/// Notably absent: `openWrite`/`openRead` (used only by `media_store.dart`,
/// which copies a picked file in from disk and is greyed out in the demo) and
/// a working [Directory.watch], which is the one no browser can ever provide
/// and the reason folder sync does not port. See `workspace_fs.dart`.
///
/// ## Lifetime
///
/// One map, one tab, no persistence of any kind. Refreshing the page is a new
/// machine. That is the demo's defining property; see
/// `docs/planning/v1.0.2.md` §16.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Every file in the world, by normalised absolute path.
final Map<String, Uint8List> _files = {};

/// Every directory, likewise. Held explicitly so that an empty directory
/// exists — `listSync` on one must return `[]`, not throw.
final Set<String> _dirs = {'/'};

final Map<String, DateTime> _modified = {};

/// Wipe everything. For tests, and for nothing else: the app has no reason to
/// ask, because the only way to clear a browser demo is to reload it.
void debugResetMemoryFs() {
  _files.clear();
  _dirs
    ..clear()
    ..add('/');
  _modified.clear();
}

/// Collapse a path to one spelling, so that `a/b`, `a\b`, `a//b` and `a/b/`
/// are the same key.
///
/// Windows separators are accepted because `package:path` is configured by the
/// platform and some paths in the storage layer are assembled before anyone
/// knows where they will be used.
String _norm(String path) {
  var s = path.replaceAll('\\', '/');
  if (!s.startsWith('/')) s = '/$s';
  final out = <String>[];
  for (final part in s.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (out.isNotEmpty) out.removeLast();
      continue;
    }
    out.add(part);
  }
  return '/${out.join('/')}';
}

String _parentOf(String normalised) {
  final i = normalised.lastIndexOf('/');
  return i <= 0 ? '/' : normalised.substring(0, i);
}

void _mkdirs(String normalised) {
  final parts = normalised.split('/').where((p) => p.isNotEmpty);
  var at = '';
  _dirs.add('/');
  for (final part in parts) {
    at = '$at/$part';
    _dirs.add(at);
  }
}

class FileSystemEntityType {
  const FileSystemEntityType._(this._name);
  final String _name;

  static const file = FileSystemEntityType._('file');
  static const directory = FileSystemEntityType._('directory');
  static const notFound = FileSystemEntityType._('notFound');
  static const link = FileSystemEntityType._('link');

  @override
  String toString() => _name;
}

class FileStat {
  FileStat._(this.type, this.size, this.modified);

  final FileSystemEntityType type;
  final int size;
  final DateTime modified;

  DateTime get changed => modified;
  DateTime get accessed => modified;
  int get mode => 0x1a4; // 0644, for anything that prints it
  String modeString() => 'rw-r--r--';
}

/// Stands in for `dart:io`'s, so that `e.osError?.errorCode` keeps compiling.
/// Always null here: there is no operating system underneath to have an
/// opinion, and `repository.dart` already treats a null code as "no detail".
class OSError {
  const OSError([this.message = '', this.errorCode = 0]);
  final String message;
  final int errorCode;
}

/// The subset of `dart:io`'s modes the storage layer names.
class FileMode {
  const FileMode._(this._name);
  final String _name;

  static const read = FileMode._('read');
  static const write = FileMode._('write');
  static const append = FileMode._('append');
  static const writeOnly = FileMode._('writeOnly');
  static const writeOnlyAppend = FileMode._('writeOnlyAppend');

  bool get _truncates => this == write || this == writeOnly;

  @override
  String toString() => _name;
}

class FileSystemException implements Exception {
  const FileSystemException([this.message = '', this.path, this.osError]);
  final String message;
  final String? path;
  final OSError? osError;

  @override
  String toString() =>
      'FileSystemException: $message${path == null ? '' : ', path = \'$path\''}';
}

abstract class FileSystemEntity {
  String get path;

  String get _key => _norm(path);

  Directory get parent => Directory(_parentOf(_key));

  bool existsSync();

  Future<bool> exists() async => existsSync();

  FileStat statSync() {
    final k = _key;
    if (_files.containsKey(k)) {
      return FileStat._(FileSystemEntityType.file, _files[k]!.length,
          _modified[k] ?? DateTime.now());
    }
    if (_dirs.contains(k)) {
      return FileStat._(
          FileSystemEntityType.directory, 0, _modified[k] ?? DateTime.now());
    }
    return FileStat._(
        FileSystemEntityType.notFound, 0, DateTime.fromMillisecondsSinceEpoch(0));
  }

  Future<FileStat> stat() async => statSync();

  DateTime lastModifiedSync() => statSync().modified;

  static FileSystemEntityType typeSync(String path, {bool followLinks = true}) {
    final k = _norm(path);
    if (_files.containsKey(k)) return FileSystemEntityType.file;
    if (_dirs.contains(k)) return FileSystemEntityType.directory;
    return FileSystemEntityType.notFound;
  }

  static bool isDirectorySync(String path) =>
      typeSync(path) == FileSystemEntityType.directory;

  static bool isFileSync(String path) =>
      typeSync(path) == FileSystemEntityType.file;

  static Future<bool> isDirectory(String path) async => isDirectorySync(path);

  static Future<bool> isFile(String path) async => isFileSync(path);

  @override
  String toString() => "$runtimeType: '$path'";
}

class File extends FileSystemEntity {
  File(this.path);

  @override
  final String path;

  File get absolute => File(_key);

  @override
  bool existsSync() => _files.containsKey(_key);

  File createSync({bool recursive = false, bool exclusive = false}) {
    final k = _key;
    if (recursive) _mkdirs(_parentOf(k));
    _files.putIfAbsent(k, () => Uint8List(0));
    _modified[k] = DateTime.now();
    return this;
  }

  Future<File> create({bool recursive = false, bool exclusive = false}) async =>
      createSync(recursive: recursive, exclusive: exclusive);

  Uint8List readAsBytesSync() {
    final b = _files[_key];
    if (b == null) {
      throw FileSystemException('Cannot open file, no such file', path);
    }
    return b;
  }

  Future<Uint8List> readAsBytes() async => readAsBytesSync();

  String readAsStringSync({Encoding encoding = utf8}) =>
      encoding.decode(readAsBytesSync());

  Future<String> readAsString({Encoding encoding = utf8}) async =>
      readAsStringSync(encoding: encoding);

  List<String> readAsLinesSync({Encoding encoding = utf8}) =>
      const LineSplitter().convert(readAsStringSync(encoding: encoding));

  File writeAsBytesSync(List<int> bytes,
      {bool flush = false, bool mode = false}) {
    final k = _key;
    _mkdirs(_parentOf(k));
    _files[k] = Uint8List.fromList(bytes);
    _modified[k] = DateTime.now();
    return this;
  }

  Future<File> writeAsBytes(List<int> bytes, {bool flush = false}) async =>
      writeAsBytesSync(bytes, flush: flush);

  File writeAsStringSync(String contents,
          {bool flush = false, Encoding encoding = utf8}) =>
      writeAsBytesSync(encoding.encode(contents), flush: flush);

  Future<File> writeAsString(String contents,
          {bool flush = false, Encoding encoding = utf8}) async =>
      writeAsStringSync(contents, flush: flush, encoding: encoding);

  void deleteSync({bool recursive = false}) {
    _files.remove(_key);
    _modified.remove(_key);
  }

  Future<File> delete({bool recursive = false}) async {
    deleteSync(recursive: recursive);
    return this;
  }

  File renameSync(String newPath) {
    final from = _key, to = _norm(newPath);
    final b = _files.remove(from);
    if (b == null) {
      throw FileSystemException('Cannot rename file, no such file', path);
    }
    _mkdirs(_parentOf(to));
    _files[to] = b;
    _modified[to] = _modified.remove(from) ?? DateTime.now();
    return File(newPath);
  }

  Future<File> rename(String newPath) async => renameSync(newPath);

  File copySync(String newPath) {
    final to = _norm(newPath);
    _mkdirs(_parentOf(to));
    _files[to] = Uint8List.fromList(readAsBytesSync());
    _modified[to] = DateTime.now();
    return File(newPath);
  }

  Future<File> copy(String newPath) async => copySync(newPath);

  RandomAccessFile openSync({FileMode mode = FileMode.read}) {
    if (mode == FileMode.read && !existsSync()) {
      throw FileSystemException('Cannot open file, no such file', path);
    }
    return RandomAccessFile._(_key, mode);
  }

  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      openSync(mode: mode);

  int lengthSync() => readAsBytesSync().length;

  Future<int> length() async => lengthSync();
}

/// A positioned handle on a file.
///
/// Not an optional corner: the op log reads itself in windows and appends
/// through one of these, so this is how every edit in the demo is recorded.
///
/// Writes land in the map on each call rather than being buffered, so
/// `flushSync` has nothing to do and a handle that is never closed still
/// leaves the file correct — which is the opposite of the real one's
/// behaviour, and safer in the only direction that matters here.
class RandomAccessFile {
  RandomAccessFile._(this._key, FileMode mode) {
    if (mode._truncates || !_files.containsKey(_key)) {
      _mkdirs(_parentOf(_key));
      _files[_key] = Uint8List(0);
    }
    _position = (mode == FileMode.append || mode == FileMode.writeOnlyAppend)
        ? _files[_key]!.length
        : 0;
  }

  final String _key;
  int _position = 0;

  Uint8List get _bytes => _files[_key] ?? Uint8List(0);

  int lengthSync() => _bytes.length;
  Future<int> length() async => lengthSync();

  int positionSync() => _position;
  Future<int> position() async => _position;

  RandomAccessFile setPositionSync(int to) {
    _position = to;
    return this;
  }

  Future<RandomAccessFile> setPosition(int to) async => setPositionSync(to);

  Uint8List readSync(int count) {
    final b = _bytes;
    final from = _position.clamp(0, b.length);
    final to = (from + count).clamp(0, b.length);
    _position = to;
    return Uint8List.fromList(b.sublist(from, to));
  }

  Future<Uint8List> read(int count) async => readSync(count);

  RandomAccessFile writeFromSync(List<int> buffer) {
    final old = _bytes;
    final end = _position + buffer.length;
    final out = Uint8List(end > old.length ? end : old.length)
      ..setAll(0, old)
      ..setAll(_position, buffer);
    _files[_key] = out;
    _modified[_key] = DateTime.now();
    _position = end;
    return this;
  }

  Future<RandomAccessFile> writeFrom(List<int> buffer) async =>
      writeFromSync(buffer);

  RandomAccessFile writeStringSync(String s, {Encoding encoding = utf8}) =>
      writeFromSync(encoding.encode(s));

  Future<RandomAccessFile> writeString(String s,
          {Encoding encoding = utf8}) async =>
      writeStringSync(s, encoding: encoding);

  void flushSync() {}
  Future<void> flush() async {}

  void closeSync() {}
  Future<void> close() async {}
}

class Directory extends FileSystemEntity {
  Directory(this.path);

  @override
  final String path;

  Directory get absolute => Directory(_key);

  /// There is no system temp directory in a tab. A name under the root is
  /// enough for the one thing that asks: somewhere scratch to put a file.
  static Directory get systemTemp => Directory('/tmp');

  @override
  bool existsSync() => _dirs.contains(_key);

  Directory createSync({bool recursive = false}) {
    _mkdirs(_key);
    return this;
  }

  Future<Directory> create({bool recursive = false}) async =>
      createSync(recursive: recursive);

  Directory createTempSync([String? prefix]) {
    final d = Directory(
        '${_key}/${prefix ?? 'tmp'}${DateTime.now().microsecondsSinceEpoch}');
    return d.createSync(recursive: true);
  }

  Future<Directory> createTemp([String? prefix]) async => createTempSync(prefix);

  List<FileSystemEntity> listSync(
      {bool recursive = false, bool followLinks = true}) {
    final root = _key;
    if (!_dirs.contains(root)) {
      throw FileSystemException('Directory listing failed, no such directory',
          path);
    }
    final prefix = root == '/' ? '/' : '$root/';
    final out = <FileSystemEntity>[];
    bool wanted(String k) {
      if (!k.startsWith(prefix) || k == root) return false;
      return recursive || !k.substring(prefix.length).contains('/');
    }

    for (final k in _dirs) {
      if (wanted(k)) out.add(Directory(k));
    }
    for (final k in _files.keys) {
      if (wanted(k)) out.add(File(k));
    }
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }

  Stream<FileSystemEntity> list(
          {bool recursive = false, bool followLinks = true}) =>
      Stream.fromIterable(
          listSync(recursive: recursive, followLinks: followLinks));

  void deleteSync({bool recursive = false}) {
    final root = _key;
    if (!recursive) {
      _dirs.remove(root);
      return;
    }
    final prefix = root == '/' ? '/' : '$root/';
    _files.removeWhere((k, _) => k == root || k.startsWith(prefix));
    _dirs.removeWhere((k) => k == root || k.startsWith(prefix));
  }

  Future<Directory> delete({bool recursive = false}) async {
    deleteSync(recursive: recursive);
    return this;
  }

  Directory renameSync(String newPath) {
    final from = _key, to = _norm(newPath);
    final prefix = '$from/';
    for (final k in _files.keys.toList()) {
      if (k == from || k.startsWith(prefix)) {
        _files[to + k.substring(from.length)] = _files.remove(k)!;
      }
    }
    for (final k in _dirs.toList()) {
      if (k == from || k.startsWith(prefix)) {
        _dirs
          ..remove(k)
          ..add(to + k.substring(from.length));
      }
    }
    _mkdirs(to);
    return Directory(newPath);
  }

  Future<Directory> rename(String newPath) async => renameSync(newPath);

  /// **Always an empty stream, and this is the honest answer rather than a
  /// gap.** No browser can tell a page that a folder changed underneath it,
  /// on any engine, with any permission. Folder sync is built on exactly this
  /// call — see `sync/folder_watch.dart` — which is why
  /// `Capability.folderSync` is false here and the sync UI is greyed out.
  ///
  /// An empty stream rather than a throw because the caller's contract is "you
  /// will hear about changes", and in a world where nothing outside this tab
  /// can write, hearing about none of them is correct.
  Stream<FileSystemEvent> watch({int events = 0, bool recursive = false}) =>
      const Stream.empty();
}

/// Declared so `sync/folder_watch.dart` keeps compiling, and never
/// constructed: [Directory.watch] here is always an empty stream. See the note
/// on that method for why this is the one capability no browser can supply.
class FileSystemEvent {
  const FileSystemEvent._(this.path);
  final String path;
}

class FileSystemMoveEvent extends FileSystemEvent {
  const FileSystemMoveEvent._(super.path, this.destination) : super._();
  final String? destination;
}
