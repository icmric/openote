import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/ids.dart';
import '../core/onote_ffi.dart';
import '../model/models.dart';
import '../model/tags.dart';
import '../state/app_state.dart';
import 'import_sink.dart';
import '../ui/onote_dialog.dart';

/// Isolate entry points: the Rust parse (LZX + binary decode + base64) can
/// take seconds on a big notebook and must not freeze the UI thread. Each
/// isolate loads its own copy of the native library on first use.
/// Parse a package AND finish every CPU-heavy byte of post-processing before
/// returning: `jsonDecode` of the (potentially hundreds of MB) result string,
/// and base64 → bytes for every image.
///
/// **Why this exists when `compute(_parseOnepkg…)` already ran the parse off
/// the UI thread.** The old shape returned the JSON *string*, so the decode of
/// that string — seconds, for a big notebook — happened on the UI isolate, and
/// so did a `base64Decode` per image during the write phase. That was most of
/// "the whole app completely locks up while importing". Both now happen here.
/// Returning the decoded *structure* is effectively free: `compute` uses
/// `Isolate.exit`, which hands the result to the caller in O(1) rather than
/// copying it.
///
/// Images are rewritten in place: `data_base64` (String) becomes `bytes`
/// (Uint8List). Consumers accept either spelling, so the old string path —
/// still used by tests driving [buildNotebookFromPackage] directly — keeps
/// working.
Map<String, dynamic> parseOnepkgStructured(Uint8List bytes) {
  final core = OnoteCore.instance;
  if (core == null) throw StateError('core unavailable');
  final result = jsonDecode(core.importOnepkg(bytes)) as Map<String, dynamic>;
  if (result['ok'] == true) {
    for (final s in (result['sections'] as List? ?? const [])) {
      final pages =
          (((s as Map)['section'] as Map?)?['pages'] as List?) ?? const [];
      for (final page in pages) {
        decodePageImagesInPlace((page as Map).cast<String, dynamic>());
      }
    }
  }
  return result;
}

/// Same, for a single `.one` section.
Map<String, dynamic> parseOneStructured(Uint8List bytes) {
  final core = OnoteCore.instance;
  if (core == null) throw StateError('core unavailable');
  final result = jsonDecode(core.importOne(bytes)) as Map<String, dynamic>;
  if (result['ok'] == true) {
    for (final page in (result['pages'] as List? ?? const [])) {
      decodePageImagesInPlace((page as Map).cast<String, dynamic>());
    }
  }
  return result;
}

/// base64 → bytes for every image of one parsed page, in place.
///
/// Part of the parse-side contract, not an internal: both parse entry points
/// above run it, and so does the writer isolate when it is handed an
/// already-parsed package. Doing it here rather than at write time is the point
/// — a `base64Decode` per image on the UI thread was a measurable slice of the
/// old lockup.
void decodePageImagesInPlace(Map<String, dynamic> page) {
  for (final imgRaw in (page['images'] as List? ?? const [])) {
    final img = imgRaw as Map;
    final b64 = img.remove('data_base64') as String?;
    if (b64 == null || b64.isEmpty) continue;
    try {
      img['bytes'] = base64Decode(b64);
    } catch (_) {/* an undecodable image degrades to absent, as before */}
  }
}

/// Show a busy dialog while [work] runs (import feedback for large notebooks).
/// The dialog text tracks [message] live, so multi-phase imports can narrate
/// progress ("Importing section 3 of 12…") as they go.
/// Runs [work] behind a modal progress dialog. **Takes ownership of
/// [message]** and disposes it when the work completes — both call sites
/// hand over a notifier they never touch again, and leaving disposal to them
/// leaked one notifier per import.
Future<T> _withBusyDialog<T>(BuildContext? context,
    ValueNotifier<String> message, Future<T> Function() work) async {
  if (context == null || !context.mounted) {
    try {
      return await work();
    } finally {
      message.dispose();
    }
  }
  showOnoteDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(children: [
        const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.6)),
        const SizedBox(width: 16),
        Expanded(
          child: ValueListenableBuilder<String>(
            valueListenable: message,
            builder: (_, text, __) => Text(text),
          ),
        ),
      ]),
    ),
  );
  try {
    return await work();
  } finally {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    // Dispose only after the dialog is gone — its ValueListenableBuilder is
    // still listening until the route pops.
    message.dispose();
  }
}

/// OneNote import (OPEN-8): `.one` sections and `.onepkg` whole notebooks.
///
/// Powered by the Rust core's reverse-engineered MS-ONESTORE/MS-ONE parser
/// (`onote_core::onenote` / `onote_core::onepkg`). A section brings across its
/// pages' **separate text boxes at true positions** (styled text, lists,
/// in-flow images, highlights), **equations** as math blocks, **floating
/// images**, and **ink strokes** with pressure. Requires the native core to be
/// linked — pure-Dart builds can't parse the binary formats.
///
/// Both entry points return the number of pages imported, 0 if the file had
/// nothing usable, or null if the user cancelled. They throw
/// [OneNoteUnavailable] when the Rust core isn't linked.
class OneNoteUnavailable implements Exception {}

