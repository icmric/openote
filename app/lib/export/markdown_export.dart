import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../model/models.dart';
import '../state/app_state.dart';

/// Page → Markdown export (OPEN-7 partial, MVP cut).
///
/// Freeform layout flattens to reading order (top-to-bottom, then
/// left-to-right) per the File Format Spec §8 note that page.md is the
/// convenience projection; page.json remains the fidelity path. Images are
/// written into an assets/ folder next to the .md, content-addressed.
Future<String?> exportPageMarkdown(AppState app) async {
  if (app.pageId == null) return null;
  final page = app.nodes.firstWhere((n) => n.id == app.pageId);
  final location = await getSaveLocation(
    suggestedName: '${_safe(page.title)}.md',
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Markdown', extensions: ['md'])
    ],
  );
  if (location == null) return null;

  final ordered = [...app.blocks]..sort((a, b) {
      final dy = a.y.compareTo(b.y);
      return dy != 0 ? dy : a.x.compareTo(b.x);
    });

  final buf = StringBuffer('# ${page.title}\n\n');
  var inkCount = 0;
  final assets = <String, String>{}; // hash -> filename

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
        final hash = (b.content['blob'] as String? ?? '').replaceFirst('sha256:', '');
        if (hash.isNotEmpty) {
          final mime = b.content['mime'] as String? ?? 'image/png';
          final ext = mime.split('/').last.replaceFirst('jpeg', 'jpg');
          final name = 'assets/$hash.$ext';
          assets[hash] = name;
          buf.writeln('![image]($name)\n');
        }
      case BlockType.ink:
        inkCount += (b.content['strokes'] as List?)?.length ?? 0;
      default:
        break;
    }
  }
  if (inkCount > 0) {
    buf.writeln('> _This page also contains $inkCount ink strokes '
        '(not representable in Markdown — see the .onote file or InkML export)._');
  }

  final outPath = location.path;
  await File(outPath).writeAsString(buf.toString());
  // Write referenced image assets next to the file.
  if (assets.isNotEmpty) {
    final assetDir = Directory(p.join(p.dirname(outPath), 'assets'));
    await assetDir.create(recursive: true);
    for (final e in assets.entries) {
      final bytes = app.repo.getBlob(app.notebookId!, e.key);
      if (bytes != null) {
        await File(p.join(p.dirname(outPath), e.value)).writeAsBytes(bytes);
      }
    }
  }
  return outPath;
}

String _safe(String s) {
  final cleaned = s.replaceAll(RegExp(r'[^\w\- ]'), '').trim();
  return cleaned.isEmpty ? 'page' : cleaned;
}
