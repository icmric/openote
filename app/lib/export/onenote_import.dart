import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/ids.dart';
import '../core/onote_ffi.dart';
import '../model/models.dart';
import '../state/app_state.dart';

/// Isolate entry points: the Rust parse (LZX + binary decode + base64) can
/// take seconds on a big notebook and must not freeze the UI thread. Each
/// isolate loads its own copy of the native library on first use.
String _parseOneInIsolate(Uint8List bytes) =>
    (OnoteCore.instance ?? (throw StateError('core unavailable')))
        .importOne(bytes);
String _parseOnepkgInIsolate(Uint8List bytes) =>
    (OnoteCore.instance ?? (throw StateError('core unavailable')))
        .importOnepkg(bytes);

/// Show a busy dialog while [work] runs (import feedback for large notebooks).
/// The dialog text tracks [message] live, so multi-phase imports can narrate
/// progress ("Importing section 3 of 12…") as they go.
Future<T> _withBusyDialog<T>(BuildContext? context,
    ValueNotifier<String> message, Future<T> Function() work) async {
  if (context == null || !context.mounted) return work();
  showDialog<void>(
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
  Map<String, dynamic> result;
  try {
    final json = await _withBusyDialog(
        progressContext,
        ValueNotifier('Importing OneNote section…'),
        () => compute(_parseOneInIsolate, bytes));
    result = jsonDecode(json) as Map<String, dynamic>;
  } catch (_) {
    return 0; // parser returned malformed/empty output — nothing to import
  }
  if (result['ok'] != true) return 0;

  final pages = (result['pages'] as List?) ?? const [];
  if (pages.isEmpty) return 0;

  final nbId = app.notebookId!;
  final posBase = nowMs();
  var pos = 0;
  String next() => 'a${(posBase + pos++).toString().padLeft(15, '0')}';

  // A section named after the imported file.
  final sectionTitle = _titleFromName(p.basenameWithoutExtension(file.name));
  final section = app.repo.upsertNode(
      nbId,
      TreeNode(
        kind: NodeKind.section,
        title: sectionTitle,
        position: next(),
      ));

  final firstPageId =
      _importPagesIntoSection(app, nbId, section.id, pages, next);
  final imported = pages.length;

  app.nodes = app.repo.loadNodes(nbId);
  if (firstPageId != null) {
    await app.selectPage(firstPageId);
  } else {
    app.refresh();
  }
  return imported;
}

/// Import a `.onepkg` notebook package as a NEW notebook: one Openote section
/// per packaged `.one` (grouped into section groups when the package nests
/// them in folders), named after the package file. Pass [progressContext] to
/// show a busy dialog while parsing.
Future<int?> importOneNotePackage(AppState app,
    {BuildContext? progressContext}) async {
  final core = OnoteCore.instance;
  if (core == null) throw OneNoteUnavailable();

  final file = await openFile(acceptedTypeGroups: const [
    XTypeGroup(label: 'OneNote notebook package', extensions: ['onepkg'])
  ]);
  if (file == null) return null;

  final Uint8List bytes = await file.readAsBytes();
  // One dialog spans both phases: the native parse (single isolate call) and
  // the per-section database writes, which narrate progress as they go.
  final progress = ValueNotifier(
      'Reading notebook… this can take a while for large notebooks.');
  return _withBusyDialog(progressContext, progress, () async {
    Map<String, dynamic> result;
    try {
      final json = await compute(_parseOnepkgInIsolate, bytes);
      result = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return 0;
    }
    if (result['ok'] != true) return 0;
    final sections = (result['sections'] as List?) ?? const [];
    if (sections.isEmpty) return 0;

    // The package is a whole notebook → create a fresh one named after it.
    final nbTitle = _titleFromName(p.basenameWithoutExtension(file.name));
    final ref = await app.repo.createNotebook(nbTitle);
    final built = buildNotebookFromPackage(app, ref.id, sections,
        onSection: (i, name) {
      progress.value = 'Importing "$name" (${i + 1} of ${sections.length})…';
      return Future<void>.delayed(Duration.zero); // let the dialog repaint
    });
    final imported = await built;
    await app.selectNotebook(ref.id);
    if (_firstImportedPageId != null) await app.selectPage(_firstImportedPageId!);
    return imported;
  });
}

/// Last page created by [buildNotebookFromPackage] (so callers can navigate to
/// it). Set as a side effect to keep the return value a simple count.
String? _firstImportedPageId;

/// Create the sections/groups/pages of a parsed `.onepkg` into notebook [nbId].
/// Extracted from [importOneNotePackage] so it can be driven headlessly by
/// tests/tools against a real repository. [onSection] (optional) is awaited
/// before each section, for progress UI. Returns the number of pages imported.
Future<int> buildNotebookFromPackage(
    AppState app, String nbId, List<dynamic> sections,
    {Future<void> Function(int index, String name)? onSection}) async {
  // createNotebook seeds a starter section+page; remember them so the
  // scaffolding can be removed once real content has landed.
  final seeded = app.repo.loadNodes(nbId);
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
    final name = _titleFromName(s['name'] as String? ?? 'Section');
    if (onSection != null) await onSection(si, name);
    // Section group from the package's folder path (single level in the UI;
    // nested paths keep their full name).
    String? groupId;
    final group = (s['group'] as String?)?.trim();
    if (group != null && group.isNotEmpty) {
      groupId = groupIds.putIfAbsent(
          group,
          () => app.repo
              .upsertNode(
                  nbId,
                  TreeNode(
                      kind: NodeKind.sectionGroup,
                      title: group.replaceAll('/', ' › '),
                      position: next()))
              .id);
    }
    final section = app.repo.upsertNode(
        nbId,
        TreeNode(
          kind: NodeKind.section,
          parentId: groupId,
          title: name,
          position: next(),
        ));
    // NOTE: must not be `firstPageId ??= _import…` — `??=` short-circuits its
    // right-hand side once non-null, which would silently skip importing every
    // section after the first (the "only the first group had content" bug).
    final first = _importPagesIntoSection(app, nbId, section.id, pages, next);
    firstPageId ??= first;
    imported += pages.length;
  }

  if (imported > 0) {
    // Drop the seeded starter section — the notebook has real content now.
    for (final n in seeded.where((n) => n.kind == NodeKind.section)) {
      app.repo.purgeNode(nbId, n.id);
    }
  }
  _firstImportedPageId = firstPageId;
  return imported;
}

