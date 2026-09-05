/// **Importing a OneNote notebook over the internet, a section at a time.**
///
/// The owner, on why this is not one long wait:
///
/// > *"if the user selects something then has to sit and wait for 30s for a
/// > large notebook to import with nothing happening on the screen and not
/// > being able to do anything it would be a pretty poor experience"*
///
/// So nothing here batches to the end. A section's pages are fetched,
/// converted and **written** before the next section is written, and the write
/// goes through the same `AppState` funnel every other edit does — which means
/// the section appears in the navigator, with its pages in it, the moment it
/// lands. A student watches their notebook arrive rather than watching a
/// spinner, and can read the parts already in while the rest is still coming.
///
/// Between every batch the loop yields to the event loop, so typing, scrolling
/// and painting all continue.
///
/// ## Fetching ahead, writing in order
///
/// The owner again: *"do you recon we could import several sections in
/// paralell too"*. The **fetching** can, and now does — it is all waiting on
/// the network. The **writing** cannot: the sink is a transaction on one
/// isolate, and every node carries a position that decides where it appears,
/// so two sections interleaving their writes would shuffle the notebook.
///
/// So the halves are separated. [kGraphSectionsAhead] sections are in flight
/// while the current one is written, and each is written in its own turn. The
/// progress does jump a little, which the owner accepted in advance — it jumps
/// because the work genuinely is ahead of the display.
///
/// ## Waiting is not hanging
///
/// OneNote throttles by request COUNT, so batching cuts round trips and not
/// throttling, and a notebook of several hundred pages will be asked to slow
/// down. Measured on the real thing: six and a half minutes of reading before
/// the first 429, and a cooldown still in force minutes later. That wait is
/// reported rather than swallowed, because an import that goes quiet for two
/// minutes with no explanation cannot be told from one that has hung.
library;

import 'dart:async';
import 'dart:typed_data';

import '../export/import_sink.dart';
import '../export/onenote_import.dart';
import '../model/models.dart';
import 'graph_client.dart';
import 'graph_pages.dart';

/// Where a running import has got to.
class GraphImportProgress {
  const GraphImportProgress({
    required this.sectionName,
    required this.pagesDone,
    required this.pagesTotal,
    required this.sectionsDone,
    required this.sectionsTotal,
    this.waitingFor,
  });

  final String sectionName;
  final int pagesDone;
  final int pagesTotal;
  final int sectionsDone;
  final int sectionsTotal;

  /// Non-null while Microsoft has asked the app to slow down.
  final Duration? waitingFor;
}

/// What an import ended up doing.
class GraphImportResult {
  const GraphImportResult({
    required this.pages,
    required this.sections,
    required this.loss,
    required this.firstPageId,
    this.cancelled = false,
    this.pageIdsByOneNoteId = const {},
  });

  final int pages;
  final int sections;
  final GraphPageLoss loss;
  final String? firstPageId;
  final bool cancelled;

  /// OneNote's own page GUID to the page written for it.
  ///
  /// The raw material for turning a notebook's cross-references into real
  /// links. It cannot be used DURING the import: a link on the first page
  /// often points at the last, and the import writes progressively on purpose,
  /// so the mapping is only complete once everything has landed.
  final Map<String, String> pageIdsByOneNoteId;
}

/// How many pages are fetched and written at a time.
///
/// Matched to [kGraphBatchRequests], because a batch of pages is ONE round
/// trip rather than a wave of them: asking for fewer than twenty wastes the
/// request, and asking for more just splits into a second one while delaying
/// the write and the cancel check.
const int kGraphBatchPages = kGraphBatchRequests;

/// How many sections are read ahead of the one being written.
///
/// Two rather than ten. What actually bounds parallelism is the client's own
/// request gate, so reading further ahead buys none — it only holds more pages
/// in memory and makes a cancel waste more of them.
const int kGraphSectionsAhead = 2;

