import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../model/models.dart';
import '../state/app_state.dart';
import 'md_common.dart';

/// Open-format exporters (OPEN-5/6/7): the "glass box" promise made real.
///
/// * [materializeNotebook] writes the whole notebook as a plain folder tree of
///   open files (File Format Spec §8): a top-level `notebook.json` structure
///   tree, one folder per page under `pages/` (nested to mirror the section
///   hierarchy), each page carried by a fidelity `page.json` (the mirror), a
///   convenience `page.md`, a JSON Canvas `canvas.json`, a `page.inkml` when the
///   page has ink, and a single top-level `assets/` of content-addressed blobs
///   (shared across pages, so an image used twice is stored once). Nothing here
///   needs Openote to read.
/// * [exportPageJsonCanvas] exports the current page as a single
///   [JSON Canvas](https://jsoncanvas.org) file (Obsidian-compatible).
/// * [exportPageInkML] exports the current page's ink as W3C InkML.
///
/// Freeform layout flattens to reading order (top→bottom, then left→right) for
/// the Markdown projection; the JSON keeps exact coordinates (File Format Spec
/// §8: page.json is the fidelity path, page.md the convenience one).

// ── Whole-notebook materialize (OPEN-6) ───────────────────────────────────

/// Export every page of the current notebook into [rootDir]/<notebook>/…, one
/// folder per section and page. Returns the created root folder path, or null
/// if the user cancelled the folder picker.
Future<String?> materializeNotebook(AppState app) async {
  if (app.notebookId == null) return null;
  await app.flushSave(); // include the open page's latest edits

  final dir = await getDirectoryPath(confirmButtonText: 'Export here');
  if (dir == null) return null;

  final nb = app.notebooks.firstWhere((n) => n.id == app.notebookId);
  final root = _uniqueDir(dir, safeFilename(nb.title));
  await Directory(root).create(recursive: true);
  final assetsDir = p.join(root, 'assets');

  final byId = {for (final n in app.nodes) n.id: n};
  final manifestPages = <Map<String, dynamic>>[];
  final usedDirs = <String>{};
  // hash → "hash.ext"; collected across ALL pages then written once (dedup).
  final sharedAssets = <String, String>{};

  for (final node in app.nodes.where((n) => n.kind == NodeKind.page)) {
    // Page folder = sanitized titles of every ancestor + this page (+ an id
    // suffix to guarantee uniqueness), so the section/group/subpage hierarchy
    // is mirrored as nested folders under pages/.
    final segments = <String>[];
    TreeNode? cur = node;
    while (cur != null) {
      segments.insert(0, safeFilename(cur.title));
      cur = cur.parentId == null ? null : byId[cur.parentId];
    }
    var rel = p.joinAll(segments);
    // De-collide sibling pages that sanitize to the same name.
    var candidate = rel;
    var i = 2;
    while (usedDirs.contains(candidate.toLowerCase())) {
      candidate = '$rel-$i';
      i++;
    }
    usedDirs.add(candidate.toLowerCase());
    rel = candidate;

    final pageDir = p.join(root, 'pages', rel);
    await Directory(pageDir).create(recursive: true);
    // Relative path from this page's folder back to the shared assets/ dir,
    // in POSIX form so the Markdown/canvas links are portable.
    final assetPrefix =
        p.relative(assetsDir, from: pageDir).replaceAll('\\', '/');

    final data = app.readPage(node.id);
    final blocks = data.blocks;

    // 1) Fidelity mirror.
    await File(p.join(pageDir, 'page.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(
            _mirrorMap(node.id, data.props, blocks)));

    // 2) Convenience Markdown + collected image assets.
    final md = _pageMarkdown(node.title, blocks, assetPrefix);
    await File(p.join(pageDir, 'page.md')).writeAsString(md.text);
    sharedAssets.addAll(md.assets);

    // 3) JSON Canvas.
    await File(p.join(pageDir, 'canvas.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(
            _jsonCanvas(blocks, assetPrefix)));

    // 4) InkML when there's ink.
    final inkml = _inkML(blocks);
    if (inkml != null) {
      await File(p.join(pageDir, 'page.inkml')).writeAsString(inkml);
    }

    manifestPages.add({
      'id': node.id,
      'title': node.title,
      'path': 'pages/${rel.replaceAll('\\', '/')}',
      'level': node.level,
    });
  }

  // Write the shared, content-addressed asset store once.
  if (sharedAssets.isNotEmpty) {
    await Directory(assetsDir).create(recursive: true);
    for (final e in sharedAssets.entries) {
      final bytes = app.blob(e.key);
      if (bytes != null) {
        await File(p.join(assetsDir, e.value)).writeAsBytes(bytes);
      }
    }
  }

  // notebook.json: the full structure tree (groups/sections/pages, order,
  // colours, timestamps) — the spec's §8 top-level structure file.
  await File(p.join(root, 'notebook.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
    'format': 'openote-materialized/1',
    'notebook': {'id': nb.id, 'title': nb.title},
    'exportedAt': DateTime.now().toIso8601String(),
    'nodes': [
      for (final n in app.nodes)
        {
          'id': n.id,
          'kind': switch (n.kind) {
            NodeKind.sectionGroup => 'section_group',
            NodeKind.section => 'section',
            NodeKind.page => 'page',
          },
          'parentId': n.parentId,
          'title': n.title,
          'position': n.position,
          if (n.color != null) 'color': n.color,
          'level': n.level,
          'createdAt': n.createdAt,
          'updatedAt': n.updatedAt,
        }
    ],
    'pages': manifestPages,
  }));

  return root;
}

