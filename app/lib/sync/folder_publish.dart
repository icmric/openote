/// **Putting a notebook that lives on this phone into a Drive folder.**
///
/// The other half of opening one from a folder: a notebook made on the phone has
/// its logs and pictures in the phone's own directory, and nothing in any Drive.
/// This makes a folder for it inside the folder the person picked
/// (`<title>.onotebook`, the same shape the computer makes) and fills it, once.
/// From then on the ordinary push keeps it up to date.
///
/// **The rules are the push's, adapted to making something new:**
///
///  * It only ever creates. A file is written only when the folder does not
///    already have one of that name; nothing is replaced, moved or deleted.
///  * It never writes into a folder it did not make for this notebook. A folder
///    whose `manifest.json` names this very notebook is this notebook's (an
///    earlier try that was interrupted), and is filled in where it is missing
///    things; any other folder with the same name is left alone and a free name
///    is used.
///  * The picked folder must not itself be a notebook.
///  * Only pictures whose bytes are their name leave the phone.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../core/open_target.dart'
    show notebookFolderExtension, notebookPointerFileName, notebookPointerText;
import '../store/notebook_writer.dart' show sha256Hex;
import 'saf_folder.dart';

/// Something to say to the person in words, rather than a stack: the folder they
/// picked cannot be used, and why.
class PublishProblem implements Exception {
  const PublishProblem(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Where the notebook ended up.
class PublishedFolder {
  const PublishedFolder(
      {required this.root, required this.name, required this.alreadyThere});

  /// The new folder's document id inside the picked tree.
  final String root;

  /// Its name, `<title>.onotebook`.
  final String name;

  /// True when an earlier, interrupted try had already made it.
  final bool alreadyThere;
}

/// A folder name that is safe on every system a Drive folder reaches: no path
/// characters, no leading or trailing dots or spaces, not a name Windows
/// reserves, and not absurdly long. Never empty.
String safeFolderName(String title) {
  var s = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  s = s.replaceFirst(RegExp(r'^\.+'), '').trim();
  s = s.replaceFirst(RegExp(r'[. ]+$'), '');
  if (s.runes.length > 80) {
    s = String.fromCharCodes(s.runes.take(80)).trim();
  }
  if (s.isEmpty) s = 'Notebook';
  if (RegExp(r'^(con|prn|aux|nul|com\d|lpt\d)$', caseSensitive: false)
      .hasMatch(s)) {
    s = '$s notebook';
  }
  return s;
}

final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

/// Make (or find, if an earlier try made it) the notebook's folder inside
/// [picked] and fill in whatever it does not have yet: the manifest, every log in
/// [logDir]`/ops`, the pictures in [logDir]`/blobs`, and the pointer file.
///
/// [manifest] is written as `manifest.json` when the folder has none; it carries
/// [notebookId], which is how a later try (and the other devices) know this
/// folder is this notebook. Throws [PublishProblem] for a folder that cannot be
/// used and anything else for a folder that cannot be reached; whatever was
/// written stays written, and a second call carries on from there.
Future<PublishedFolder> publishNotebookToFolder(
  FolderApi picked, {
  required Directory logDir,
  required String title,
  required String notebookId,
  required Map<String, dynamic> manifest,
  void Function(String stage)? onStage,
}) async {
  onStage?.call('Looking at the folder…');
  final top = await picked.list();
  if (top.any((e) => e.dir && e.name == 'ops')) {
    throw const PublishProblem(
        'That folder is already a notebook. Choose the folder it sits in, or a '
        'different one.');
  }

  final base = safeFolderName(title);
  const ext = notebookFolderExtension;

  // Made by an earlier, interrupted try? Looked for by name first (cheap), then
  // confirmed by what its manifest says it is.
  var checked = 0;
  for (final e in top) {
    if (!e.dir || checked >= 8) continue;
    final n = e.name.toLowerCase();
    if (!n.endsWith(ext) || !n.startsWith(base.toLowerCase())) continue;
    checked++;
    if (await _manifestId(picked, e.id) == notebookId) {
      await _fill(picked, e.id, logDir, manifest, title, onStage);
      return PublishedFolder(root: e.id, name: e.name, alreadyThere: true);
    }
  }

  // A name nobody has, however the provider folds case.
  final taken = {for (final e in top) e.name.toLowerCase()};
  var name = '$base$ext';
  for (var i = 2; taken.contains(name.toLowerCase()) && i < 200; i++) {
    name = '$base ($i)$ext';
  }
  if (taken.contains(name.toLowerCase())) {
    throw const PublishProblem(
        'That folder already has too many notebooks with this name. Choose '
        'another folder.');
  }

  onStage?.call('Making the notebook folder…');
  final id = await picked.makeDir(name: name);
  await _fill(picked, id, logDir, manifest, title, onStage);
  return PublishedFolder(root: id, name: name, alreadyThere: false);
}

Future<String?> _manifestId(FolderApi folder, String dirId) async {
  try {
    final kids = await folder.list(doc: dirId);
    final mf = kids.where((e) => !e.dir && e.name == 'manifest.json').firstOrNull;
    if (mf == null) return null;
    final j = jsonDecode(utf8.decode(await folder.read(mf.id)));
    final id = j is Map ? j['notebookId'] : null;
    return id is String ? id : null;
  } catch (_) {
    return null;
  }
}

Future<void> _fill(
  FolderApi f,
  String rootId,
  Directory logDir,
  Map<String, dynamic> manifest,
  String title,
  void Function(String stage)? onStage,
) async {
  final kids = await f.list(doc: rootId);
  bool hasFile(String n) => kids.any((e) => !e.dir && e.name == n);
  String? dirId(String n) =>
      kids.where((e) => e.dir && e.name == n).firstOrNull?.id;

  // The manifest first: it is what says whose folder this is.
  if (!hasFile('manifest.json')) {
    await f.write(
        parent: rootId,
        name: 'manifest.json',
        bytes: Uint8List.fromList(utf8.encode(
            const JsonEncoder.withIndent('  ').convert(manifest))));
  }

  // Every log there is, each only if the folder does not have it.
  onStage?.call('Sending the notes…');
  final opsId = dirId('ops') ?? await f.makeDir(parent: rootId, name: 'ops');
  final there = {
    for (final e in await f.list(doc: opsId))
      if (!e.dir) e.name
  };
  final opsDir = Directory(p.join(logDir.path, 'ops'));
  if (opsDir.existsSync()) {
    final logs = [
      for (final e in opsDir.listSync())
        if (e is File && e.path.endsWith('.oplog')) e
    ]..sort((a, b) => a.path.compareTo(b.path));
    for (final log in logs) {
      final n = p.basename(log.path);
      if (there.contains(n)) continue;
      await f.write(parent: opsId, name: n, bytes: log.readAsBytesSync());
    }
  }

  // The pictures, each only if its bytes are what its name says.
  final blobsDir = Directory(p.join(logDir.path, 'blobs'));
  if (blobsDir.existsSync()) {
    final local = [
      for (final e in blobsDir.listSync())
        if (e is File &&
            e.path.endsWith('.blob') &&
            _hex64.hasMatch(p.basenameWithoutExtension(e.path)))
          e
    ];
    if (local.isNotEmpty) {
      final blobsId =
          dirId('blobs') ?? await f.makeDir(parent: rootId, name: 'blobs');
      final have = <String>{
        for (final e in await f.list(doc: blobsId))
          if (!e.dir && e.name.length >= 64) e.name.substring(0, 64)
      };
      var done = 0;
      for (final file in local) {
        done++;
        final hash = p.basenameWithoutExtension(file.path);
        if (have.contains(hash)) continue;
        final bytes = file.readAsBytesSync();
        if (sha256Hex(bytes) != hash) continue;
        onStage?.call('Sending pictures… $done of ${local.length}');
        await f.write(parent: blobsId, name: '$hash.blob', bytes: bytes);
      }
    }
  }

  // The small file a computer double-clicks. Nothing depends on it.
  if (!hasFile(notebookPointerFileName)) {
    try {
      await f.write(
          parent: rootId,
          name: notebookPointerFileName,
          bytes: Uint8List.fromList(utf8.encode(notebookPointerText(title))));
    } catch (_) {}
  }
}
