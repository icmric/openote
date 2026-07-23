/// The seam where the Rust core (onote-core: Loro CRDT via flutter_rust_bridge,
/// ADR-0002) will slot in. The crate exists at `rust/onote_core` and is now
/// **linked at runtime over `dart:ffi`** (see `core/onote_ffi.dart`): when the
/// native library is present the app calls into Rust for the page-mirror
/// **merge** and content **hash** (the latter runs on every save today), and
/// the status bar shows the active engine; when it's absent everything falls
/// back to this pure-Dart [MirrorEngine], which implements the same interface
/// using the File Format Spec's documented "mirror-write mode" (§4). The next
/// step is a `RustEngine` implementing [DocumentEngine] end-to-end; because the
/// app depends ONLY on [DocumentEngine], swapping engines never touches UI or
/// repository call sites.
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