// ── Single-page JSON Canvas (OPEN-6) ──────────────────────────────────────

Future<String?> exportPageJsonCanvas(AppState app) async {
  if (app.pageId == null) return null;
  await app.flushSave();
  final page = app.nodes.firstWhere((n) => n.id == app.pageId);
  final location = await getSaveLocation(
    suggestedName: '${safeFilename(page.title)}.canvas',
    acceptedTypeGroups: const [
      XTypeGroup(label: 'JSON Canvas', extensions: ['canvas'])
    ],
  );
  if (location == null) return null;
  await File(location.path).writeAsString(
      const JsonEncoder.withIndent('  ').convert(_jsonCanvas(app.blocks, 'assets')));
  return location.path;
}

// ── Single-page InkML (OPEN-7) ────────────────────────────────────────────

Future<String?> exportPageInkML(AppState app) async {
  if (app.pageId == null) return null;
  await app.flushSave();
  final inkml = _inkML(app.blocks);
  final page = app.nodes.firstWhere((n) => n.id == app.pageId);
  final location = await getSaveLocation(
    suggestedName: '${safeFilename(page.title)}.inkml',
    acceptedTypeGroups: const [
      XTypeGroup(label: 'InkML', extensions: ['inkml', 'xml'])
    ],
  );
  if (location == null) return null;
  await File(location.path)
      .writeAsString(inkml ?? _emptyInkML());
  return location.path;
}

// ── Builders (pure; unit-testable) ────────────────────────────────────────

Map<String, dynamic> _mirrorMap(
        String pageId, PageProps props, List<Block> blocks) =>
    {
      'schema': 'onote-page/1',
      'pageId': pageId,
      'page': props.toJson(),
      'blocks': [for (final b in blocks) b.toJson()],
    };

class _Markdown {
  _Markdown(this.text, this.assets);
  final String text;
  final Map<String, String> assets; // hash -> relative asset path
}

