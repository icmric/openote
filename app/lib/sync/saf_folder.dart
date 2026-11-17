/// A folder the person chose with Android's own folder picker (a Google Drive
/// folder, say), reached by document id rather than by file path.
///
/// **No account, no sign-in, no token in this app.** The picker grants access to
/// ONE folder and what is in it, once, on a system screen; the grant is kept.
/// The Kotlin half is `MainActivity.kt`. Everything here is a thin wrapper, so
/// the rest of the sync code can be tested against a fake of this one class.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SafEntry {
  const SafEntry(
      {required this.id,
      required this.name,
      required this.dir,
      required this.size,
      required this.modified});
  final String id;
  final String name;
  final bool dir;

  /// Bytes, or -1 when the provider does not say.
  final int size;
  final int modified;

  factory SafEntry.fromMap(Map<Object?, Object?> m) => SafEntry(
        id: m['id'] as String,
        name: m['name'] as String,
        dir: m['dir'] as bool,
        size: (m['size'] as num).toInt(),
        modified: (m['modified'] as num).toInt(),
      );
}

/// The operations the bridge needs. An interface so a test can stand in a
/// folder held in memory.
abstract class FolderApi {
  /// The entries directly inside [doc] (the chosen folder itself when null).
  Future<List<SafEntry>> list({String? doc});
  Future<Uint8List> read(String doc);

  /// Create [name] in [parent] (the chosen folder when null), or replace its
  /// whole content if it is there. Returns the file's document id.
  Future<String> write({String? parent, required String name, required Uint8List bytes});
}

/// Whether this build can reach a folder this way at all.
bool get safAvailable =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class SafFolder implements FolderApi {
  SafFolder(this.tree);

  /// The persisted tree URI the picker returned.
  final String tree;

  static const _ch = MethodChannel('org.openote/saf');

  /// Ask the person for a folder. Null when they back out.
  static Future<String?> pick() => _ch.invokeMethod<String>('pickTree');

  @override
  Future<List<SafEntry>> list({String? doc}) async {
    final r = await _ch.invokeMethod<List<Object?>>(
        'list', {'tree': tree, 'doc': doc});
    return [
      for (final e in r ?? const <Object?>[])
        SafEntry.fromMap(e as Map<Object?, Object?>)
    ];
  }

  @override
  Future<Uint8List> read(String doc) async {
    final r = await _ch.invokeMethod<Uint8List>('read', {'tree': tree, 'doc': doc});
    return r ?? Uint8List(0);
  }

  @override
  Future<String> write(
      {String? parent, required String name, required Uint8List bytes}) async {
    final r = await _ch.invokeMethod<String>(
        'write', {'tree': tree, 'parent': parent, 'name': name, 'bytes': bytes});
    return r!;
  }
}
