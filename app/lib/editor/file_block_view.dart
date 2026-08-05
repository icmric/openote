import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/platform_open.dart';
import '../export/md_common.dart' show safeFilename;
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';

/// File attachment block (MEDIA-2): the file lives in the notebook's
/// content-addressed blob store; "Save a copy…" extracts it back out.
/// content: { blob: "sha256:…", name, mime, size }
class FileBlockView extends StatelessWidget {
  const FileBlockView({super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  @override
  Widget build(BuildContext context) {
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
      showDialog<bool>(
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
    if (bytes == null) return;
    final loc = await getSaveLocation(
        suggestedName: block.content['name'] as String? ?? 'file');
    if (loc == null) return;
    await File(loc.path).writeAsBytes(bytes);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved to ${loc.path}')));
    }
  }

  String _fmtSize(int b) => b < 1024
      ? '$b B'
      : b < 1024 * 1024
          ? '${(b / 1024).toStringAsFixed(1)} KB'
          : '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}
