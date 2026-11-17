/// **Where a file goes when the person saves or exports something.**
///
/// On a computer that is the system's Save dialog, which gives a path to write
/// to. Android has no such dialog for an ordinary app (the plugin that supplies
/// it throws there), and no path that `dart:io` could write through either: its
/// own Save-as screen hands back a document address. That screen is the right
/// one to use (it can save to Google Drive as well as to the phone), so on
/// Android the export is written into a private staging folder and then handed
/// over to it:
///
///  1. [chooseSaveLocation] gives a path inside a staging folder. The caller
///     writes its file(s) there exactly as it would anywhere.
///  2. [finishSave] opens the system Save-as screen with what was written (a
///     single file as it is, several files zipped) and returns what to tell the
///     person, or null if they backed out.
///
/// Everywhere else [finishSave] returns the path unchanged, so a caller can use
/// the pair without asking what it is running on.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../sync/saf_folder.dart' show safAvailable;

/// Where the caller should write. A path and nothing else, so it reads the same
/// as the dialog's own result did.
class SaveSpot {
  const SaveSpot(this.path);
  final String path;
}

const _channel = MethodChannel('org.openote/saf');
const _stagingPrefix = 'save-';

/// Ask where to save a file called [suggestedName]. Null if the person backs out.
Future<SaveSpot?> chooseSaveLocation(
    {String? suggestedName, List<XTypeGroup>? acceptedTypeGroups}) async {
  if (!safAvailable) {
    final loc = await getSaveLocation(
        suggestedName: suggestedName, acceptedTypeGroups: acceptedTypeGroups ?? const <XTypeGroup>[]);
    return loc == null ? null : SaveSpot(loc.path);
  }
  final dir = await _newStagingDir();
  return SaveSpot(p.join(dir.path, suggestedName ?? 'openote'));
}

/// Ask for a folder to write a whole tree into. On Android that is the staging
/// folder, delivered as one zip by [finishSave].
Future<String?> chooseExportFolder({String? confirmButtonText}) async {
  if (!safAvailable) {
    return getDirectoryPath(confirmButtonText: confirmButtonText);
  }
  return (await _newStagingDir()).path;
}

Future<Directory> _newStagingDir() async {
  final tmp = await getTemporaryDirectory();
  final dir = Directory(
      p.join(tmp.path, '$_stagingPrefix${DateTime.now().microsecondsSinceEpoch}'));
  await dir.create(recursive: true);
  return dir;
}

/// The staging folder [path] is in, or null if it is not in one.
Directory? _stagingOf(String path) {
  var cur = p.dirname(p.normalize(path));
  for (var i = 0; i < 8; i++) {
    if (p.basename(cur).startsWith(_stagingPrefix)) return Directory(cur);
    final up = p.dirname(cur);
    if (up == cur) break;
    cur = up;
  }
  // The path may BE the staging folder (a whole-tree export).
  final self = p.normalize(path);
  return p.basename(self).startsWith(_stagingPrefix) ? Directory(self) : null;
}

/// Hand what was written at [path] to the system Save-as screen (Android), or
/// do nothing (elsewhere). Returns what to name in the "Saved" message: the
/// path as given, or on Android the name of the file, or null if cancelled.
///
/// Never throws for a person backing out; a real failure does throw, so the
/// caller's own "that didn't save" message can say so.
Future<String?> finishSave(String? path) async {
  if (path == null) return null;
  if (!safAvailable) return path;
  final staging = _stagingOf(path);
  if (staging == null || !staging.existsSync()) return path;
  try {
    final files = [
      for (final e in staging.listSync(recursive: true))
        if (e is File) e
    ];
    if (files.isEmpty) return null;
    String name;
    String mime;
    Uint8List bytes;
    if (files.length == 1) {
      name = p.basename(files.single.path);
      mime = _mimeFor(name);
      bytes = await files.single.readAsBytes();
    } else {
      // A page with pictures, or a whole notebook: one zip, with the same
      // layout the folder would have had.
      final base = p.basename(path) == p.basename(staging.path)
          ? 'openote-export'
          : p.basenameWithoutExtension(path);
      name = '$base.zip';
      mime = 'application/zip';
      final zip = ZipEncoder();
      final archive = Archive();
      for (final f in files) {
        final rel = p.relative(f.path, from: staging.path).replaceAll('\\', '/');
        final data = await f.readAsBytes();
        archive.addFile(ArchiveFile(rel, data.length, data));
      }
      bytes = Uint8List.fromList(zip.encode(archive));
    }
    final saved = await _channel.invokeMethod<String>(
        'saveFile', {'name': name, 'mime': mime, 'bytes': bytes});
    return saved == null ? null : name;
  } finally {
    try {
      staging.deleteSync(recursive: true);
    } catch (_) {}
  }
}

String _mimeFor(String name) => switch (p.extension(name).toLowerCase()) {
      '.pdf' => 'application/pdf',
      '.md' => 'text/markdown',
      '.txt' => 'text/plain',
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      '.svg' => 'image/svg+xml',
      '.zip' => 'application/zip',
      _ => 'application/octet-stream',
    };
