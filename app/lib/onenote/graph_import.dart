/// **Importing a OneNote notebook over the internet, a section at a time.**
///
/// The owner, on why this is not one long wait:
///
/// > *"if the user selects something then has to sit and wait for 30s for a
/// > large notebook to import with nothing happening on the screen and not
/// > being able to do anything it would be a pretty poor experience"*
///
/// So nothing here batches to the end. A section's pages are fetched,
/// converted and **written** before the next section is started, and the write
/// goes through the same `AppState` funnel every other edit does — which means
/// the section appears in the navigator, with its pages in it, the moment it
/// lands. A student watches their notebook arrive rather than watching a
/// spinner, and can open and read the parts that have already come in while
/// the rest is still coming.
///
/// Between every batch the loop yields to the event loop, so typing, scrolling
/// and painting all continue. That is inherited wholesale from the `.onepkg`
/// path, whose own doc comment records what it was like before: *"a first-run
/// user picked their `.onepkg` and watched a frozen app do apparently nothing
/// for a minute. That is the single worst moment the product had."*
///
/// ## Why the network shape is different from the file shape
///
/// The `.onepkg` import runs its writes in a separate isolate, because parsing
/// a five-year notebook is seconds of solid CPU. This is not that: the work is
/// almost entirely **waiting on the network**, and the per-page conversion is
/// cheap. Writing on the UI isolate in small batches is therefore both simpler
/// and better here — it needs no cross-isolate handle, and it is what lets the
/// content appear progressively at all.
library;

import 'dart:async';
import 'dart:typed_data';

import '../export/import_sink.dart';
import '../export/onenote_import.dart';
import '../model/models.dart';
import 'graph_client.dart';
import 'graph_pages.dart';

/// Where a running import has got to. Reported often enough that the card
/// never sits on one sentence for long.
class GraphImportProgress {
  const GraphImportProgress({
    required this.sectionName,
    required this.pagesDone,
    required this.pagesTotal,
    required this.sectionsDone,
    required this.sectionsTotal,
  });

  final String sectionName;
  final int pagesDone;
  final int pagesTotal;
  final int sectionsDone;
  final int sectionsTotal;
}

/// What an import ended up doing.
class GraphImportResult {
  const GraphImportResult({
    required this.pages,
    required this.sections,
    required this.loss,
    required this.firstPageId,
    this.cancelled = false,
  });

  final int pages;
  final int sections;
  final GraphPageLoss loss;
  final String? firstPageId;
  final bool cancelled;
}

/// How many pages are fetched and written before yielding.
///
/// Small on purpose. Each page is a network round trip, so a big batch buys
/// nothing in throughput and costs the responsiveness this whole file exists
/// for — and a smaller batch means a cancel is honoured sooner.
const int kGraphBatchPages = 3;

/// Pull [notebookId] into the notebook behind [sink], writing as it goes.
///
/// [shouldCancel] is asked at every batch boundary, so stopping lands within a
/// page or two rather than at the end of the notebook.
Future<GraphImportResult> importNotebookFromGraph({
  required GraphClient client,
  required String notebookId,
  required ImportSink sink,
  void Function(GraphImportProgress)? onProgress,
  bool Function()? shouldCancel,
  Future<void> Function()? yieldToUi,
}) async {
  final loss = GraphPageLoss();
  final sections = await client.sections(notebookId);
  // The starter section `createNotebook` seeds, remembered so it can go once
  // real content has landed — and only then, so a cancelled import does not
  // leave an empty notebook with nothing in it at all.
  final seeded = sink.nodes();

  final posBase = DateTime.now().millisecondsSinceEpoch;
  var pos = 0;
  String nextPosition() =>
      'a${(posBase + pos++).toString().padLeft(15, '0')}';

  final groupIds = <String, String>{};
  var pagesWritten = 0;
  var sectionsWritten = 0;
  String? firstPageId;
  var cancelled = false;

  for (final section in sections) {
    if (shouldCancel?.call() ?? false) {
      cancelled = true;
      break;
    }
    final pageRefs = await client.pages(section.id);
    if (pageRefs.isEmpty) continue;

    // The section node first, so it appears in the navigator immediately and
    // its pages arrive underneath it rather than all at once at the end.
    String? groupId;
    if (section.groupPath.isNotEmpty) {
      groupId = groupIds.putIfAbsent(
          section.groupPath,
          () => sink
              .node(TreeNode(
                kind: NodeKind.sectionGroup,
                title: section.groupPath.replaceAll('/', ' › '),
                position: nextPosition(),
              ))
              .id);
    }
    final sectionNode = sink.node(TreeNode(
      kind: NodeKind.section,
      parentId: groupId,
      title: importTitleFromName(section.name),
      position: nextPosition(),
    ));

    for (var start = 0; start < pageRefs.length; start += kGraphBatchPages) {
      if (shouldCancel?.call() ?? false) {
        cancelled = true;
        break;
      }
      final end = (start + kGraphBatchPages).clamp(0, pageRefs.length);
      // Fetched OUTSIDE the transaction: these are network round trips, and
      // holding a write transaction open across them would lock the notebook
      // for the duration of somebody's internet connection.
      final ready = <Map<String, dynamic>>[];
      for (var i = start; i < end; i++) {
        final page = await _fetchOnePage(client, pageRefs[i], loss);
        if (page != null) ready.add(page);
      }
      if (ready.isEmpty) continue;

      sink.batch(() {
        for (final page in ready) {
          final id = importOneParsedPage(
              sink, sectionNode.id, page, nextPosition);
          firstPageId ??= id;
        }
        return null;
      });
      pagesWritten += ready.length;

      onProgress?.call(GraphImportProgress(
        sectionName: section.name,
        pagesDone: pagesWritten,
        pagesTotal: 0,
        sectionsDone: sectionsWritten,
        sectionsTotal: sections.length,
      ));
      // The yield that keeps the app usable while this runs.
      await (yieldToUi?.call() ?? Future<void>.delayed(Duration.zero));
    }
    sectionsWritten++;
    if (cancelled) break;
  }

  // Only once something real is in it. A notebook whose starter section was
  // removed and whose import then failed would be empty and confusing.
  if (pagesWritten > 0) {
    for (final n in seeded.where((n) => n.kind == NodeKind.section)) {
      sink.purgeNode(n.id);
    }
  }

  return GraphImportResult(
    pages: pagesWritten,
    sections: sectionsWritten,
    loss: loss,
    firstPageId: firstPageId,
    cancelled: cancelled,
  );
}

/// Fetch and convert one page, or null when it could not be read.
///
/// A page that fails costs that page and nothing else: one unreadable page in
/// a five-year notebook must not end the import that has already brought in
/// four hundred others.
Future<Map<String, dynamic>?> _fetchOnePage(
    GraphClient client, GraphPageRef ref, GraphPageLoss loss) async {
  try {
    final html = await client.pageHtml(ref.id);
    final read = readGraphPage(
      html,
      title: ref.title,
      level: ref.level,
      createdIso: ref.createdIso,
    );
    // Images are separate authenticated fetches, one per picture.
    final bytes = <Uint8List?>[];
    for (final img in read.images) {
      bytes.add(await client.resource(img.url));
    }
    attachImageBytes(read.page, read.images, bytes, read.loss);
    loss
      ..images += read.loss.images
      ..attachments += read.loss.attachments
      ..inkPages += read.loss.inkPages;
    return read.page;
  } on GraphException {
    return null;
  } catch (_) {
    return null;
  }
}
