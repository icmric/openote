import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';

/// Image block: content-addressed blob reference (File Format Spec §3 blobs).
/// content: { blob: "sha256:…", mime, naturalW?, naturalH? }
///
/// Stateful so the decoded image + its provider are cached — this stops the
/// hover flicker (a fresh Image.memory each rebuild would blank for a frame)
/// and lets us record the intrinsic size for proportional resizing.
class ImageBlockView extends StatefulWidget {
  const ImageBlockView({super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  @override
  State<ImageBlockView> createState() => _ImageBlockViewState();
}

class _ImageBlockViewState extends State<ImageBlockView> {
  Uint8List? _bytes;
  MemoryImage? _provider;
  String? _hash;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ImageBlockView old) {
    super.didUpdateWidget(old);
    if (widget.block.content['blob'] != _hash) _load();
  }

  void _load() {
    _hash = widget.block.content['blob'] as String?;
    _bytes = _hash == null ? null : widget.app.repo.getBlob(widget.app.notebookId!, _hash!);
    _provider = _bytes == null ? null : MemoryImage(_bytes!);
    // Record intrinsic size once, so width-resize keeps aspect ratio.
    if (_bytes != null && widget.block.content['naturalW'] == null) {
      ui.decodeImageFromList(_bytes!, (img) {
        if (!mounted) return;
        widget.block.content['naturalW'] = img.width.toDouble();
        widget.block.content['naturalH'] = img.height.toDouble();
        // Persist it (once) so proportional resize, export and hit-testing all
        // agree without re-decoding on every load.
        widget.app.markDirty();
        setState(() {});
      });
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_provider == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.broken_image_outlined, color: OnoteColors.graphite400),
          SizedBox(width: 8),
          Text('Missing image', style: TextStyle(color: OnoteColors.graphite400)),
        ]),
      );
    }
    final nw = (widget.block.content['naturalW'] as num?)?.toDouble();
    final nh = (widget.block.content['naturalH'] as num?)?.toDouble();
    final aspect = (nw != null && nh != null && nh > 0) ? nw / nh : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: aspect != null
          // Known aspect: AspectRatio sizes height from the block width, so
          // resizing the width scales the image proportionally.
          ? AspectRatio(
              aspectRatio: aspect,
              child: Image(
                image: _provider!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              ),
            )
          : Image(
              image: _provider!,
              width: widget.block.w,
              fit: BoxFit.fitWidth,
              gaplessPlayback: true, // no blank frame on rebuild → no flicker
              filterQuality: FilterQuality.medium,
            ),
    );
  }
}
