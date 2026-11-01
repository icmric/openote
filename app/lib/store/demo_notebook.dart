/// The notebook the browser demo opens with.
///
/// A visitor arriving at an empty page learns nothing: the canvas looks like a
/// blank rectangle and every feature worth seeing is behind a menu they have
/// no reason to open. So the demo starts with something already on the page,
/// chosen to answer "what is this, and what can it do" in the ten seconds
/// before somebody closes the tab.
///
/// ## It is a real notebook, not code that builds one
///
/// `assets/demo/demo.onote` is an ordinary Openote container. **To change what
/// the demo says, open it in Openote and edit it** — see `assets/demo/README.md`
/// for the two-step loop. Nothing here needs touching, and nobody has to learn
/// a second way of expressing a page.
///
/// The first version of this file built the pages from Dart: a list of
/// `Block(type:, content:)` literals with hand-written coordinates. It worked,
/// and it was the wrong shape. Laying out a canvas is a thing this app is
/// *for*, and doing it by typing `y: 650` and rebuilding to see where the box
/// landed is both slower and worse than dragging it. It also meant the demo's
/// content was the one page in the product that could not be edited in the
/// product.
///
/// ## What it costs
///
/// The container has to reach SQLite, which in a browser means two places:
/// `memory_fs.dart` (so `File(path).existsSync()` and the length checks the
/// registry makes are true) and sqlite3's own in-memory VFS (so the database
/// opens at all). Those are separate stores, so the bytes are written twice.
/// At 94 KB that is not worth a shared-buffer design — but it is worth saying
/// out loud, because a reader who assumes one filesystem will be wrong.
library;

import 'package:flutter/services.dart' show rootBundle;

import '../model/models.dart';
import 'fs.dart';
import 'repository.dart';
import 'sqlite_backend.dart';

/// Where the demo's container is shipped.
const kDemoNotebookAsset = 'assets/demo/demo.onote';

/// What the notebook is called in the sidebar.
///
/// Taken from here rather than from the container's own `notebook_meta`,
/// because the registry is what the sidebar reads and
/// [Repository.adoptWorkspaceNotebook] names a notebook after its file. Keep
/// it in step with the title inside the asset, or the two will disagree in
/// places only one of them is shown.
const kDemoNotebookTitle = 'Welcome to Openote';

/// Put the demo notebook in [repo] and return it.
///
/// Called in place of the empty "My Notebook" a fresh desktop workspace gets.
/// The caller decides; this does not check what platform it is on.
Future<NotebookRef> seedDemoNotebook(Repository repo) async {
  final bytes =
      (await rootBundle.load(kDemoNotebookAsset)).buffer.asUint8List();

  // Inside the workspace folder, because that is what `adoptWorkspaceNotebook`
  // means by "already here": it registers a container where it lies instead of
  // copying it, which is exactly right for a file that arrived as an asset and
  // has nowhere else to be.
  final path = '${repo.workspaceDir.path}/$kDemoNotebookTitle.onote';

  // Both filesystems. See the library comment.
  File(path).writeAsBytesSync(bytes);
  seedSqliteFile(path, bytes);

  return repo.adoptWorkspaceNotebook(path, title: kDemoNotebookTitle);
}