/// Build the page's Markdown projection. [assetPrefix] is the POSIX-relative
/// path from the page folder to the shared `assets/` dir; image links use it.
/// The returned `assets` map (hash → "hash.ext") is collected by the caller and
/// written once into the shared store.
_Markdown _pageMarkdown(String title, List<Block> blocks, String assetPrefix) {
  final ordered = [...blocks]..sort((a, b) {
      final dy = a.y.compareTo(b.y);
      return dy != 0 ? dy : a.x.compareTo(b.x);
    });
  final buf = StringBuffer('# $title\n\n');
  final assets = <String, String>{};
  var inkCount = 0;
  for (final b in ordered) {
    switch (b.type) {
      case BlockType.text:
        buf.writeln(markdownInline(b.content['text'] as String? ?? '').trimRight());
        buf.writeln();
      case BlockType.math:
        final latex = b.content['latex'] as String? ?? '';
        if (latex.isNotEmpty) buf.writeln('\$\$\n$latex\n\$\$\n');
      case BlockType.graph:
        // A curve has no Markdown, so what travels is the equation it is
        // a curve OF — written as an equation on its own line, which a
        // re-import can do something with. A missing case here writes
        // nothing at all, which is how `board` was left out of this file
        // for a whole release.
        final gtex = b.content['latex'] as String? ?? '';
        if (gtex.isNotEmpty) {
          buf.writeln('Graph of:\n\n\$\$\n$gtex\n\$\$\n');
        }
      case BlockType.code:
        final lang = b.content['language'] as String? ?? '';
        buf.writeln('```$lang\n${b.content['source'] ?? ''}\n```\n');
      case BlockType.image:
        final hash =
            (b.content['blob'] as String? ?? '').replaceFirst('sha256:', '');
        if (hash.isNotEmpty) {
          final mime = b.content['mime'] as String? ?? 'image/png';
          final ext = mime.split('/').last.replaceFirst('jpeg', 'jpg');
          assets[hash] = '$hash.$ext';
          buf.writeln('![image]($assetPrefix/$hash.$ext)\n');
        }
      case BlockType.table:
        final table = tableToMarkdown(b.content['cells']);
        if (table.isNotEmpty) {
          buf.writeln(table);
          buf.writeln();
        }
      case BlockType.ink:
        inkCount += (b.content['strokes'] as List?)?.length ?? 0;
      default:
        break;
    }
  }
  if (inkCount > 0) {
    buf.writeln('> _This page also contains $inkCount ink strokes '
        '(see page.inkml for the vector data)._');
  }
  return _Markdown(buf.toString(), assets);
}

/// Map blocks to a JSON Canvas document (https://jsoncanvas.org/spec/1.0/).
/// [assetPrefix] is the POSIX-relative path from the output file to `assets/`.
Map<String, dynamic> _jsonCanvas(List<Block> blocks, String assetPrefix) {
  final nodes = <Map<String, dynamic>>[];
  for (final b in blocks) {
    final x = b.x.round();
    final y = b.y.round();
    final w = b.w.round().clamp(1, 100000);
    final h = (b.h ?? 60).round().clamp(1, 100000);
    switch (b.type) {
      case BlockType.text:
        nodes.add({
          'id': b.id,
          'type': 'text',
          'text': b.content['text'] as String? ?? '',
          'x': x, 'y': y, 'width': w, 'height': h,
        });
      case BlockType.graph:
        // JSON Canvas has no curve, so a graph travels as the text of its
        // equation. Better a readable node than a hole in the file.
        nodes.add({
          'id': b.id,
          'type': 'text',
          'text': 'Graph of \$${b.content['latex'] ?? ''}\$',
          'x': x, 'y': y, 'width': w, 'height': h,
        });
      case BlockType.math:
        final latex = b.content['latex'] as String? ?? '';
        nodes.add({
          'id': b.id,
          'type': 'text',
          'text': latex.isEmpty ? '' : '\$\$$latex\$\$',
          'x': x, 'y': y, 'width': w, 'height': h,
        });
      case BlockType.code:
        final lang = b.content['language'] as String? ?? '';
        nodes.add({
          'id': b.id,
          'type': 'text',
          'text': '```$lang\n${b.content['source'] ?? ''}\n```',
          'x': x, 'y': y, 'width': w, 'height': h,
        });
      case BlockType.table:
        nodes.add({
          'id': b.id,
          'type': 'text',
          'text': tableToMarkdown(b.content['cells']),
          'x': x, 'y': y, 'width': w, 'height': h,
        });
      case BlockType.image:
        final hash =
            (b.content['blob'] as String? ?? '').replaceFirst('sha256:', '');
        final mime = b.content['mime'] as String? ?? 'image/png';
        final ext = mime.split('/').last.replaceFirst('jpeg', 'jpg');
        nodes.add({
          'id': b.id,
          'type': 'file',
          'file': '$assetPrefix/$hash.$ext',
          'x': x, 'y': y, 'width': w, 'height': h,
        });
      default:
        break; // ink/file/embed have no JSON Canvas equivalent
    }
  }
  return {'nodes': nodes, 'edges': <Map<String, dynamic>>[]};
}

