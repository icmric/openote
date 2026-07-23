import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';

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
                    style: TextStyle(
                        fontSize: 11, color: OnoteColors.graphite400)),
              ],
            ),
          ),
          const SizedBox(width: 8),
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

  Future<void> _saveCopy(BuildContext context) async {
    final hash = block.content['blob'] as String?;
    if (hash == null) return;
    final bytes = app.repo.getBlob(app.notebookId!, hash);
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