/// OneNote's line pitch, as a multiple of font size.
///
/// **Measured, then explained.** OneNote's own PDF export gives the baseline of
/// every rendered line, so the pitch is readable directly. Fitting a grid to all
/// the line steps on two unrelated pages, in Openote page units (1/120 inch),
/// divided by the em we render at (18.3333 u for 11 pt):
///
/// | sample                        | steps | pitch      | ÷ em     |
/// |-------------------------------|-------|------------|----------|
/// | `Lecture.pdf`                 | 66    | 22.38299 u | 1.220890 |
/// | `Lecture p2 Web and HTTP.pdf` | 55    | 22.37745 u | 1.220588 |
///
/// Both land on **(1950 + 550) / 2048 = 1.2207031** — Calibri's `usWinAscent +
/// usWinDescent` over its `unitsPerEm`. So this is not a fudge factor: OneNote
/// lays lines out at the font's own default spacing, and that is the number.
///
/// This previously read `1.35`, making every imported line ~10.6% taller than
/// OneNote's. Fitting the *rendered* output against OneNote row by row gave
/// `dy = -2.3693 * row - 7.998 u` (R² = 0.99999993 over 213 rows, max residual
/// 0.030 u ≈ 0.006 mm) — i.e. exactly two causes and nothing else: this line
/// pitch (24.75 − 22.3805 = −2.3695 u per row) and the text block's 8 u top
/// padding (see [importedTextPadding]). A 62-line box therefore drifted ~150 u,
/// sliding its text past the images, ink and neighbouring boxes that sit at their
/// own absolute positions — the reported "text doesn't align with the other
/// elements". A separate check confirmed the parser's box origins, image
/// positions and ink transform are all accurate to better than 0.05 mm, so
/// nothing else was ever misplaced: the text was growing past it.
const double oneNoteLineHeight = 1.2207031;

/// Padding inside an imported text box.
///
/// Zero, deliberately. A OneNote box's stored origin *is* where its first line
/// starts, so any inset shifts every line in the box down and right of the
/// source. The measured intercepts were exactly our decoration padding: −8 u
/// vertically and +10 u horizontally. Hand-authored boxes keep their comfortable
/// inset; only imported ones are pinned to the origin.
const EdgeInsets importedTextPadding = EdgeInsets.zero;

/// Vertical gap the parser leaves after each item in a container's flow. These
/// mirror the parser's own constants so re-stacking changes *heights*, not
/// spacing — OneNote's real inter-paragraph spacing isn't recorded in a form
/// we've decoded, so this stays an agreed convention rather than a measurement.
const double _flowGapAfterText = 14.0;
const double _flowGapAfterTable = 20.0;

/// Height of one table row, over and above its tallest cell's text: the cell's
/// vertical content padding (6 top + 6 bottom, from `TableBlockView`) plus its
/// share of the 1px borders.
const double _tableRowChrome = 13.0;

/// Re-stack each container's flow using real text measurement.
///
/// The parser assigns every box in a container a `y`, but it can only count
/// *source* lines at a fixed 22px pitch. A paragraph that wraps to three visual
/// lines is therefore costed as one, so everything below it rides up — which is
/// why an imported table sat too high and consecutive tables overlapped. Font
/// metrics only exist here, in the renderer's process, so this is where the
/// correction belongs.
///
/// The **first** box of a flow keeps its parsed position: that one is OneNote's
/// own recorded offset and is already right. Only the boxes after it move.
/// Boxes with `flow == 0` (floating images, orphaned tables) are untouched.
///
/// Mutates `y` in the box maps in place. Exposed for testing.
void restackFlows(List<dynamic> boxes) {
  for (final group in _flowGroups(boxes)) {
    var cy = (group.first['y'] as num?)?.toDouble() ?? 0;
    for (final b in group) {
      b['y'] = cy;
      cy += _measuredFlowHeight(b);
    }
  }
}

/// [restackFlows], yielding when [shouldYield] says so — between boxes, and
/// **inside** a box's measurement.
///
/// The synchronous version treats a page as atomic, which is right for the
/// import translation (it runs inside a transaction) and wrong on the UI
/// thread. Pacing between pages could not split a page; pacing between boxes
/// could not split a box — and a real lecture page routinely carries one
/// full-page text box whose single `TextPainter.layout` measured at **216 ms
/// for 2000 lines, 613 ms for 5000**. That atomic call was the import stall
/// that survived every earlier fix, because none of my synthetic pages had a
/// giant box.
///
/// So the measurement itself is chunked (see [_measuredFlowHeightPaced]), and
/// the accumulation stays identical to [restackFlows] — same groups, same
/// heights to the last bit, same order. `flow_restack_test.dart` fuzzes the
/// equality, because a paced height that drifted from the sync one would
/// misplace imported content depending on which path measured it.
Future<void> restackFlowsPaced(
  List<dynamic> boxes, {
  required bool Function() shouldYield,
  required Future<void> Function() onYield,
}) async {
  for (final group in _flowGroups(boxes)) {
    var cy = (group.first['y'] as num?)?.toDouble() ?? 0;
    for (final b in group) {
      b['y'] = cy;
      cy += await _measuredFlowHeightPaced(b,
          shouldYield: shouldYield, onYield: onYield);
      if (shouldYield()) await onYield();
    }
  }
}

/// How many hard lines of a text box are measured per chunk in the paced
/// path. Measured at ~0.12 ms per wrapped line, 64 lines ≈ 8 ms — inside a
/// frame with room to spare.
const int _measureChunkLines = 64;

