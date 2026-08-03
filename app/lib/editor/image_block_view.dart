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
    _bytes = _hash == null ? null : widget.app.blob(_hash!);
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
    final boxH = widget.block.h;
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      // Anchor top-left, always.
      //
      // This is why imported images sat **too high**. `BlockView` gives the block
      // a container of exactly `w × h` — OneNote's own display rectangle — and an
      // `AspectRatio` child derives its height from the width instead. When the
      // stored rectangle's aspect doesn't quite match the PNG's, the child ends
      // up a different height from the container, and a `Container` with one
      // child **centres** it: the image shifted up by half the difference, which
      // is exactly the "layout is right, just offset vertically" symptom. It was
      // also `BoxFit.cover`, so the mismatch was cropped rather than visible.
      child: Align(
        alignment: Alignment.topLeft,
        child: boxH != null
            // Imported (or explicitly sized): honour OneNote's rectangle exactly
            // and fit inside it — never crop, never shift.
            ? Image(
                image: _provider!,
                width: widget.block.w,
                height: boxH,
                fit: BoxFit.contain,
                alignment: Alignment.topLeft,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              )
            : aspect != null
                // Auto-height: derive the height from the width so a width
                // resize scales the image proportionally.
                ? AspectRatio(
                    aspectRatio: aspect,
                    child: Image(
                      image: _provider!,
                      fit: BoxFit.contain,
                      alignment: Alignment.topLeft,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                    ),
                  )
                : Image(
                    image: _provider!,
                    width: widget.block.w,
                    fit: BoxFit.fitWidth,
                    alignment: Alignment.topLeft,
                    gaplessPlayback: true, // no blank frame on rebuild
                    filterQuality: FilterQuality.medium,
                  ),
      ),
    );
  }
}
