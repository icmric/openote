import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../media/pdf_pages.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';

/// Image block: content-addressed blob reference (File Format Spec §3 blobs).
/// content: { blob: "sha256:…", mime, naturalW?, naturalH? }
///
/// Stateful so the decoded image + its provider are cached — this stops the
/// hover flicker (a fresh Image.memory each rebuild would blank for a frame)
/// and lets us record the intrinsic size for proportional resizing.
/// Content-addressed LRU for block-image bytes, shared across every
/// image view and every page. Keys are sha256 hashes, so an entry can
/// never be stale; the cap bounds memory, evicting least-recently-used.
class _BlobCache {
  static final _map = <String, Uint8List>{};
  static var _size = 0;
  static const _cap = 48 << 20; // 48 MB — a few pages of slides

  Uint8List? get(String h) {
    final v = _map.remove(h);
    if (v != null) _map[h] = v; // re-insert = most recent
    return v;
  }

  void put(String h, Uint8List b) {
    if (b.length > _cap) return;
    final old = _map.remove(h);
    if (old != null) _size -= old.length;
    _map[h] = b;
    _size += b.length;
    while (_size > _cap && _map.isNotEmpty) {
      final k = _map.keys.first;
      _size -= _map[k]!.length;
      _map.remove(k);
    }
  }
}

final _blobCache = _BlobCache();

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

  /// True while an on-demand PDF page render is in flight — the placeholder
  /// then says "rendering" rather than "missing", which are different facts.
  bool _rendering = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ImageBlockView old) {
    super.didUpdateWidget(old);
    final key = widget.block.content['pdf'] ?? widget.block.content['blob'];
    if (key != _hash) _load();
  }

  void _load() {
    // A slide is a REFERENCE — `{pdf: sha256:…, page: i}` — rendered on
    // demand (storage wave 1c). The PDF is stored once; the pixels exist
    // only while something is looking at them.
    final pdf = widget.block.content['pdf'] as String?;
    if (pdf != null) {
      _hash = pdf;
      final page = (widget.block.content['page'] as num?)?.toInt() ?? 0;
      final hit = PdfPages.cached(pdf, page);
      if (hit != null) {
        _bytes = hit;
        _provider = MemoryImage(hit);
        if (mounted) setState(() {});
        return;
      }
      _rendering = true;
      PdfPages.pageImage(widget.app, pdf, page).then((png) {
        if (!mounted || widget.block.content['pdf'] != pdf) return;
        setState(() {
          _rendering = false;
          _bytes = png;
          _provider = png == null ? null : MemoryImage(png);
        });
      });
      if (mounted) setState(() {});
      return;
    }
    final h = widget.block.content['blob'] as String?;
    _hash = h;
    if (h == null) {
      _bytes = null;
      _provider = null;
      if (mounted) setState(() {});
      return;
    }
    // Content-addressed LRU first: a hash can never go stale, so a hit IS
    // the bytes — revisiting a page costs no reads at all.
    final cached = _blobCache.get(h);
    if (cached != null) {
      _setBytes(cached);
      if (mounted) setState(() {});
      return;
    }
    // Cold read, DEFERRED. The fetch is a synchronous SQLite read —
    // megabytes for an imported slide — and doing it during build was THE
    // page-switch stall: every image on the incoming page was read
    // back-to-back before the first frame could paint ("about half a
    // second or so very consistently"). Reads now run after the frame,
    // one per event-loop turn through a shared queue, so the page appears
    // immediately and its pictures pop in over the next few frames.
    _rendering = true;
    _readQueue = _readQueue.then((_) async {
      await Future<void>.delayed(Duration.zero);
      if (!mounted || widget.block.content['blob'] != h) return;
      final b = widget.app.blob(h);
      if (b != null) _blobCache.put(h, b);
      if (!mounted || widget.block.content['blob'] != h) return;
      setState(() {
        _rendering = false;
        _setBytes(b);
      });
    });
    if (mounted) setState(() {});
  }

  /// One event-loop turn between blob reads, shared by every image on the
  /// page — the stagger that keeps any single frame cheap.
  static Future<void> _readQueue = Future<void>.value();

  void _setBytes(Uint8List? b) {
    _bytes = b;
    _provider = b == null ? null : MemoryImage(b);
    // Record intrinsic size once, so width-resize keeps aspect ratio.
    if (b != null && widget.block.content['naturalW'] == null) {
      ui.decodeImageFromList(b, (img) {
        if (!mounted) return;
        widget.block.content['naturalW'] = img.width.toDouble();
        widget.block.content['naturalH'] = img.height.toDouble();
        // Persist it (once) so proportional resize, export and hit-testing
        // all agree without re-decoding on every load.
        widget.app.markDirty();
        setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_provider == null && _rendering) {
      // The slide's own footprint, so the page does not reflow when the
      // pixels arrive a frame or two later.
      return SizedBox(
        width: widget.block.w,
        height: widget.block.h,
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_provider == null) {
      final isPdf = widget.block.content['pdf'] != null;
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(isPdf ? Icons.picture_as_pdf_outlined : Icons.broken_image_outlined,
              color: OnoteColors.graphite400),
          const SizedBox(width: 8),
          Text(isPdf ? 'PDF not here yet — still syncing?' : 'Missing image',
              style: const TextStyle(color: OnoteColors.graphite400)),
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
