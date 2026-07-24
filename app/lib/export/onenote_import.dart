import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../core/onote_ffi.dart';
import '../model/models.dart';
import '../state/app_state.dart';

/// OneNote `.one` section import (OPEN-8, v1).
///
/// Powered by the Rust core's reverse-engineered MS-ONESTORE/MS-ONE parser
/// (`onote_core::onenote`). It brings across a section's **title, text (with
/// bold / italic / strikethrough, font family and colour), bulleted/indented
/// outlines, equations** (Office linear-math → LaTeX, rendered as `$$…$$`) and
/// **images** at their stored page positions/sizes. Not yet reconstructed:
/// per-page splitting of a multi-page section (content merges into one page)
/// and ink (needs a sample file to identify its object types). Requires the
/// native core to be linked — pure-Dart builds can't parse the binary format.
///
/// Returns the number of pages imported, 0 if the file had nothing usable,
/// or null if the user cancelled. Throws [OneNoteUnavailable] when the Rust
/// core isn't linked.
class OneNoteUnavailable implements Exception {}

Future<int?> importOneNoteFile(AppState app) async {
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
    result = jsonDecode(core.importOne(bytes)) as Map<String, dynamic>;
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

  String? firstPageId;
  var imported = 0;
  for (final raw in pages) {
    final page = (raw as Map).cast<String, dynamic>();
    final title = (page['title'] as String?)?.trim();
    final texts = (page['texts'] as List?) ?? const [];
    final images = (page['images'] as List?) ?? const [];

    // Recover the page's original created date from the title/date text so the
    // in-page date band shows it instead of today's date.
    final createdMs = _parseOneNoteDate(texts);

    final node = app.repo.upsertNode(
        nbId,
        TreeNode(
          kind: NodeKind.page,
          parentId: section.id,
          title: (title == null || title.isEmpty) ? 'Imported page' : title,
          position: next(),
          createdAt: createdMs,
        ));

    // Each OneNote container becomes its own box, placed at the coordinates the
    // Rust parser recovered. Text boxes are fixed-width (autoWidth off) so a
    // long line never grows the box sideways over an adjacent image.
    final blocks = <Block>[];
    for (final tRaw in texts) {
      final t = (tRaw as Map).cast<String, dynamic>();
      final text = (t['markdown'] as String? ?? '').trimRight();
      if (text.isEmpty) continue;
      // The parser now carries bold/italic/colour inline (Markdown +
      // `{{#hex}}`), `$$…$$` math, and a box-level font family.
      final content = <String, dynamic>{'text': text, 'autoWidth': false};
      final font = t['font'] as String?;
      if (font != null && font.isNotEmpty) content['font'] = font;
      blocks.add(Block(
        type: BlockType.text,
        x: (t['x'] as num?)?.toDouble() ?? AppState.pageLeftMargin,
        y: (t['y'] as num?)?.toDouble() ?? AppState.contentTop,
        w: 560,
        content: content,
      ));
    }
    for (final imgRaw in images) {
      final img = (imgRaw as Map).cast<String, dynamic>();
      final b64 = img['data_base64'] as String?;
      if (b64 == null || b64.isEmpty) continue;
      final Uint8List png;
      try {
        png = base64Decode(b64);
      } catch (_) {
        continue;
      }
      final hash = app.repo.putBlob(nbId, png, 'image/png');
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

    app.repo.writePage(nbId, node.id, blocks, PageProps());
    firstPageId ??= node.id;
    imported++;
  }

  app.nodes = app.repo.loadNodes(nbId);
  if (firstPageId != null) {
    await app.selectPage(firstPageId);
  } else {
    app.refresh();
  }
  return imported;
}

String _titleFromName(String name) {
  final t = name.replaceAll('_', ' ').trim();
  return t.isEmpty ? 'OneNote import' : t;
}

const _months = {
  'january': 1, 'february': 2, 'march': 3, 'april': 4, 'may': 5, 'june': 6,
  'july': 7, 'august': 8, 'september': 9, 'october': 10, 'november': 11,
  'december': 12,
};

/// Scan the imported text for OneNote's title-area date/time (e.g.
/// "Tuesday, 29 July 2025" + "8:05 AM") and return it as epoch ms, or null.
int? _parseOneNoteDate(List<dynamic> texts) {
  final buf = StringBuffer();
  for (final tRaw in texts) {
    final m = (tRaw as Map)['markdown'];
    if (m is String) buf.writeln(m);
  }
  final s = buf.toString();
  final dateRe =
      RegExp(r'(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})');
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