/// [_measuredFlowHeight], yielding between chunks of work.
///
/// **Why the sum is exact.** With one uniform style per box (true of every
/// parsed box) and an explicit `height` multiplier, every line box — wrapped
/// or hard — is exactly `fontSize × height` tall, so hard-broken lines lay
/// out independently and measuring them in runs and summing gives the same
/// answer to the bit. Probed across wrapping, interior empty lines, unicode
/// and unbreakable words before this was built.
///
/// **The one exception**, also probed: a chunk that is exactly ONE empty line
/// joins to the empty string, and an empty `TextPainter` reports the font's
/// natural height instead of the multiplier'd line box. Any chunk of two or
/// more lines contains a `\n` and cannot be empty, so the chunker only has to
/// avoid stranding a final lone empty line — it absorbs it into the previous
/// chunk.
Future<double> _measuredFlowHeightPaced(
  Map<String, dynamic> b, {
  required bool Function() shouldYield,
  required Future<void> Function() onYield,
}) async {
  Future<void> maybeYield() async {
    if (shouldYield()) await onYield();
  }

  switch (b['kind'] as String?) {
    case 'table':
      // Same arithmetic as the sync path, yielding between rows — a row is
      // cells of ordinary length, so per-row is fine granularity.
      final rows = (b['cells'] as List?) ?? const [];
      if (rows.isEmpty) return _flowGapAfterTable;
      final rawW = (b['col_w'] as List?) ?? const [];
      var total = 0.0;
      for (final rowRaw in rows) {
        final row = (rowRaw as List?) ?? const [];
        var tallest = 0.0;
        for (var c = 0; c < row.length; c++) {
          final w =
              c < rawW.length ? (rawW[c] as num).toDouble() : double.infinity;
          final h =
              _textHeight(row[c]?.toString() ?? '', width: w, fontSizePx: 15);
          if (h > tallest) tallest = h;
        }
        total += tallest + _tableRowChrome;
        await maybeYield();
      }
      return total + _flowGapAfterTable;
    case 'math':
      return 48.0;
    default:
      final md = b['markdown'] as String? ?? '';
      if (md.trim().isEmpty) return 0;
      final sizePt = (b['font_size_pt'] as num?)?.toDouble();
      final fontSizePx =
          (sizePt != null && sizePt > 4) ? sizePt * 120.0 / 72.0 : 15.0;
      final w = (b['w'] as num?)?.toDouble();
      final width = (w != null && w > 1) ? w : double.infinity;
      final family = b['font'] as String?;
      var imagesH = 0.0;
      final textLines = <String>[];
      for (final line in md.split('\n')) {
        final m = _flowImageLine.firstMatch(line);
        if (m != null) {
          imagesH += double.tryParse(m.group(1)!) ?? 0;
        } else {
          textLines.add(line);
        }
      }

      var textH = 0.0;
      final n = textLines.length;
      var i = 0;
      while (i < n) {
        var j = i + _measureChunkLines;
        if (j > n) j = n;
        // Don't strand a final lone empty line — see the doc comment.
        if (n - j == 1 && textLines[n - 1].isEmpty) j = n;
        textH += _textHeight(textLines.sublist(i, j).join('\n'),
            width: width, fontSizePx: fontSizePx, family: family);
        i = j;
        if (i < n) await maybeYield();
      }
      return textH + imagesH + _flowGapAfterText;
  }
}

/// Boxes grouped by flow, in input order, groups of one dropped — the shape
/// both restack variants walk. The FIRST box of a flow keeps its parsed
/// position (OneNote's own recorded offset, already right); only boxes after
/// it move.
List<List<Map<String, dynamic>>> _flowGroups(List<dynamic> boxes) {
  final byFlow = <int, List<Map<String, dynamic>>>{};
  for (final raw in boxes) {
    if (raw is! Map) continue;
    final b = raw.cast<String, dynamic>();
    final flow = (b['flow'] as num?)?.toInt() ?? 0;
    if (flow == 0) continue;
    byFlow.putIfAbsent(flow, () => []).add(b);
  }
  return [
    for (final g in byFlow.values)
      if (g.length >= 2) g // nothing below a lone anchor to correct
  ];
}

/// The fields [restackFlows] reads, and nothing else.
///
/// **Why a projection rather than sending the boxes.** The restack happens on
/// the main isolate (TextPainter is root-isolate-only) while the import runs in
/// the writer isolate, so every box has to cross an isolate boundary — and a
/// message is copied in one uninterruptible go by the receiver, which is the UI
/// thread. A parsed box carries tag lists, style runs, geometry and whatever
/// else the parser recovered; the restack reads nine fields. Measured on a
/// synthetic 3000-page notebook, projecting took the worst interaction stall
/// during the layout pass from **48 ms to 4 ms**.
///
/// Keep this in step with [_measuredFlowHeight] and the grouping in
/// [restackFlows]. `flow_projection_test.dart` fails if it drifts: a projected
/// box that measured differently from the whole one would misplace imported
/// content silently, which is the exact failure restackFlows exists to fix.
Map<String, dynamic> flowMeasurementInput(Map<String, dynamic> b) => {
      // Grouping and the anchor position.
      'flow': b['flow'],
      'y': b['y'],
      // Everything _measuredFlowHeight reads.
      'kind': b['kind'],
      if (b['markdown'] != null) 'markdown': b['markdown'],
      if (b['w'] != null) 'w': b['w'],
      if (b['font'] != null) 'font': b['font'],
      if (b['font_size_pt'] != null) 'font_size_pt': b['font_size_pt'],
      if (b['cells'] != null) 'cells': b['cells'],
      if (b['col_w'] != null) 'col_w': b['col_w'],
    };

