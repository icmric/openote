// A directory on disk served the way Android's folder picker serves a Drive
// folder: by document id (here, the path relative to the root). Stands in for
// the Drive folder in the tests of opening, sending and putting a notebook in a
// folder.
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'package:openote/sync/saf_folder.dart';

class DirFolder implements FolderApi {
  DirFolder(this.root, {this.allowWrites = false});
  final Directory root;
  final List<String> reads = [];

  /// Off by default: reading a notebook must never write to its folder.
  bool allowWrites;

  /// Make every write fail, as a folder that cannot be reached would.
  bool failWrites = false;

  /// Every file written, relative to the root.
  final List<String> writes = [];

  String _abs(String? doc) =>
      doc == null || doc.isEmpty ? root.path : p.join(root.path, doc);

  @override
  Future<List<SafEntry>> list({String? doc}) async {
    final dir = Directory(_abs(doc));
    return [
      for (final e in dir.listSync())
        SafEntry(
          id: p.relative(e.path, from: root.path),
          name: p.basename(e.path),
          dir: e is Directory,
          size: e is File ? e.lengthSync() : -1,
          modified: 0,
        )
    ];
  }

  @override
  Future<Uint8List> read(String doc) async {
    reads.add(doc);
    return File(_abs(doc)).readAsBytesSync();
  }

  @override
  Future<String> write(
      {String? parent, required String name, required Uint8List bytes}) async {
    if (!allowWrites) {
      throw StateError('the bridge must not write to the folder here');
    }
    if (failWrites) throw StateError('folder not reachable');
    final file = File(p.join(_abs(parent), name));
    file.writeAsBytesSync(bytes);
    final id = p.relative(file.path, from: root.path);
    writes.add(id);
    return id;
  }

  @override
  Future<String> makeDir({String? parent, required String name}) async {
    if (!allowWrites) throw StateError('the bridge must not write to the folder here');
    if (failWrites) throw StateError('folder not reachable');
    final d = Directory(p.join(_abs(parent), name))..createSync(recursive: true);
    return p.relative(d.path, from: root.path);
  }
}
