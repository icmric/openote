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

/// How many pages are fetched and written at a time.
///
/// Matched to [kGraphBatchRequests], because a batch of pages is now ONE round
/// trip rather than a wave of them: asking for fewer than twenty wastes the
/// request, and asking for more just splits into a second one while delaying
/// the write and the cancel check.
const int kGraphBatchPages = kGraphBatchRequests;

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
  // **Every section's page list up front, together.** Asked for one at a time
  // inside the loop, each was a round trip the student waited through with
  // nothing happening — *"it also seems to take a while when changing
  // sections"*. Fetching them all at once also makes the total known, so the
  // progress can say how far through it is rather than only how far it has
  // got.
  final pageLists = await graphPool<List<GraphPageRef>>([
    for (final section in sections) () => client.pages(section.id),
  ]);
  var pagesTotal = 0;
  for (final list in pageLists) {
    pagesTotal += list.length;
  }
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

  for (var si = 0; si < sections.length; si++) {
    final section = sections[si];
    if (shouldCancel?.call() ?? false) {
      cancelled = true;
      break;
    }
    final pageRefs = pageLists[si];
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
      // **One round trip for the whole batch.** Every page used to be its own
      // request; twenty at a time through `\$batch` is what takes a
      // three-hundred-page notebook from fifty waves of latency to fifteen.
      final slice = pageRefs.sublist(start, end);
      final htmls = await client.pageHtmlMany([for (final r in slice) r.id]);
      final ready = <Map<String, dynamic>>[];
      // Images are still per-picture requests, so they go out together across
      // the whole batch rather than page by page.
      final reads = <GraphPage>[];
      for (var i = 0; i < slice.length; i++) {
        final html = htmls[i];
        if (html == null) continue;
        try {
          reads.add(readGraphPage(
            html,
            title: slice[i].title,
            level: slice[i].level,
            createdIso: slice[i].createdIso,
          ));
        } catch (_) {
          // One page that will not parse costs that page, never the import.
        }
      }
      final wanted = <(GraphPage, GraphImageRef)>[
        for (final r in reads)
          for (final img in r.images) (r, img),
      ];
      final bytes = await graphPool<Uint8List?>([
        for (final (_, img) in wanted) () => client.resource(img.url),
      ]);
      var at = 0;
      for (final r in reads) {
        final mine = <Uint8List?>[];
        for (var k = 0; k < r.images.length; k++) {
          mine.add(bytes[at++]);
        }
        attachImageBytes(r.page, r.images, mine, r.loss);
        loss
          ..images += r.loss.images
          ..attachments += r.loss.attachments
          ..inkPages += r.loss.inkPages;
        ready.add(r.page);
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
        pagesTotal: pagesTotal,
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
