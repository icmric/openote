import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../model/models.dart';
import '../state/app_state.dart';

/// Open-format exporters (OPEN-5/6/7): the "glass box" promise made real.
///
/// * [materializeNotebook] writes the whole notebook as a plain folder tree of
///   open files — one folder per section/page, each page carried by a
///   fidelity `page.json` (the mirror), a convenience `page.md`, a JSON Canvas
///   `page.canvas`, an `page.inkml` when the page has ink, and an `assets/`
///   folder of content-addressed blobs. Nothing here needs Openote to read.
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

  final nb = app.repo.notebooks.firstWhere((n) => n.id == app.notebookId);
  final root = _uniqueDir(dir, _safe(nb.title));
  await Directory(root).create(recursive: true);

  final byId = {for (final n in app.nodes) n.id: n};
  final manifestPages = <Map<String, dynamic>>[];
  final usedDirs = <String>{};

  for (final node in app.nodes.where((n) => n.kind == NodeKind.page)) {
    // Folder path = sanitized titles of every ancestor + this page, so the
    // section/group/subpage hierarchy is mirrored as nested folders.
    final segments = <String>[];
    TreeNode? cur = node;
    while (cur != null) {
      segments.insert(0, _safe(cur.title));
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

    final pageDir = p.join(root, rel);
    await Directory(pageDir).create(recursive: true);

    final data = app.repo.readPage(app.notebookId!, node.id);
    final blocks = data.blocks;

    // 1) Fidelity mirror.
    await File(p.join(pageDir, 'page.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(
            _mirrorMap(node.id, data.props, blocks)));

    // 2) Convenience Markdown + collected image assets.
    final md = _pageMarkdown(node.title, blocks);
    await File(p.join(pageDir, 'page.md')).writeAsString(md.text);

    // 3) JSON Canvas.
    await File(p.join(pageDir, 'page.canvas')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(_jsonCanvas(blocks)));

    // 4) InkML when there's ink.
    final inkml = _inkML(blocks);
    if (inkml != null) {
      await File(p.join(pageDir, 'page.inkml')).writeAsString(inkml);
    }

    // 5) Assets referenced by Markdown / canvas.
    if (md.assets.isNotEmpty) {
      final assetDir = Directory(p.join(pageDir, 'assets'));
      await assetDir.create(recursive: true);
      for (final e in md.assets.entries) {
        final bytes = app.repo.getBlob(app.notebookId!, e.key);
        if (bytes != null) {
          await File(p.join(pageDir, e.value)).writeAsBytes(bytes);
        }
      }
    }

    manifestPages.add({
      'id': node.id,
      'title': node.title,
      'path': rel.replaceAll('\\', '/'),
      'level': node.level,
    });
  }

  await File(p.join(root, 'manifest.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
    'format': 'openote-materialized/1',
    'notebook': {'id': nb.id, 'title': nb.title},
    'exportedAt': DateTime.now().toIso8601String(),
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
    suggestedName: '${_safe(page.title)}.canvas',
    acceptedTypeGroups: const [
      XTypeGroup(label: 'JSON Canvas', extensions: ['canvas'])
    ],
  );
  if (location == null) return null;
  await File(location.path).writeAsString(
      const JsonEncoder.withIndent('  ').convert(_jsonCanvas(app.blocks)));
  return location.path;
}

// ── Single-page InkML (OPEN-7) ────────────────────────────────────────────

Future<String?> exportPageInkML(AppState app) async {
  if (app.pageId == null) return null;
  await app.flushSave();
  final inkml = _inkML(app.blocks);
  final page = app.nodes.firstWhere((n) => n.id == app.pageId);
  final location = await getSaveLocation(
    suggestedName: '${_safe(page.title)}.inkml',
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

_Markdown _pageMarkdown(String title, List<Block> blocks) {
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
        buf.writeln((b.content['text'] as String? ?? '').trimRight());
        buf.writeln();
      case BlockType.math:
        final latex = b.content['latex'] as String? ?? '';
        if (latex.isNotEmpty) buf.writeln('\$\$\n$latex\n\$\$\n');
      case BlockType.code:
        final lang = b.content['language'] as String? ?? '';
        buf.writeln('```$lang\n${b.content['source'] ?? ''}\n```\n');
      case BlockType.image:
        final hash =
            (b.content['blob'] as String? ?? '').replaceFirst('sha256:', '');
        if (hash.isNotEmpty) {
          final mime = b.content['mime'] as String? ?? 'image/png';
          final ext = mime.split('/').last.replaceFirst('jpeg', 'jpg');
          final name = 'assets/$hash.$ext';
          assets[hash] = name;
          buf.writeln('![image]($name)\n');
        }
      case BlockType.table:
        final cells = b.content['cells'];
        if (cells is List && cells.isNotEmpty) {
          final rows = [
            for (final row in cells)
              [
                for (final c in (row as List))
                  (c?.toString() ?? '').replaceAll('|', r'\|')
              ]
          ];
          final cols = rows[0].length;
          buf.writeln('| ${rows[0].join(' | ')} |');
          buf.writeln('|${List.filled(cols, ' --- ').join('|')}|');
          for (final r in rows.skip(1)) {
            buf.writeln('| ${r.join(' | ')} |');
          }
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
Map<String, dynamic> _jsonCanvas(List<Block> blocks) {
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
          'text': _tableToMarkdown(b.content['cells']),
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
          'file': 'assets/$hash.$ext',
          'x': x, 'y': y, 'width': w, 'height': h,
        });
      default:
        break; // ink/file/embed have no JSON Canvas equivalent
    }
  }
  return {'nodes': nodes, 'edges': <Map<String, dynamic>>[]};
}

String _tableToMarkdown(dynamic cells) {
  if (cells is! List || cells.isEmpty) return '';
  final rows = [
    for (final row in cells)
      [
        for (final c in (row as List))
          (c?.toString() ?? '').replaceAll('|', r'\|')
      ]
  ];
  final cols = rows[0].length;
  final buf = StringBuffer()
    ..writeln('| ${rows[0].join(' | ')} |')
    ..writeln('|${List.filled(cols, ' --- ').join('|')}|');
  for (final r in rows.skip(1)) {
    buf.writeln('| ${r.join(' | ')} |');
  }
  return buf.toString().trimRight();
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
      pts.add('${_num(s.x[i])} ${_num(s.y[i])} ${_num(pr)}');
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

String _safe(String s) {
  final cleaned = s.replaceAll(RegExp(r'[^\w\- ]'), '').trim();
  return cleaned.isEmpty ? 'untitled' : cleaned;
}
