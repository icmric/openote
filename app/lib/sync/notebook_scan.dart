/// **Finding the notebooks in a folder, so nobody has to know which folder is
/// the notebook.**
///
/// A notebook that is shared through a cloud folder is a directory whose name
/// ends in `.onotebook`, holding an `ops` folder of logs. A person who wants to
/// open one on another device should be able to point at the folder their
/// notebooks live in (or at the notebook itself, or at their whole Drive) and be
/// shown what is in there. Two finders, one for the computer's own files and one
/// for a folder reached through Android's picker, with the same rule for what a
/// notebook looks like.
///
/// **They only look.** Nothing is opened, written or created: a candidate lives
/// in somebody's Drive, and opening anything there to interrogate it can write
/// to it.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'saf_folder.dart';

/// A notebook found in a folder.
class FoundNotebook {
  const FoundNotebook({required this.name, required this.path, this.root});

  /// What to call it: the folder's name without `.onotebook`.
  final String name;

  /// Where it is: a path on a computer, or, on Android, the folder it is in
  /// (the notebook's own folder's document id is [root]).
  final String path;

  /// On Android, the document id of the notebook's own folder inside the chosen
  /// tree, or null when the chosen tree IS the notebook.
  final String? root;
}

String _nameOf(String folderName) => folderName.toLowerCase().endsWith('.onotebook')
    ? folderName.substring(0, folderName.length - '.onotebook'.length)
    : folderName;

bool _skipName(String name) => name.startsWith('.') || name.startsWith(r'$');

// ── On a computer ─────────────────────────────────────────────────────────

/// Does [dir] look like a notebook: it has an `ops` folder of logs.
bool looksLikeNotebookDir(String dir) {
  try {
    return Directory(p.join(dir, 'ops')).existsSync();
  } catch (_) {
    return false;
  }
}

/// The notebooks in [root]: [root] itself if it is one, else those up to
/// [depth] folders below it. Gives up after [budget] folders so a whole Drive is
/// never walked. Never throws: an unreadable folder is skipped.
Future<List<FoundNotebook>> findNotebooksUnder(String root,
    {int depth = 3, int budget = 400}) async {
  final out = <FoundNotebook>[];
  if (looksLikeNotebookDir(root)) {
    return [FoundNotebook(name: _nameOf(p.basename(root)), path: root)];
  }
  var visited = 0;
  var level = <String>[root];
  for (var d = 0; d < depth && level.isNotEmpty; d++) {
    final next = <String>[];
    for (final dir in level) {
      if (visited++ >= budget) return out;
      try {
        await for (final e in Directory(dir).list(followLinks: false)) {
          if (e is! Directory) continue;
          final name = p.basename(e.path);
          if (_skipName(name)) continue;
          if (looksLikeNotebookDir(e.path)) {
            out.add(FoundNotebook(name: _nameOf(name), path: e.path));
          } else {
            next.add(e.path);
          }
        }
      } catch (_) {
        // Offline placeholder, no permission: skip it.
      }
    }
    level = next;
  }
  return out;
}

// ── In a folder reached through Android's picker ──────────────────────────

/// The notebooks in the folder [folder] points at: the folder itself if it is
/// one, else those one or two folders below it. Gives up after [budget]
/// listings (each is a round trip to Drive). Never throws for a folder that
/// cannot be listed; the caller shows the "none found" words.
Future<List<FoundNotebook>> findNotebooksInFolder(FolderApi folder,
    {int depth = 2, int budget = 40, void Function()? onStep}) async {
  var used = 0;
  Future<List<SafEntry>?> list(String? doc) async {
    if (used++ >= budget) return null;
    onStep?.call();
    try {
      return await folder.list(doc: doc);
    } catch (_) {
      return null;
    }
  }

  final top = await list(null);
  if (top == null) return const [];
  if (top.any((e) => e.dir && e.name == 'ops')) {
    return const [FoundNotebook(name: '', path: '')];
  }
  final out = <FoundNotebook>[];
  var level = [
    for (final e in top)
      if (e.dir && !_skipName(e.name)) e
  ];
  for (var d = 0; d < depth && level.isNotEmpty; d++) {
    final next = <SafEntry>[];
    for (final dir in level) {
      final kids = await list(dir.id);
      if (kids == null) return out;
      if (kids.any((e) => e.dir && e.name == 'ops')) {
        out.add(FoundNotebook(name: _nameOf(dir.name), path: dir.name, root: dir.id));
      } else if (d + 1 < depth) {
        next.addAll(kids.where((e) => e.dir && !_skipName(e.name)));
      }
    }
    level = next;
  }
  return out;
}
