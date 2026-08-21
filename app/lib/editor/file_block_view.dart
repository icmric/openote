import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/platform_open.dart';
import '../export/md_common.dart' show safeFilename;
import '../media/pdf_pages.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';
import '../ui/pdf_viewer_dialog.dart';
import 'video_block_view.dart';
import '../ui/onote_dialog.dart';

/// File attachment block (MEDIA-2): the file lives in the notebook's
/// content-addressed blob store; "Save a copy…" extracts it back out.
/// content: { blob: "sha256:…", name, mime, size }
///
/// **Also the media LINK block (MEDIA-7).** A block with a `url` and no `blob`
/// is a link card — a lecture recording embedded in the page so it can be
/// reached from the notes rather than hunted for in a browser. It rides this
/// block type on purpose rather than taking a new one:
///
///   * `BlockType.embed` looks free but is not — the data-model spec and the
///     PRD reserve it for live page transclusion, which is the "read-only
///     version of one page visible inside another" ask sitting a few lines
///     further down PLANNING.md. Taking it for video would collide head-on.
///   * A brand-new enum value would be the honest choice, and it is now safe
///     to add one (see `Block.rawType`) — but it is still not free: every
///     build older than that fix renders it as "Unsupported block". A `file`
///     block degrades far better, because every shipped build already knows
///     the type.
///
/// What an OLD build does with a link card, exactly: it mounts this widget,
/// shows the icon and the correct name, and both buttons return early because
/// `content['blob']` is null. An inert, correctly-labelled card — and `url`
/// rides along untouched in `content`, so opening the same page in a current
/// build restores the feature completely.
class FileBlockView extends StatelessWidget {
  const FileBlockView({super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    // A recording kept in the notebook, played in the page. Checked before the
    // url and blob branches because it is neither: the bytes are a file beside
    // the container (store/media_store.dart), and an older build that knows
    // about neither still shows the right name on an inert card.
    final media = (block.content['media'] as String?)?.trim();
    if (media != null && media.isNotEmpty) {
      return VideoBlockView(block: block, app: app);
    }
    final url = (block.content['url'] as String?)?.trim();
    if (url != null && url.isNotEmpty) return _linkCard(context, url);
    // A PDF card: the deck behind a click, with a thumbnail so the page
    // reads as holding the document rather than a paperclip. Keyed on the
    // mime, so a plain .pdf attachment dropped before this existed upgrades
    // itself the next time it renders. An older build shows it as its
    // ordinary attachment card — same blob, both buttons still work.
    final blob = block.content['blob'] as String?;
    if (blob != null && block.content['mime'] == 'application/pdf') {
      return _pdfCard(context, blob);
    }
    final name = block.content['name'] as String? ?? 'file';
    final size = (block.content['size'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.attach_file,
              size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                Text(_fmtSize(size),
                    style: const TextStyle(
                        fontSize: 11, color: OnoteColors.graphite400)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.open_in_new, size: 16),
            visualDensity: VisualDensity.compact,
            tooltip: 'Open with the default app',
            onPressed: () => _openWithDefaultApp(context),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined, size: 16),
            visualDensity: VisualDensity.compact,
            tooltip: 'Save a copy…',
            onPressed: () => _saveCopy(context),
          ),
        ],
      ),
    );
  }

  /// The whole document behind a click: first page as the thumbnail, opened
  /// in the popup viewer where the text is selectable. "Embed my lectures
  /// into the page to be able to quickly reference in the future."
  Widget _pdfCard(BuildContext context, String blob) {
    final name = (block.content['name'] as String?)?.trim();
    final pages = (block.content['pages'] as num?)?.toInt();
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      // growFrom: the card's own centre — the viewer reads as the
      // thumbnail opening rather than a dialog appearing over it.
      onTap: () {
        final box = context.findRenderObject() as RenderBox?;
        showPdfViewerDialog(context, app,
            hash: blob,
            title: name,
            growFrom: box != null && box.hasSize
                ? box.localToGlobal(box.size.center(Offset.zero))
                : null);
      },
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: FutureBuilder<Uint8List?>(
              future: PdfPages.pageImage(app, blob, 0),
              builder: (context, snap) => snap.data == null
                  ? Container(
                      height: 120,
                      color: OnoteColors.paper100,
                      child: const Center(
                        child: Icon(Icons.picture_as_pdf_outlined,
                            size: 32, color: OnoteColors.graphite400),
                      ),
                    )
                  : Image.memory(snap.data!,
                      height: 160,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      gaplessPlayback: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(children: [
              Icon(Icons.picture_as_pdf_outlined,
                  size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name == null || name.isEmpty ? 'PDF' : name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    Text(
                        pages == null
                            ? 'Open — text is selectable'
                            : '$pages page${pages == 1 ? '' : 's'} — open to '
                                'read and copy',
                        style: const TextStyle(
                            fontSize: 11, color: OnoteColors.graphite400)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.download_outlined, size: 16),
                visualDensity: VisualDensity.compact,
                tooltip: 'Save a copy…',
                onPressed: () => _saveCopy(context),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  /// A link to something that lives outside the notebook — a lecture
  /// recording on a university site, a video, a page worth coming back to.
  ///
  /// Still a link and not a player, but for a narrower reason than it used to
  /// be. The old reason was that inline playback meant a media engine on three
  /// desktop platforms and the AppImage could not declare a system libmpv;
  /// Openote now ships a .deb and an .rpm, which can, so a video the user
  /// copies IN does play in the page (see video_block_view.dart). What stays
  /// true is that a URL is not a file: a YouTube or Panopto page is a web
  /// application, not a stream we can hand to a decoder, and pretending
  /// otherwise would mean embedding a browser. Those go to the browser.
  Widget _linkCard(BuildContext context, String url) {
    final scheme = Theme.of(context).colorScheme;
    final name = (block.content['name'] as String?)?.trim();
    final kind = block.content['kind'] as String?;
    final openable = PlatformOpen.isOpenableUrl(url);
    final host = Uri.tryParse(url)?.host ?? '';

    return InkWell(
      // Only wire the tap when the scheme is one we will actually hand to the
      // OS. A card that looks clickable and silently does nothing is worse
      // than one that plainly is not.
      onTap: openable ? () => _openLink(context, url) : null,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                kind == 'video'
                    ? Icons.play_circle_outline
                    : Icons.link_outlined,
                size: 22,
                color: openable ? scheme.primary : OnoteColors.graphite400),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name == null || name.isEmpty ? url : name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                  Text(
                      openable
                          ? (host.isEmpty ? url : host)
                          : 'Not a link this can open',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: OnoteColors.graphite400)),
                ],
              ),
            ),
            if (openable) ...[
              const SizedBox(width: 8),
              const Icon(Icons.open_in_new,
                  size: 14, color: OnoteColors.graphite400),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openLink(BuildContext context, String url) async {
    final ok = await PlatformOpen.url(url);
    if (!ok && context.mounted) _toast(context, "That link couldn't be opened.");
  }

  /// MEDIA-2: open the attachment in whatever application owns its type.
  ///
  /// The bytes live in the notebook's blob store, so there's no path to hand the
  /// OS — materialise a copy in the temp directory under the original filename
  /// (so the extension drives the file association) and open that.
  Future<void> _openWithDefaultApp(BuildContext context) async {
    final hash = block.content['blob'] as String?;
    if (hash == null) return;
    final bytes = app.blob(hash);
    if (bytes == null) {
      if (context.mounted) _toast(context, 'That attachment is missing.');
      return;
    }
    final name = (block.content['name'] as String?)?.trim();
    final safe = safeFilename(name == null || name.isEmpty ? 'attachment' : name);
    // A notebook can arrive from an import or a shared folder, so an
    // attachment is not necessarily something this user chose to put here.
    // Opening a document is safe; opening a program is a decision, and it
    // should be one the person makes on purpose.
    if (PlatformOpen.isExecutableName(safe)) {
      if (!context.mounted) return;
      final go = await _confirmRun(context, safe);
      if (go != true || !context.mounted) return;
    }
    try {
      final dir = await Directory.systemTemp.createTemp('onote_open_');
      final f = File(p.join(dir.path, safe));
      await f.writeAsBytes(bytes);
      final ok = await PlatformOpen.file(f.path);
      if (!ok && context.mounted) {
        _toast(context,
            'No app is registered for that file type — use “Save a copy…”.');
      }
    } catch (e) {
      if (context.mounted) _toast(context, "Couldn't open that attachment: $e");
    }
  }

  /// Ask before running a program that came out of a notebook.
  ///
  /// States what will happen rather than warning vaguely, and offers the safe
  /// alternative as the other button — the same shape §7h asks of every
  /// destructive-or-risky confirmation.
  Future<bool?> _confirmRun(BuildContext context, String filename) =>
      showOnoteDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Run this file?'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(filename, style: OnoteType.uiStrong),
                const SizedBox(height: OnoteSpace.x4),
                const Text(
                  'This attachment is a program, not a document — opening it '
                  'runs it. If the notebook came from someone else or was '
                  'imported, only continue if you know what this is.',
                  style: OnoteType.ui,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx, false);
                _saveCopy(context);
              },
              child: const Text('Save a copy instead'),
            ),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Run it')),
          ],
        ),
      );

  void _toast(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _saveCopy(BuildContext context) async {
    final hash = block.content['blob'] as String?;
    if (hash == null) return;
    final bytes = app.blob(hash);
    if (bytes == null) {
      // The SAME words the Open button gives for the same missing file. One
      // of the two used to explain it and the other silently did nothing.
      _toast(context, 'That attachment is missing.');
      return;
    }
    final loc = await getSaveLocation(
        suggestedName: block.content['name'] as String? ?? 'file');
    if (loc == null) return;
    try {
      await File(loc.path).writeAsBytes(bytes);
    } catch (e) {
      // A full stick, a protected folder: the write threw into an unhandled
      // Future and the student was told nothing at all.
      if (context.mounted) _toast(context, "That copy didn't save: $e");
      return;
    }
    if (context.mounted) _toast(context, 'Saved to ${loc.path}');
  }

  String _fmtSize(int b) => b < 1024
      ? '$b B'
      : b < 1024 * 1024
          ? '${(b / 1024).toStringAsFixed(1)} KB'
          : '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}