/// The vertical space one flow item occupies, including the gap after it.
double _measuredFlowHeight(Map<String, dynamic> b) {
  switch (b['kind'] as String?) {
    case 'table':
      final rows = (b['cells'] as List?) ?? const [];
      if (rows.isEmpty) return _flowGapAfterTable;
      final rawW = (b['col_w'] as List?) ?? const [];
      var total = 0.0;
      for (final rowRaw in rows) {
        final row = (rowRaw as List?) ?? const [];
        var tallest = 0.0;
        for (var c = 0; c < row.length; c++) {
          // Unknown column widths → measure unconstrained; the row height is
          // then a floor rather than an estimate, which errs towards spacing
          // things apart instead of overlapping them.
          final w =
              c < rawW.length ? (rawW[c] as num).toDouble() : double.infinity;
          final h =
              _textHeight(row[c]?.toString() ?? '', width: w, fontSizePx: 15);
          if (h > tallest) tallest = h;
        }
        total += tallest + _tableRowChrome;
      }
      return total + _flowGapAfterTable;
    case 'math':
      // flutter_math can't be measured without laying it out; keep the
      // parser's allowance rather than pretend to a number we don't have.
      return 48.0;
    default:
      final md = b['markdown'] as String? ?? '';
      if (md.trim().isEmpty) return 0;
      final sizePt = (b['font_size_pt'] as num?)?.toDouble();
      final fontSizePx =
          (sizePt != null && sizePt > 4) ? sizePt * 120.0 / 72.0 : 15.0;
      final w = (b['w'] as num?)?.toDouble();
      // An in-flow image occupies its declared display height, not a text
      // line — measuring the placeholder as text would undercount a 200px
      // picture by an order of magnitude. Pull those lines out, add their real
      // heights, and measure what's left as text.
      var imagesH = 0.0;
      final textLines = <String>[];
      for (final line in md.split('\n')) {
        final m = _flowImageLine.firstMatch(line);
        if (m != null) {
          imagesH += double.tryParse(m.group(1)!) ?? 0;
        } else {
          textLines.add(line);
        }
      }
      return _textHeight(textLines.join('\n'),
              width: (w != null && w > 1) ? w : double.infinity,
              fontSizePx: fontSizePx,
              family: b['font'] as String?) +
          imagesH +
          _flowGapAfterText;
  }
}

/// A flow line that is nothing but an image placeholder, capturing its declared
/// display height: `![alt](onote-img://3 =264x198)`.
final _flowImageLine = RegExp(r'^\s*!\[[^\]]*\]\([^)\s]+\s+=\d+x(\d+)\)\s*$');

/// Lay [text] out exactly as the canvas will and return its height.
double _textHeight(
  String text, {
  required double width,
  required double fontSizePx,
  String? family,
}) {
  if (text.isEmpty) return 0;
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSizePx,
        height: oneNoteLineHeight,
        fontFamily: (family == null || family.isEmpty) ? null : family,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: null,
  )..layout(maxWidth: width);
  final h = tp.height;
  tp.dispose();
  return h;
}

/// Import a single `.one` section into the CURRENT notebook as a new section.
/// Pass [progressContext] to show a busy dialog while parsing.
Future<int?> importOneNoteFile(AppState app,
    {BuildContext? progressContext}) async {
  if (app.notebookId == null) return null;
  final core = OnoteCore.instance;
  if (core == null) throw OneNoteUnavailable();

  final file = await openFile(acceptedTypeGroups: const [
    XTypeGroup(label: 'OneNote section', extensions: ['one'])
  ]);
  if (file == null) return null;

  final Uint8List bytes = await file.readAsBytes();
  // Reset here too. These are process-global counters, so without this a
  // section imported after a package reported the package's numbers — which
  // matters more now that the report says what ARRIVED and not only what did
  // not.
  resetImportReport();
  Map<String, dynamic> result;
  try {
    // Structured: the isolate does the jsonDecode and the image base64 too.
    // The old shape returned the JSON string, whose decode — seconds on a big
    // section — then ran right here on the UI thread.
    result = await _withBusyDialog(
        progressContext,
        ValueNotifier('Importing OneNote section…'),
        () => compute(parseOneStructured, bytes));
  } catch (_) {
    return 0; // parser returned malformed/empty output — nothing to import
  }
  if (result['ok'] != true) return 0;

  final pages = (result['pages'] as List?) ?? const [];
  if (pages.isEmpty) return 0;

  final sectionTitle =
      importTitleFromName(p.basenameWithoutExtension(file.name));
  final (imported, firstPageId) =
      importParsedSection(app, app.notebookId!, sectionTitle, pages);

  app.reloadNodes(); // nbId is the open notebook here
  if (firstPageId != null) {
    await app.selectPage(firstPageId);
  } else {
    app.refresh();
  }
  return imported;
}

/// Sections the last import could not read, by name. Empty on a clean import.
/// Surfaced by the caller so a partial import announces itself rather than
/// quietly delivering fewer sections than the notebook contains.
List<String> lastSkippedSections = const [];

/// Ink strokes the parser could not decode in the last import (~0.02 % on the
/// reference notebook). Non-zero means the notes look complete but a handful
/// of pen marks are missing — worth a sentence, not silence.
int lastDroppedStrokes = 0;

/// Import already-parsed pages as a new section. Returns (page count, first id).
///
/// Split out of [importOneNoteFile] so the import half can be driven without a
/// file picker or a progress dialog — everything after the native parser, which
/// is where tags, images, ink and layout are actually turned into blocks, and
/// therefore the half worth testing end to end.
@visibleForTesting
(int, String?) importParsedSection(
    AppState app, String nbId, String sectionTitle, List<dynamic> pages) {
  final posBase = nowMs();
  var pos = 0;
  String next() => 'a${(posBase + pos++).toString().padLeft(15, '0')}';

  final sink = AppStateImportSink(app, nbId);
  final section = sink.node(TreeNode(
    kind: NodeKind.section,
    title: sectionTitle,
    position: next(),
  ));
  final firstPageId = _importPagesIntoSection(sink, section.id, pages, next);
  return (pages.length, firstPageId);
}

/// Clear every last-import counter. One function, because they are reset from
/// two entry points and the one that forgot was silently wrong. Public because
/// the background job (import_job.dart) is one of those entry points now.
void resetImportReport() {
  lastSkippedSections = const [];
  lastDroppedStrokes = 0;
  lastImportedImages = 0;
  lastImportedStrokes = 0;
  lastImportedTags = 0;
  lastImportError = null;
}

