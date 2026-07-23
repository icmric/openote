/// The seam where the Rust core (onote-core: Loro CRDT via flutter_rust_bridge,
/// ADR-0002) will slot in. Until then, [MirrorEngine] implements the same
/// interface in pure Dart using the File Format Spec's documented
/// "mirror-write mode" (§4). The app depends ONLY on [DocumentEngine];
/// swapping engines must not touch UI or repository call sites.
library;

import '../model/models.dart';
import '../store/repository.dart';

abstract interface class DocumentEngine {
  Future<PageData> loadPage(String notebookId, String pageId);
  Future<void> savePage(
      String notebookId, String pageId, List<Block> blocks, PageProps props);
}

class MirrorEngine implements DocumentEngine {
  MirrorEngine(this.repo);
  final Repository repo;

  @override
  Future<PageData> loadPage(String notebookId, String pageId) async =>
      repo.readPage(notebookId, pageId);

  @override
  Future<void> savePage(String notebookId, String pageId, List<Block> blocks,
          PageProps props) async =>
      repo.writePage(notebookId, pageId, blocks, props);
}