/// Build a W3C InkML document from every ink stroke on the page, or null if
/// the page has no ink. Channels X Y F (F = pressure, 0..1).
String? _inkML(List<Block> blocks) {
  final strokes = <Stroke>[];
  for (final b in blocks.where((b) => b.type == BlockType.ink)) {
    for (final sj in (b.content['strokes'] as List? ?? const [])) {
      strokes.add(Stroke.fromJson((sj as Map).cast<String, dynamic>()));
    }
  }
  if (strokes.isEmpty) return null;

  final buf = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<ink xmlns="http://www.w3.org/2003/InkML">')
    ..writeln('  <definitions>')
    ..writeln('    <inkSource xml:id="openote">')
    ..writeln('      <traceFormat>')
    ..writeln('        <channel name="X" type="decimal"/>')
    ..writeln('        <channel name="Y" type="decimal"/>')
    ..writeln('        <channel name="F" type="decimal" min="0" max="1"/>')
    ..writeln('        <channel name="T" type="integer" units="ms"/>')
    ..writeln('      </traceFormat>')
    ..writeln('    </inkSource>');
  // One brush per distinct (tool,color,size,opacity).
  final brushes = <String, String>{}; // key -> brush id
  for (final s in strokes) {
    final key = '${s.tool}|${s.colorHex}|${s.size}|${s.opacity}';
    brushes.putIfAbsent(key, () {
      final id = 'br${brushes.length + 1}';
      buf
        ..writeln('    <brush xml:id="$id">')
        ..writeln('      <brushProperty name="tool" value="${_xml(s.tool)}"/>')
        ..writeln('      <brushProperty name="color" value="${_xml(s.colorHex)}"/>')
        ..writeln('      <brushProperty name="width" value="${s.size}"/>')
        ..writeln('      <brushProperty name="opacity" value="${s.opacity}"/>')
        ..writeln('    </brush>');
      return id;
    });
  }
  buf.writeln('  </definitions>');
  for (final s in strokes) {
    final key = '${s.tool}|${s.colorHex}|${s.size}|${s.opacity}';
    final brushRef = brushes[key];
    final pts = <String>[];
    for (var i = 0; i < s.x.length; i++) {
      final pr = i < s.p.length ? s.p[i] : 1.0;
      final t = i < s.t.length ? s.t[i] : 0;
      pts.add('${_num(s.x[i])} ${_num(s.y[i])} ${_num(pr)} $t');
    }
    buf.writeln('  <trace brushRef="#$brushRef">${pts.join(', ')}</trace>');
  }
  buf.writeln('</ink>');
  return buf.toString();
}

String _emptyInkML() =>
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<ink xmlns="http://www.w3.org/2003/InkML"/>\n';

String _num(double v) {
  final r = (v * 100).roundToDouble() / 100; // 2 dp, drop trailing zeros
  return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
}

String _xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _uniqueDir(String parent, String name) {
  var candidate = p.join(parent, name);
  var i = 2;
  while (Directory(candidate).existsSync() || File(candidate).existsSync()) {
    candidate = p.join(parent, '$name-$i');
    i++;
  }
  return candidate;
}
