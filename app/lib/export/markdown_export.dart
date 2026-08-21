import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../model/models.dart';
import '../state/app_state.dart';
import '../store/media_store.dart';
import 'md_common.dart';

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
    suggestedName: '${safeFilename(page.title, fallback: 'page')}.md',
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Markdown', extensions: ['md'])
    ],
  );
  if (location == null) return null;

  final assets = <String, String>{}; // hash -> filename
  final media = <String, String>{}; // stored media name -> filename
  final md = pageMarkdownOf(app, page.title, app.blocks,
      assetsOut: assets, mediaOut: media);

  final outPath = location.path;
  await File(outPath).writeAsString(md);
  // Write referenced image assets next to the file.
  if (assets.isNotEmpty) {
    final assetDir = Directory(p.join(p.dirname(outPath), 'assets'));
    await assetDir.create(recursive: true);
    for (final e in assets.entries) {
      final bytes = app.blob(e.key);
      if (bytes != null) {
        await File(p.join(p.dirname(outPath), e.value)).writeAsBytes(bytes);
      }
    }
  }
  await writeExportedMedia(app, outPath, media);
  return outPath;
}

/// Copy the videos and recordings [md] links to into the export's `assets/`.
///
/// **Streamed, not `readAsBytes`.** These are the files that are not in the
/// `blobs` table precisely because a lecture is hundreds of megabytes
/// (`media_store.dart`'s opening note); loading one whole to write it out
/// again would undo that on the one operation where the user is already
/// waiting. Same shape as "Save a copy…" in `video_block_view.dart`.
///
/// Best-effort per file: a notebook synced without its `media/` yet, or a
/// video whose bytes never arrived, must still produce a `.md` with all its
/// writing in it. The link is already in the Markdown either way — a missing
/// file next to it is a broken link, which is recoverable; failing the whole
/// export is not.
Future<void> writeExportedMedia(
    AppState app, String outPath, Map<String, String> media) async {
  if (media.isEmpty) return;
  final NotebookRef ref;
  try {
    ref = app.currentNotebook;
  } catch (_) {
    return; // no notebook open — nothing to resolve names against
  }
  final dir = Directory(p.join(p.dirname(outPath), 'assets'));
  await dir.create(recursive: true);
  for (final e in media.entries) {
    final src = MediaStore.resolve(ref, e.key);
    if (src == null) continue;
    try {
      final dst = File(p.join(p.dirname(outPath), e.value));
      final sink = dst.openWrite();
      await src.openRead().pipe(sink);
    } catch (_) {
      // Out of space, or a name the filesystem refused. The writing survives.
    }
  }
}