/// What ARRIVED in the last import — images stored and ink strokes decoded.
///
/// The failure half of an import has been surfaced since the Tier-1 pass
/// (skipped sections, dropped strokes). This is the other half, and it is not
/// symmetry for its own sake: a switcher who has just handed us five years of
/// notes has no way to know whether it worked, and silence reads as "probably
/// lost something". The numbers were already being walked past — every image is
/// counted as it is stored and every stroke as it is decoded — so saying them
/// costs two integers.
int lastImportedImages = 0;
int lastImportedStrokes = 0;
int lastImportedTags = 0;

/// Why the last import returned 0, when the reason wasn't "nothing usable".
String? lastImportError;

/// Create the sections/groups/pages of a parsed `.onepkg` into notebook [nbId].
/// Extracted from [importOneNotePackage] so it can be driven headlessly by
/// tests/tools against a real repository. [onSection] (optional) is awaited
/// before each section, for progress UI. Returns the number of pages imported.
Future<int> buildNotebookFromPackage(ImportSink sink, List<dynamic> sections,
    {Future<void> Function(int index, String name)? onSection}) async {
  // createNotebook seeds a starter section+page; remember them so the
  // scaffolding can be removed once real content has landed.
  final seeded = sink.nodes();
  final posBase = nowMs();
  var pos = 0;
  String next() => 'a${(posBase + pos++).toString().padLeft(15, '0')}';

  var imported = 0;
  String? firstPageId;
  final groupIds = <String, String>{}; // group path → node id
  for (var si = 0; si < sections.length; si++) {
    final s = (sections[si] as Map).cast<String, dynamic>();
    final pages = ((s['section'] as Map?)?['pages'] as List?) ?? const [];
    if (pages.isEmpty) continue;
    final name = importTitleFromName(s['name'] as String? ?? 'Section');
    if (onSection != null) await onSection(si, name);
    // Section group from the package's folder path (single level in the UI;
    // nested paths keep their full name).
    String? groupId;
    final group = (s['group'] as String?)?.trim();
    if (group != null && group.isNotEmpty) {
      groupId = groupIds.putIfAbsent(
          group,
          () => sink
              .node(TreeNode(
                  kind: NodeKind.sectionGroup,
                  title: group.replaceAll('/', ' › '),
                  position: next()))
              .id);
    }
    final section = sink.node(TreeNode(
      kind: NodeKind.section,
      parentId: groupId,
      title: name,
      position: next(),
    ));
    // NOTE: must not be `firstPageId ??= _import…` — `??=` short-circuits its
    // right-hand side once non-null, which would silently skip importing every
    // section after the first (the "only the first group had content" bug).
    final first = _importPagesIntoSection(sink, section.id, pages, next);
    firstPageId ??= first;
    imported += pages.length;
  }

  if (imported > 0) {
    // Drop the seeded starter section — the notebook has real content now.
    for (final n in seeded.where((n) => n.kind == NodeKind.section)) {
      sink.purgeNode(n.id);
    }
  }
  return imported;
}

/// Write a parsed package into the notebook behind [sink] a few pages at a
/// time,
/// yielding to the event loop between batches.
///
/// This is [buildNotebookFromPackage]'s responsive sibling and shares its
/// per-page translation via [importOneParsedPage]; the differences are the
/// batch boundaries and the cancel check. Kept as a top-level function so it
/// is drivable headlessly in tests, exactly as its predecessor is.
Future<({int pages, String? firstPageId})> writePackageInBatches(
  ImportSink sink,
  List<dynamic> sections, {
  int batchPages = 4,
  bool restack = true,
  Future<void> Function(List<dynamic> pagesInBatch)? prepareBatch,
  bool Function()? shouldCancel,
  void Function(String sectionName, int pagesDone, int pagesTotal)? onProgress,
}) async {
  final seeded = sink.nodes();
  final posBase = nowMs();
  var pos = 0;
  String next() => 'a${(posBase + pos++).toString().padLeft(15, '0')}';

  var total = 0;
  for (final s in sections) {
    total += ((((s as Map)['section'] as Map?)?['pages'] as List?) ?? const [])
        .length;
  }

  var written = 0;
  String? firstPageId;
  final groupIds = <String, String>{};
  for (final sRaw in sections) {
    if (shouldCancel?.call() ?? false) break;
    final s = (sRaw as Map).cast<String, dynamic>();
    final pages = ((s['section'] as Map?)?['pages'] as List?) ?? const [];
    if (pages.isEmpty) continue;
    final name = importTitleFromName(s['name'] as String? ?? 'Section');

    String? groupId;
    final group = (s['group'] as String?)?.trim();
    if (group != null && group.isNotEmpty) {
      groupId = groupIds.putIfAbsent(
          group,
          () => sink
              .node(TreeNode(
                  kind: NodeKind.sectionGroup,
                  title: group.replaceAll('/', ' › '),
                  position: next()))
              .id);
    }
    final section = sink.node(TreeNode(
      kind: NodeKind.section,
      parentId: groupId,
      title: name,
      position: next(),
    ));

    // The preparation for the batch after the one being written, already in
    // flight. See the fire below for why.
    Future<void>? prepped;
    List<dynamic> batchAt(int start) => pages.sublist(
        start,
        (start + batchPages) > pages.length
            ? pages.length
            : start + batchPages);

    for (var start = 0; start < pages.length; start += batchPages) {
      if (shouldCancel?.call() ?? false) break;
      final end = (start + batchPages) > pages.length
          ? pages.length
          : start + batchPages;
      // Anything that has to happen elsewhere before these pages can be
      // written. The writer isolate uses it to have the main isolate lay out
      // this batch's flows — see [flowMeasurementInput]. Per batch, not per
      // notebook: a single up-front pass meant nothing was written until every
      // page had been measured, and meant one enormous message crossing the
      // isolate boundary in one uninterruptible copy.
      if (prepareBatch != null) {
        await (prepped ?? prepareBatch(batchAt(start)));
        prepped = null;
      }
      if (shouldCancel?.call() ?? false) break;
      // Fire the NEXT batch's preparation before writing this one, so it
      // overlaps instead of queueing behind it. This is what keeps the
      // preparation off the critical path: it happens in another isolate, and
      // waiting for it turned a 2000-page import from 13.4 s into 23.2 s
      // because the pacing that keeps that isolate responsive — a real frame
      // between chunks — was being paid for serially, once per batch.
      if (prepareBatch != null && end < pages.length) {
        prepped = prepareBatch(batchAt(end));
      }
      final first = sink.batch(() {
        String? firstInBatch;
        for (var i = start; i < end; i++) {
          final id = importOneParsedPage(
              sink, section.id, (pages[i] as Map).cast<String, dynamic>(), next,
              restack: restack);
          firstInBatch ??= id;
        }
        return firstInBatch;
      });
      firstPageId ??= first;
      written += end - start;
      onProgress?.call(name, written, total);
      // Let anything else queued in this isolate run — the cancel message, in
      // particular, which is delivered as an event and can only be seen at a
      // boundary like this one.
      await Future<void>.delayed(Duration.zero);
    }
    // A batch prepared for a page we then decided not to write (cancel, or the
    // section ending mid-flight). Settle it rather than abandoning it: the
    // future is live, and dropping it leaves an unawaited error waiting to be
    // reported against whatever runs next.
    if (prepped != null) {
      try {
        await prepped;
      } catch (_) {/* the run is ending anyway */}
    }
  }

  if (written > 0 && !(shouldCancel?.call() ?? false)) {
    for (final n in seeded.where((n) => n.kind == NodeKind.section)) {
      sink.purgeNode(n.id);
    }
  }
  return (pages: written, firstPageId: firstPageId);
}

