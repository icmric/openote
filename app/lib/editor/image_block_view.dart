import 'package:flutter/material.dart';

import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';

/// Image block: content-addressed blob reference (File Format Spec §3 blobs).
/// content: { blob: "sha256:…", mime, naturalW?, naturalH? }
class ImageBlockView extends StatelessWidget {
  const ImageBlockView({super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final hash = block.content['blob'] as String?;
    final bytes =
        hash == null ? null : app.repo.getBlob(app.notebookId!, hash);
    if (bytes == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.broken_image_outlined, color: OnoteColors.graphite400),
          SizedBox(width: 8),
          Text('Missing image', style: TextStyle(color: OnoteColors.graphite400)),
        ]),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: Image.memory(bytes, width: block.w, fit: BoxFit.contain),
    );
  }
}