/// The Markdown projection of one page — the FUNCTION, shared by the file
/// exporter above and the external API's `read_page format: "markdown"`
/// (spec 14 §5), because two projections of the same page would drift.
///
/// Freeform layout flattens to reading order (top-to-bottom, then
/// left-to-right); page.json remains the fidelity path.
String pageMarkdownOf(AppState app, String title, List<Block> blocks,
    {Map<String, String>? assetsOut, Map<String, String>? mediaOut}) {
  final ordered = [...blocks]..sort((a, b) {
      final dy = a.y.compareTo(b.y);
      return dy != 0 ? dy : a.x.compareTo(b.x);
    });

  final buf = StringBuffer('# $title\n\n');
  var inkCount = 0;
  final assets = assetsOut ?? <String, String>{};
  final media = mediaOut ?? <String, String>{};

  for (final b in ordered) {
    switch (b.type) {
      case BlockType.text:
        buf.writeln(markdownInline(b.content['text'] as String? ?? '').trimRight());
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
      case BlockType.table:
        final table = tableToMarkdown(b.content['cells']);
        if (table.isNotEmpty) {
          buf.writeln(table);
          buf.writeln();
        }
      case BlockType.ink:
        inkCount += (b.content['strokes'] as List?)?.length ?? 0;
      case BlockType.graph:
        // Markdown has no picture of a curve, so it carries the equation the
        // curve is OF — which is the thing a reader (or a re-import) can do
        // something with. Silently writing nothing is what a missing case
        // does, and it is why this one is here.
        final latex = b.content['latex'] as String? ?? '';
        if (latex.isNotEmpty) buf.writeln('Graph of \$$latex\$\n');
      case BlockType.board:
        // A board's Markdown projection: one heading per column, cards as a
        // list. Round enough that a reader (or a re-import) keeps the
        // structure a human would reconstruct anyway.
        final columns = b.content['columns'];
        if (columns is List) {
          for (final col in columns.whereType<Map>()) {
            buf.writeln('## ${col['title'] ?? 'Column'}\n');
            for (final card in (col['cards'] as List? ?? const [])) {
              buf.writeln('- $card');
            }
            buf.writeln();
          }
        }
      case BlockType.embed:
        // EMBED-8's plain-link projection: Markdown cannot hold a live
        // window, so the export names the source and links to it rather than
        // silently dropping the block or inlining a stale copy.
        final ref = (b.content['ref'] as Map?)?.cast<String, dynamic>();
        final dst = ref?['pageId'] as String?;
        if (dst != null) {
          final title = app.nodes
                  .where((n) => n.id == dst)
                  .firstOrNull
                  ?.title
                  .trim() ??
              '';
          buf.writeln('> Window onto '
              '[${title.isEmpty ? 'another page' : title}](onote://page/$dst)'
              '\n');
        }
      case BlockType.file:
        // A video was silently GONE from the export ("Exporting a notebook to
        // Markdown does not carry copied-in videos yet", 0.4.2 known gaps):
        // `BlockType.file` fell through `default:` and wrote nothing at all,
        // so a page of lectures exported as a page with no lectures and no
        // sign there had ever been any.
        //
        // Same precedence the renderer uses (`file_block_view.dart`): a copied
        // -in file wins, then a link. The two are different things to a reader
        // — one is bytes we can carry, the other is a page on the internet
        // that only ever was a link — so they project differently.
        final stored = (b.content['media'] as String?)?.trim();
        final label = (b.content['name'] as String?)?.trim();
        if (stored != null && stored.isNotEmpty) {
          // **The name is checked before it becomes a path.** It comes out of
          // page content, which may have been imported or handed over by
          // someone else; `"media": "../../../../etc/passwd"` must not turn
          // into a read of that file and a copy of it into the export folder.
          // Same guard, same reason, as `MediaStore.resolve`.
          if (MediaStore.isValidName(stored)) {
            final name = media[stored] ??= _exportMediaName(
                stored, label, media.values.toSet());
            buf.writeln('[${label?.isNotEmpty == true ? label : name}]'
                '(${_mdPath(name)})\n');
          }
        } else {
          final url = (b.content['url'] as String?)?.trim();
          if (url != null && url.isNotEmpty) {
            buf.writeln('[${label?.isNotEmpty == true ? label : url}]($url)\n');
          }
        }
      default:
        break;
    }
  }
  if (inkCount > 0) {
    buf.writeln('> _This page also contains $inkCount ink strokes '
        '(not representable in Markdown — see the .onote file or InkML export)._');
  }
  return buf.toString();
}

/// What a copied-in video is called inside the export's `assets/`.
///
/// **The user's own filename, not the stored one.** On disk a video is a
/// UUIDv7 (`MediaStore.add`) because two copies of the same lecture must not
/// collide; an export folder is read by a person, and `0198f3c1-….mp4` tells
/// them nothing about which lecture it is. `Lecture 3.mp4` does.
///
/// The extension always comes from the STORED name, which `MediaStore.add`
/// already vetted — the display name is arbitrary text from a picker and could
/// carry none, or one that disagrees with the bytes.
///
/// [taken] holds the paths already handed out for this page, so two different
/// videos that were both called `lecture.mp4` do not export as one file that
/// is really the second one.
String _exportMediaName(String stored, String? label, Set<String> taken) {
  final ext = p.extension(stored);
  final base = safeFilename(
      p.basenameWithoutExtension(p.basename(label ?? '')),
      fallback: p.basenameWithoutExtension(stored));
  var candidate = 'assets/$base$ext';
  var n = 2;
  while (taken.contains(candidate)) {
    candidate = 'assets/$base ($n)$ext';
    n++;
  }
  return candidate;
}

/// A path as a Markdown link destination.
///
/// `[Lecture 3](assets/Lecture 3.mp4)` is not a link — the space ends the
/// destination and the rest becomes a title, so the one thing the reader wants
/// to click does nothing. Percent-encoding the segments is what makes a
/// filename with spaces in it survive into every Markdown reader.
String _mdPath(String path) =>
    path.split('/').map(Uri.encodeComponent).join('/');