/// Import parsed pages into [sectionId]. Returns the first created page id.
/// The whole section runs in ONE transaction — per-page commits measurably
/// dominated large imports.
String? _importPagesIntoSection(ImportSink sink, String sectionId,
        List<dynamic> pages, String Function() next) =>
    sink.batch(() => _importPagesLocked(sink, sectionId, pages, next));

/// The page-import path, reachable from a test with one parsed section.
///
/// The e2e import tests could only drive the whole `.onepkg` flow, so a single
/// misbehaving page had no way to be examined without importing a five-year
/// notebook around it. Exposed for diagnosing exactly that.
@visibleForTesting
String? importPagesForTest(
        ImportSink sink, String sectionId, List<dynamic> pages) =>
    _importPagesIntoSection(sink, sectionId, pages, newId);

String? _importPagesLocked(ImportSink sink, String sectionId,
    List<dynamic> pages, String Function() next) {
  String? firstPageId;
  for (final raw in pages) {
    final id = importOneParsedPage(
        sink, sectionId, (raw as Map).cast<String, dynamic>(), next);
    firstPageId ??= id;
  }
  return firstPageId;
}

/// Write ONE parsed page into [sectionId]. Returns the created page id.
///
/// The unit the background import job batches on: a page is big enough that
/// per-page transactions would cost real time over hundreds of pages, and
/// small enough that a batch of a few stays comfortably inside one frame
/// budget's worth of work between yields. Extracted from the loop above so
/// both callers share every byte of the translation logic.
/// Set [restack] false when the flow y-coordinates have already been corrected
/// — the writer isolate does that, because [restackFlows] needs `TextPainter`
/// and text layout is only available on the root isolate.
String importOneParsedPage(ImportSink sink, String sectionId,
    Map<String, dynamic> page, String Function() next,
    {bool restack = true}) {
  {
    final title = (page['title'] as String?)?.trim();
    final boxes = (page['boxes'] as List?) ?? const [];
    final images = (page['images'] as List?) ?? const [];
    // Parser-side stroke drops, accumulated for the import summary — the notes
    // LOOK complete when a stroke vanishes, which is exactly why it gets said.
    lastDroppedStrokes += (page['dropped_strokes'] as num?)?.toInt() ?? 0;

    // Recover the page's original created date from the title box's date text
    // (carried out-of-band — the title box itself is not imported as content,
    // since Openote's page title band already shows the title and date).
    final createdMs = _parseOneNoteDate(page['date_text'] as String? ?? '');

    final node = sink.node(TreeNode(
      kind: NodeKind.page,
      parentId: sectionId,
      title: (title == null || title.isEmpty) ? 'Imported page' : title,
      position: next(),
      createdAt: createdMs,
      // Subpage indent straight from OneNote's page level (ORG-6).
      level: ((page['level'] as num?)?.toInt() ?? 0).clamp(0, 2),
    ));

    // Store image blobs FIRST: box markdown references in-flow images by index
    // (`![image](onote-img://N)`), which we rewrite to the stored blob hash so
    // the text renderer flows them inside the box (Data Model §5.1). Floating
    // images (in_flow == false) become positioned image blocks.
    final blocks = <Block>[];
    final hashByIndex = <int, String>{};
    for (var i = 0; i < images.length; i++) {
      final img = (images[i] as Map).cast<String, dynamic>();
      // Bytes when the structured isolate already decoded them (the fast
      // path); base64 when a caller fed this parser output verbatim. Decoding
      // here is the compatibility spelling, not the intended one — on the UI
      // thread it is exactly the work the isolate exists to keep off it.
      Uint8List? png = img['bytes'] as Uint8List?;
      if (png == null) {
        final b64 = img['data_base64'] as String?;
        if (b64 == null || b64.isEmpty) continue;
        try {
          png = base64Decode(b64);
        } catch (_) {
          continue;
        }
      }
      final hash = sink.blob(png, 'image/png');
      hashByIndex[i] = hash;
      lastImportedImages++;
      if (img['in_flow'] == true) continue; // rides a text box's flow
      final dw = (img['disp_w'] as num?)?.toDouble() ?? 0;
      final dh = (img['disp_h'] as num?)?.toDouble() ?? 0;
      final w = dw > 1 ? dw : ((img['width'] as num?)?.toDouble() ?? 320);
      final h = dh > 1 ? dh : ((img['height'] as num?)?.toDouble() ?? 240);
      blocks.add(Block(
        type: BlockType.image,
        x: (img['x'] as num?)?.toDouble() ?? 640,
        y: (img['y'] as num?)?.toDouble() ?? AppState.contentTop,
        w: w,
        h: h,
        content: {'blob': 'sha256:$hash', 'mime': 'image/png'},
      ));
    }

    if (restack) restackFlows(boxes);

    // Each OneNote box becomes its own block at the coordinates the parser
    // recovered: text boxes keep their original width (autoWidth off) so a
    // long line never grows the box sideways; equations become math blocks.
    for (final bRaw in boxes) {
      final b = (bRaw as Map).cast<String, dynamic>();
      final x = (b['x'] as num?)?.toDouble() ?? AppState.pageLeftMargin;
      final y = (b['y'] as num?)?.toDouble() ?? AppState.contentTop;
      if (b['kind'] == 'table') {
        // MEDIA-3 on import: the parser hands over a rectangular grid of
        // per-cell Markdown, which is exactly what TableBlockView stores.
        final rows = (b['cells'] as List?) ?? const [];
        final cells = [
          for (final row in rows)
            [for (final c in (row as List)) c?.toString() ?? '']
        ];
        if (cells.isEmpty || cells.first.isEmpty) continue;
        // OneNote records a width per column (0x1D66). Without them every
        // column got an equal share of a guessed total, so imported tables were
        // visibly the wrong shape and overflowed into their neighbours. Keep
        // them only if there is one per column, so a partial array can't stretch
        // the wrong columns.
        final rawW = (b['col_w'] as List?) ?? const [];
        final colWidths = rawW.length == cells.first.length
            ? [for (final v in rawW) (v as num).toDouble()]
            : const <double>[];
        final content = <String, dynamic>{'cells': cells};
        if (colWidths.isNotEmpty) content['colWidths'] = colWidths;
        blocks.add(Block(
          type: BlockType.table,
          x: x,
          y: y,
          w: (b['w'] as num?)?.toDouble() ??
              (colWidths.isNotEmpty
                  ? colWidths.reduce((a, c) => a + c)
                  : (140.0 * cells.first.length).clamp(240.0, 900.0)),
          content: content,
        ));
        continue;
      }
      if (b['kind'] == 'math') {
        final latex = (b['latex'] as String? ?? '').trim();
        if (latex.isEmpty) continue;
        blocks.add(Block(
          type: BlockType.math,
          x: x,
          y: y,
          w: 320,
          content: {'latex': latex, 'display': true},
        ));
        continue;
      }
      var text = (b['markdown'] as String? ?? '').trimRight();
      if (text.isEmpty) continue;
      // Rewrite in-flow image placeholders to their stored blob hashes,
      // keeping the ` =WxH` display-size suffix; a placeholder whose blob
      // failed to store degrades to nothing.
      text = text.replaceAllMapped(
          RegExp(r'!\[([^\]]*)\]\(onote-img://(\d+)(\s+=\d+x\d+)?\)'), (m) {
        final hash = hashByIndex[int.parse(m.group(2)!)];
        if (hash == null) return '';
        return '![${m.group(1)}](sha256:$hash${m.group(3) ?? ''})';
      });
      if (text.trim().isEmpty) continue;
      final content = <String, dynamic>{'text': text, 'autoWidth': false};
      final font = b['font'] as String?;
      if (font != null && font.isNotEmpty) content['font'] = font;
      // Render at OneNote's text metrics (pt → px in the page's 120 dpi space)
      // so box heights track the source and absolutely-positioned neighbours
      // don't drift apart.
      final sizePt = (b['font_size_pt'] as num?)?.toDouble();
      if (sizePt != null && sizePt > 4) {
        content['fontSize'] = sizePt * 120.0 / 72.0;
        content['lineHeight'] = oneNoteLineHeight;
      }
      // Pin the text to the box origin: OneNote's stored offset IS the first
      // line's position, so our comfortable inset would shift every line in the
      // box down-and-right of the source (see [importedTextPadding]).
      content['inset'] = 0;
      // Tags OneNote put on these paragraphs (TEXT-5). The parser pins each to
      // a line index within this box's markdown, which is the same thing our
      // own tags are keyed on, so they need no translation beyond the kind.
      //
      // A tag whose label we don't recognise still arrives, as `custom` with
      // its name kept — an imported tag we cannot map must be visible, never
      // silently discarded.
      final rawTags = (b['tags'] as List?) ?? const [];
      if (rawTags.isNotEmpty) {
        final lineCount = text.split('\n').length;
        final tags = <NoteTag>[];
        for (final t in rawTags) {
          final m = (t as Map).cast<String, dynamic>();
          final line = (m['line'] as num?)?.toInt() ?? -1;
          final label = (m['label'] as String? ?? '').trim();
          // The image-placeholder rewrite above can only change text WITHIN a
          // line, so indices still line up — but a tag pointing outside the
          // box would mark a sentence that isn't there.
          if (line < 0 || line >= lineCount || label.isEmpty) continue;
          final kind = TagKind.fromOneNoteLabel(label);
          tags.add(NoteTag(
            kind: kind,
            line: line,
            // Unticked: OneNote's completion flag is not decoded, see
            // `paragraph_tags` in the core. A wrongly-ticked to-do is worse
            // than an unticked one.
            checked: kind == TagKind.todo ? false : null,
            label: kind == TagKind.custom ? label : null,
          ));
          lastImportedTags++;
        }
        if (tags.isNotEmpty) NoteTag.writeInto(content, tags);
      }
      blocks.add(Block(
        type: BlockType.text,
        x: x,
        y: y,
        w: (b['w'] as num?)?.toDouble() ?? 560,
        content: content,
      ));
    }

    // Ink: the parser delivers decoded strokes in page pixels (with pressure
    // when the pen recorded it). They become one ink block whose rect is the
    // strokes' bounding box — coordinates stay page-absolute (Ink Spec §3).
    final inkStrokes = (page['ink'] as List?) ?? const [];
    if (inkStrokes.isNotEmpty) {
      final strokes = <Map<String, dynamic>>[];
      var mnx = double.infinity, mny = double.infinity;
      var mxx = -double.infinity, mxy = -double.infinity;
      for (final sRaw in inkStrokes) {
        final s = (sRaw as Map).cast<String, dynamic>();
        final xs = ((s['x'] as List?) ?? const [])
            .map((e) => (e as num).toDouble())
            .toList();
        final ys = ((s['y'] as List?) ?? const [])
            .map((e) => (e as num).toDouble())
            .toList();
        if (xs.isEmpty || xs.length != ys.length) continue;
        final ps = ((s['p'] as List?) ?? const [])
            .map((e) => (e as num).toDouble())
            .toList();
        for (final v in xs) {
          if (v < mnx) mnx = v;
          if (v > mxx) mxx = v;
        }
        for (final v in ys) {
          if (v < mny) mny = v;
          if (v > mxy) mxy = v;
        }
        strokes.add({
          'id': newId(),
          'brush': {
            'tool': 'pen',
            // "auto" = themed default ink (dark on light / light on dark);
            // explicit OneNote pen colours pass through as #RRGGBB.
            'color': s['color'] as String? ?? 'auto',
            'size': ((s['size'] as num?)?.toDouble() ?? 2.0).clamp(0.6, 24.0),
            'opacity':
                ((s['opacity'] as num?)?.toDouble() ?? 1.0).clamp(0.05, 1.0),
          },
          'x': xs,
          'y': ys,
          'p': ps,
          'tx': const <double>[],
          'ty': const <double>[],
          't': const <int>[],
          'strokeStart': nowMs(),
        });
      }
      if (strokes.isNotEmpty) {
        lastImportedStrokes += strokes.length;
        blocks.add(Block(
          type: BlockType.ink,
          x: mnx - 6,
          y: mny - 6,
          w: (mxx - mnx) + 12,
          h: (mxy - mny) + 12,
          content: {'strokes': strokes},
        ));
      }
    }

    sink.page(node.id, blocks, PageProps());
    return node.id;
  }
}

