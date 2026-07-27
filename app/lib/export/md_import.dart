import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../model/models.dart';
import '../state/app_state.dart';

/// Markdown / Obsidian folder import (OPEN-9).
///
/// Picks a folder of `.md` files and brings it into the current notebook as a
/// new section. The directory tree maps to Openote's hierarchy: the chosen
/// folder becomes a **section**, each Markdown file becomes a **page**, and
/// nested folders become **folder pages** with their contents as subpages
/// (indent depth clamped to the 0–2 the data model allows). Each file's body
/// is placed as a single live-Markdown text block, so headings, lists,
/// checkboxes, tables and `[[wiki-links]]` render immediately. YAML front
/// matter is stripped (not preserved — out of scope for the MVP cut). A file
/// that can't be read (permissions, invalid UTF-8) is skipped rather than
/// aborting the whole import.
///
/// Returns the number of pages imported, or null if the user cancelled.
///
/// Not yet handled (tracked): local image references (`![](img.png)` /
/// `![[img.png]]`) are left as literal Markdown — they aren't pulled into the
/// content-addressed blob store, so they won't render until image import lands.
Future<int?> importMarkdownFolder(AppState app) async {
  if (app.notebookId == null) return null;
  final dir = await getDirectoryPath(confirmButtonText: 'Import this folder');
  if (dir == null) return null;

  final root = Directory(dir);
  if (!root.existsSync()) return 0;

  final nbId = app.notebookId!;
  final order = _PosCounter();

  // The import root becomes a section.
  final section = app.repo.upsertNode(
      nbId,
      TreeNode(
        kind: NodeKind.section,
        title: _titleFromName(p.basename(dir)),
        position: order.next(),
      ));

  var imported = 0;
  String? firstPageId;

  // Depth-first, directories before files, each alphabetical — a stable,
  // human-expected order that also keeps folder pages above their contents.
  void walk(Directory d, int level) {
    final List<FileSystemEntity> entries;
    try {
      entries = d.listSync()..sort(_byTypeThenName);
    } catch (_) {
      return; // unreadable directory — skip its subtree
    }
    for (final e in entries) {
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue; // skip .obsidian, .git, etc.
      if (e is Directory) {
        // A folder becomes a "folder page" that parents the pages inside it.
        final folderPage = app.repo.upsertNode(
            nbId,
            TreeNode(
              kind: NodeKind.page,
              parentId: section.id,
              level: level.clamp(0, 2),
              title: _titleFromName(name),
              position: order.next(),
            ));
        app.repo.writePage(nbId, folderPage.id, const [], PageProps());
        firstPageId ??= folderPage.id;
        imported++;
        walk(e, level + 1);
      } else if (e is File && _isMarkdown(e.path)) {
        String raw;
        try {
          raw = e.readAsStringSync();
        } catch (_) {
          continue; // unreadable / invalid-UTF-8 file — skip, don't abort
        }
        final body = _stripFrontMatter(raw);
        final title = _titleFromName(p.basenameWithoutExtension(e.path));
        final page = app.repo.upsertNode(
            nbId,
            TreeNode(
              kind: NodeKind.page,
              parentId: section.id,
              level: level.clamp(0, 2),
              title: title,
              position: order.next(),
            ));
        final blocks = <Block>[
          Block(
            type: BlockType.text,
            x: AppState.pageLeftMargin,
            y: AppState.contentTop,
            w: 640,
            content: {'text': _stripLeadingH1(body, title)},
          ),
        ];
        app.repo.writePage(nbId, page.id, blocks, PageProps());
        firstPageId ??= page.id;
        imported++;
      }
    }
  }

  walk(root, 0);

  // Refresh the navigator and jump to the first imported page.
  app.nodes = app.repo.loadNodes(nbId);
  if (firstPageId != null) {
    await app.selectPage(firstPageId);
  } else {
    app.refresh();
  }
  return imported;
}

int _byTypeThenName(FileSystemEntity a, FileSystemEntity b) {
  final ad = a is Directory ? 0 : 1;
  final bd = b is Directory ? 0 : 1;
  if (ad != bd) return ad.compareTo(bd);
  return p.basename(a.path).toLowerCase().compareTo(
      p.basename(b.path).toLowerCase());
}

bool _isMarkdown(String path) {
  final e = p.extension(path).toLowerCase();
  return e == '.md' || e == '.markdown' || e == '.mdx';
}

/// Append-ordered position generator: seeded from the current time (so imported
/// nodes sort after existing ones) then monotonically increasing, zero-padded to
/// the same 15-digit width AppState uses so lexicographic == numeric order.
class _PosCounter {
  final int _base = nowMs();
  int _i = 0;
  String next() => 'a${(_base + _i++).toString().padLeft(15, '0')}';
}

String _titleFromName(String name) {
  final t = name.replaceAll('_', ' ').trim();
  return t.isEmpty ? 'Untitled' : t;
}

/// Remove a leading YAML front-matter block if present. The opening AND closing
/// fences must each be a line that is exactly `---` (or `...` to close), so a
/// thematic-break `----` or a mid-document horizontal rule is never mistaken for
/// front matter and its content eaten.
String _stripFrontMatter(String text) {
  final lines = text.split('\n');
  if (lines.isEmpty || lines.first.trim() != '---') return text;
  for (var i = 1; i < lines.length; i++) {
    final t = lines[i].trim();
    if (t == '---' || t == '...') {
      return lines.skip(i + 1).join('\n').trimLeft();
    }
  }
  return text; // no closing fence → not front matter, leave untouched
}

/// If the file opens with `# Title` matching the page title, drop it — the
/// page already shows its title, so a duplicate H1 is noise.
String _stripLeadingH1(String body, String title) {
  final lines = body.split('\n');
  if (lines.isNotEmpty) {
    final first = lines.first.trim();
    if (first.startsWith('# ') &&
        first.substring(2).trim().toLowerCase() == title.toLowerCase()) {
      return lines.skip(1).join('\n').trimLeft();
    }
  }
  return body;
}