/// Import parsed pages into [sectionId]. Returns the first created page id.
/// The whole section runs in ONE transaction — per-page commits measurably
/// dominated large imports.
String? _importPagesIntoSection(AppState app, String nbId, String sectionId,
        List<dynamic> pages, String Function() next) =>
    app.repo.runInTransaction(
        nbId, () => _importPagesLocked(app, nbId, sectionId, pages, next));

String? _importPagesLocked(AppState app, String nbId, String sectionId,
    List<dynamic> pages, String Function() next) {
  String? firstPageId;
  for (final raw in pages) {
    final page = (raw as Map).cast<String, dynamic>();
    final title = (page['title'] as String?)?.trim();
    final boxes = (page['boxes'] as List?) ?? const [];
    final images = (page['images'] as List?) ?? const [];

    // Recover the page's original created date from the title box's date text
    // (carried out-of-band — the title box itself is not imported as content,
    // since Openote's page title band already shows the title and date).
    final createdMs = _parseOneNoteDate(page['date_text'] as String? ?? '');

    final node = app.repo.upsertNode(
        nbId,
        TreeNode(
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
      final b64 = img['data_base64'] as String?;
      if (b64 == null || b64.isEmpty) continue;
      final Uint8List png;
      try {
        png = base64Decode(b64);
      } catch (_) {
        continue;
      }
      final hash = app.repo.putBlob(nbId, png, 'image/png');
      hashByIndex[i] = hash;
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

    // Each OneNote box becomes its own block at the coordinates the parser
    // recovered: text boxes keep their original width (autoWidth off) so a
    // long line never grows the box sideways; equations become math blocks.
    for (final bRaw in boxes) {
      final b = (bRaw as Map).cast<String, dynamic>();
      final x = (b['x'] as num?)?.toDouble() ?? AppState.pageLeftMargin;
      final y = (b['y'] as num?)?.toDouble() ?? AppState.contentTop;
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
      // Render at OneNote's text metrics (pt → px in the page's 120 dpi
      // space; OneNote's line spacing ≈ 1.32) so box heights track the
      // source and absolutely-positioned neighbours don't drift apart.
      final sizePt = (b['font_size_pt'] as num?)?.toDouble();
      if (sizePt != null && sizePt > 4) {
        content['fontSize'] = sizePt * 120.0 / 72.0;
        content['lineHeight'] = 1.35; // calibrated against real pages
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

    app.repo.writePage(nbId, node.id, blocks, PageProps());
    firstPageId ??= node.id;
  }
  return firstPageId;
}

String _titleFromName(String name) {
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