/// Pull [notebookId] into the notebook behind [sink], writing as it goes.
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
  // sections"*. It also makes the total known, so progress can say how far
  // through it is rather than only how far it has got.
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
  final oneNoteIds = <String, String>{};
  var pagesWritten = 0;
  var sectionsWritten = 0;
  String? firstPageId;
  var cancelled = false;
  Duration? waiting;

  // One future per section, started ahead of when it is written.
  final ahead = <int, Future<List<ReadyPage>>>{};
  void startFetching(int index) {
    if (index < 0 || index >= sections.length) return;
    if (ahead.containsKey(index) || pageLists[index].isEmpty) return;
    ahead[index] = _readSection(client, pageLists[index], loss, shouldCancel);
  }

  // Reported whenever the client starts waiting on a throttle, so a two-minute
  // pause reads as a pause rather than as a freeze.
  client.onThrottle = (d) {
    waiting = d;
    onProgress?.call(GraphImportProgress(
      sectionName: '',
      pagesDone: pagesWritten,
      pagesTotal: pagesTotal,
      sectionsDone: sectionsWritten,
      sectionsTotal: sections.length,
      waitingFor: d,
    ));
  };

  try {
    for (var i = 0; i <= kGraphSectionsAhead; i++) {
      startFetching(i);
    }

    for (var si = 0; si < sections.length; si++) {
      if (shouldCancel?.call() ?? false) {
        cancelled = true;
        break;
      }
      final section = sections[si];
      final pending = ahead.remove(si);
      if (pending == null) continue;
      // Keep the pipe full while this one is written.
      startFetching(si + kGraphSectionsAhead + 1);

      final ready = await pending;
      if (ready.isEmpty) continue;

      // The section node first, so it appears in the navigator with its pages
      // arriving underneath it.
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

      for (var start = 0; start < ready.length; start += kGraphBatchPages) {
        if (shouldCancel?.call() ?? false) {
          cancelled = true;
          break;
        }
        final end = (start + kGraphBatchPages).clamp(0, ready.length);
        sink.batch(() {
          for (var i = start; i < end; i++) {
            final id = importOneParsedPage(
                sink, sectionNode.id, ready[i].page, nextPosition);
            firstPageId ??= id;
            final guid = ready[i].oneNoteId;
            if (guid != null) oneNoteIds[guid] = id;
          }
          return null;
        });
        pagesWritten += end - start;
        onProgress?.call(GraphImportProgress(
          sectionName: section.name,
          pagesDone: pagesWritten,
          pagesTotal: pagesTotal,
          sectionsDone: sectionsWritten,
          sectionsTotal: sections.length,
          waitingFor: waiting,
        ));
        // The yield that keeps the app usable while this runs.
        await (yieldToUi?.call() ?? Future<void>.delayed(Duration.zero));
      }
      sectionsWritten++;
      if (cancelled) break;
    }
  } finally {
    client.onThrottle = null;
    // Sections read ahead of a cancel are abandoned, but their futures are
    // live and an unawaited error surfaces later somewhere unrelated.
    for (final f in ahead.values) {
      unawaited(f.then((_) {}, onError: (Object _) {}));
    }
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
    pageIdsByOneNoteId: oneNoteIds,
  );
}

/// A converted page, and the OneNote id its neighbours link to it by.
class ReadyPage {
  const ReadyPage(this.page, this.oneNoteId);
  final Map<String, dynamic> page;
  final String? oneNoteId;
}

/// Everything a section needs before any of it can be written.
///
/// Runs entirely off the network and touches the sink not at all, which is
/// what lets several of these be in flight at once while the writing stays
/// strictly in order.
Future<List<ReadyPage>> _readSection(
  GraphClient client,
  List<GraphPageRef> refs,
  GraphPageLoss loss,
  bool Function()? shouldCancel,
) async {
  final out = <ReadyPage>[];
  for (var start = 0; start < refs.length; start += kGraphBatchPages) {
    if (shouldCancel?.call() ?? false) break;
    final end = (start + kGraphBatchPages).clamp(0, refs.length);
    final slice = refs.sublist(start, end);
    // **One round trip for the whole batch.** Every page used to be its own
    // request; twenty at a time through `$batch` is what takes a
    // three-hundred-page notebook from fifty waves of latency to fifteen.
    final htmls = await client.pageHtmlMany([for (final r in slice) r.id]);

    final reads = <GraphPage>[];
    final ids = <String?>[];
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
        ids.add(slice[i].oneNoteId);
      } catch (_) {
        // One page that will not parse costs that page, never the import.
      }
    }

    // Pictures and attachments are separate authenticated requests, so they
    // go out together across the whole batch rather than page by page.
    final wanted = <GraphImageRef>[for (final r in reads) ...r.images];
    final bytes = await graphPool<Uint8List?>([
      for (final img in wanted) () => client.resource(img.url),
    ]);
    final wantedFiles = <GraphFileRef>[for (final r in reads) ...r.files];
    final fileBytes = await graphPool<Uint8List?>([
      for (final f in wantedFiles) () => client.resource(f.url),
    ]);
    var at = 0;
    var fileAt = 0;
    for (final r in reads) {
      final mine = <Uint8List?>[];
      for (var k = 0; k < r.images.length; k++) {
        mine.add(bytes[at++]);
      }
      final myFiles = <Uint8List?>[];
      for (var k = 0; k < r.files.length; k++) {
        myFiles.add(fileBytes[fileAt++]);
      }
      attachFileBytes(r.page, r.files, myFiles, r.loss);
      attachImageBytes(r.page, r.images, mine, r.loss);
      final which = reads.indexOf(r);
      loss
        ..images += r.loss.images
        ..attachments += r.loss.attachments
        ..inkPages += r.loss.inkPages;
      out.add(ReadyPage(r.page, which < ids.length ? ids[which] : null));
    }
  }
  return out;
}
