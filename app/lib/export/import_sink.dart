/// Where an import's writes go — the seam between "translate a parsed OneNote
/// page" and "put it somewhere".
///
/// **Why this exists.** The translation is the expensive, fiddly, well-tested
/// part: box geometry, in-flow image rewriting, table columns, tags, ink. It
/// must not be written twice. But it now has two destinations that cannot share
/// a receiver:
///
/// - the **app**, for importing one `.one` section into a notebook the user has
///   open, where `AppState` is the funnel every mutation goes through (so the
///   op log records it, undo sees it, the UI notices);
/// - the **writer isolate**, for importing a whole `.onepkg` into a brand-new
///   notebook, where there is no `AppState` at all — no Flutter binding, no
///   Repository, no registry — only a `Database` handle and an op log that
///   nothing else has open.
///
/// Six methods is the whole surface, which is the measure of how little the
/// translation actually needed. Each implementation is a handful of lines; the
/// translation is a few hundred and is written once.
///
/// **Notebook-scoped by construction.** Every method used to take a notebook id
/// as its first argument, threaded through a dozen call sites — a parameter that
/// could be got wrong and, being an id, would be got wrong *silently*, writing
/// an imported page into the wrong notebook. A sink is bound to one notebook
/// when it is made.
library;

import 'dart:typed_data';

import '../model/models.dart';
import '../state/app_state.dart';

abstract class ImportSink {
  /// Nodes already in the notebook. Used to find (and later purge) the starter
  /// section that `createNotebook` seeds.
  List<TreeNode> nodes();

  /// Create or update a node. Returns the stored node.
  TreeNode node(TreeNode n);

  /// Write a page's blocks.
  void page(String pageId, List<Block> blocks, PageProps props);

  /// Store image bytes. Returns the content hash, **without** the `sha256:`
  /// prefix — callers add it where the reference is written.
  String blob(Uint8List bytes, String mime);

  /// Run [body] as ONE transaction. An import writes hundreds of pages; without
  /// this each would pay its own commit.
  T batch<T>(T Function() body);

  /// Hard-delete a node. Used only to clear the seeded starter section, never
  /// on user data.
  void purgeNode(String id);
}

/// The in-app sink: everything goes through `AppState`'s storage facade, so
/// imports are recorded in the op log exactly like any other mutation.
class AppStateImportSink implements ImportSink {
  AppStateImportSink(this.app, this.notebookId);

  final AppState app;
  final String notebookId;

  @override
  List<TreeNode> nodes() => app.importNodes(notebookId);

  @override
  TreeNode node(TreeNode n) => app.importNode(notebookId, n);

  @override
  void page(String pageId, List<Block> blocks, PageProps props) =>
      app.importPage(notebookId, pageId, blocks, props);

  @override
  String blob(Uint8List bytes, String mime) =>
      app.importBlob(notebookId, bytes, mime);

  @override
  T batch<T>(T Function() body) => app.importBatch(notebookId, body);

  @override
  void purgeNode(String id) => app.importPurgeNode(notebookId, id);
}