///
/// "324 pages, 372 images, 64,616 strokes" is the sentence that converts
/// someone who has just handed over five years of notes. Until now the import
/// said only what it could not read, so a clean import was reported as a bare
/// page count and a silence — and silence, after a migration, reads as "it
/// probably lost something".
///
/// Each clause appears only if it is non-zero: a notebook with no ink should
/// not be told it imported no ink.
String importArrivalNote(int pages, int images, int strokes, [int tags = 0]) {
  String n(int v, String one, [String? many]) =>
      '${_grouped(v)} ${v == 1 ? one : (many ?? '${one}s')}';
  final parts = <String>[
    n(pages, 'page'),
    if (images > 0) n(images, 'image'),
    if (strokes > 0) n(strokes, 'ink stroke'),
    if (tags > 0) n(tags, 'tag'),
  ];
  if (parts.length == 1) return parts.first;
  return '${parts.take(parts.length - 1).join(', ')} and ${parts.last}';
}

/// Thousands separators, because 64616 is a number you have to count digits on
/// and 64,616 is one you read.
String _grouped(int v) {
  final digits = v.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// A section/notebook title from a file or folder name. Public because the
/// background job (import_job.dart) names its notebook with it too.
String importTitleFromName(String name) {
  final t = name.replaceAll('_', ' ').trim();
  return t.isEmpty ? 'OneNote import' : t;
}

const _months = {
  'january': 1,
  'february': 2,
  'march': 3,
  'april': 4,
  'may': 5,
  'june': 6,
  'july': 7,
  'august': 8,
  'september': 9,
  'october': 10,
  'november': 11,
  'december': 12,
};

/// Parse OneNote's title-area date/time (e.g. "Tuesday, 29 July 2025" +
/// "8:05 AM") out of the parser's `date_text` and return it as epoch ms.
int? _parseOneNoteDate(String s) {
  if (s.isEmpty) return null;
  final dateRe = RegExp(r'(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})');
  final dm = dateRe.firstMatch(s);
  if (dm == null) return null;
  final day = int.tryParse(dm.group(1)!);
  final month = _months[dm.group(2)!.toLowerCase()];
  final year = int.tryParse(dm.group(3)!);
  if (day == null || month == null || year == null) return null;
  var hour = 0, minute = 0;
  final tm = RegExp(r'(\d{1,2}):(\d{2})\s*([AaPp][Mm])?').firstMatch(s);
  if (tm != null) {
    hour = int.tryParse(tm.group(1)!) ?? 0;
    minute = int.tryParse(tm.group(2)!) ?? 0;
    final ap = tm.group(3)?.toLowerCase();
    if (ap == 'pm' && hour < 12) hour += 12;
    if (ap == 'am' && hour == 12) hour = 0;
  }
  return DateTime(year, month, day, hour, minute).millisecondsSinceEpoch;
}
