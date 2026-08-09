import 'dart:convert';

import 'package:flutter/material.dart';

import '../editor/code_block_view.dart';
import '../editor/file_block_view.dart';
import '../editor/flashcard_block_view.dart';
import '../editor/image_block_view.dart';
import '../editor/math_block_view.dart';
import '../editor/onote_text_editor.dart';
import '../editor/table_block_view.dart';
import '../editor/text_block_view.dart';
import '../markdown/md_render.dart';
import '../model/models.dart';
import '../model/tags.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'ink_painter.dart';

/// Live page embeds (transclusion) — EMBED-2…7, Data Model Spec §7.
///
/// **A portal is a pointer, never a copy.** The block stores `(pageId, target)`
/// and nothing else; every render reads the source page through
/// `readPageShared`, whose cache is invalidated per page on write. That is the
/// whole liveness story: an edit to the source page — a local save, an undo, a
/// sync pull — evicts the cached decode, the next rebuild reads fresh content,
/// and the host page rebuilds on exactly the notifications it already gets.
/// Nothing subscribes, nothing polls, nothing is stored twice.
///
/// **Deviations from spec §7, deliberate for v1:**
///  * `snapshotBlob` is not written. A snapshot is a copy — the thing this
///    feature was asked not to make — and for a SAME-notebook embed the source
///    is always local, so the resolution order collapses to live → tombstone.
///    Snapshots become worth their bytes when cross-notebook embeds land.
///  * The spatial target is a raw `rect`, which §7.1 marks *discouraged* in
///    favour of frames — but frames are not implemented yet, and the shape is
///    the spec's own, so a later frame upgrade is additive.
///
/// **Read-only is enforced structurally**, not by asking each view to behave.
/// Interaction is a PER-TYPE policy, drawn on one line: anything that
/// *navigates or plays* works, anything that *writes* cannot exist.
///
///  * Text renders through [MarkdownView] directly with only the safe
///    callbacks wired — wiki-links and web links navigate/open, while the
///    checkbox and tag mutators are simply not passed, so their gesture
///    handlers are never constructed (`onTap: null`, not "onTap ignored").
///  * File and video cards stay fully interactive: play, open, save-a-copy
///    are all reads of the source, and playing a lecture inside the window
///    is half the point of having one.
///  * Everything else — images, tables, code, equations, flashcards — sits
///    under its own [IgnorePointer]; none of it has a read-only interaction
///    worth the risk of the write path it also carries.
///
/// Two backstops behind the policy: the blocks handed to every view are DEEP
/// COPIES with `portal:`-prefixed ids, so even a view that mutates its block
/// in build cannot touch the shared page cache — and a self-embedded page can
/// never match `editingBlockId` and wake the text editor's session machinery
/// on a block that is only a picture of itself. A [SelectionArea] over the
/// whole window keeps its text selectable for copying.
class PortalRef {
  const PortalRef({required this.pageId, required this.wholePage, this.rect});

  final String pageId;
  final bool wholePage;

  /// The source-page region, when [wholePage] is false.
  final Rect? rect;

  /// Spec §7.1 shape: `content.ref = {notebookId, pageId, target:{kind,…}}`.
  static PortalRef? parse(Map<String, dynamic> content) {
    final ref = content['ref'];
    if (ref is! Map) return null;
    final pageId = ref['pageId'];
    if (pageId is! String || pageId.isEmpty) return null;
    // Cross-notebook refs are written by nothing yet; refuse rather than
    // misrender another notebook's ids against this one.
    if (ref['notebookId'] != null) return null;
    final target = ref['target'];
    if (target is! Map) return null;
    switch (target['kind']) {
      case 'page':
        return PortalRef(pageId: pageId, wholePage: true);
      case 'rect':
        final x = (target['x'] as num?)?.toDouble();
        final y = (target['y'] as num?)?.toDouble();
        final w = (target['w'] as num?)?.toDouble();
        final h = (target['h'] as num?)?.toDouble();
        if (x == null || y == null || w == null || h == null) return null;
        if (w < 8 || h < 8) return null;
        return PortalRef(
            pageId: pageId, wholePage: false, rect: Rect.fromLTWH(x, y, w, h));
      default:
        // block / range / frame targets are speced but unimplemented; an
        // embed written by a later build renders as a chip, not a crash.
        return null;
    }
  }

  /// The spec-shaped content for a new embed block.
  static Map<String, dynamic> contentFor(String pageId, {Rect? rect}) => {
        'ref': {
          'notebookId': null,
          'pageId': pageId,
          'target': rect == null
              ? {'kind': 'page'}
              : {
                  'kind': 'rect',
                  'x': rect.left,
                  'y': rect.top,
                  'w': rect.width,
                  'h': rect.height,
                },
        },
        'scale': 'fit',
      };
}

/// The source page as the portal is allowed to see it: deep copies, prefixed
/// ids, decoded strokes — derived once per change of the underlying
/// [PageData] and shared by every portal onto the same page.
class PortalSource {
  PortalSource._(this._raw, this.blocks);

  final PageData _raw;

  /// Deep-copied blocks with `portal:` ids. Safe to hand to any view.
  final List<Block> blocks;

  final Map<String, List<Stroke>> _strokes = {};

  /// Decoded strokes for one ink block, decoded once per source change.
  List<Stroke> strokesOf(Block b) => _strokes.putIfAbsent(
      b.id,
      () => [
            for (final sj in (b.content['strokes'] as List? ?? const []))
              if (sj is Map) Stroke.fromJson(sj.cast<String, dynamic>()),
          ]);

  static final Map<String, PortalSource> _cache = {};

  /// The derived view of [pageId], rebuilt only when `readPageShared` hands
  /// back a different object — its cache is invalidated per page on every
  /// write, so object identity IS the revision.
  static PortalSource of(AppState app, String pageId) {
    final raw = app.readPageShared(pageId);
    final key = '${app.notebookId}/$pageId';
    final hit = _cache[key];
    if (hit != null && identical(hit._raw, raw)) return hit;
    if (_cache.length > 64) _cache.clear();
    final safe = [
      for (final b in raw.blocks)
        Block.fromJson((jsonDecode(jsonEncode(b.toJson())) as Map)
            .cast<String, dynamic>()
          ..['id'] = 'portal:${b.id}'),
    ];
    return _cache[key] = PortalSource._(raw, safe);
  }

  /// Drop everything, for tests that reuse page ids across repositories.
  @visibleForTesting
  static void resetCache() => _cache.clear();
}

/// The union extent of [blocks], for whole-page targets and the region picker.
/// Heights fall back to [AppState.estimatedHeight] — coarse, so callers pad.
Rect portalExtentOf(AppState app, List<Block> blocks) {
  var right = AppState.pageLeftMargin + 200.0, bottom = AppState.contentTop + 120.0;
  for (final b in blocks) {
    final h = b.h ?? app.estimatedHeight(b);
    if (b.x + b.w > right) right = b.x + b.w;
    if (b.y + h > bottom) bottom = b.y + h;
  }
  return Rect.fromLTRB(0, 0, right + 24, bottom + 40);
}

Rect _blockRectOf(AppState app, Block b) =>
    Rect.fromLTWH(b.x, b.y, b.w, b.h ?? app.estimatedHeight(b));

/// Renders a [rect] region of a source page's blocks at logical page scale,
/// clipped, using the same content views as a normal page. The caller decides
/// how big it appears (usually through a [FittedBox]) and whether it can be
/// interacted with (the block view wraps this in [IgnorePointer]; the region
/// picker does not, because it wants nothing interactive at all and gets that
/// from its own gesture layer sitting on top).
///
/// [chain] is the embed ancestry — the host page and every embedded page
/// above this one — for cycle detection (§7.5): a source already in the chain
/// renders as a chip, and depth is capped at 3 as the backstop.
class PortalContent extends StatelessWidget {
  const PortalContent({
    super.key,
    required this.app,
    required this.source,
    required this.rect,
    required this.chain,
  });

  final AppState app;
  final PortalSource source;
  final Rect rect;
  final List<String> chain;

  static const int maxDepth = 3;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Only what the window can show. The clip would hide the rest anyway;
    // not building it is what keeps a small window onto a huge page cheap.
    final visible = <Block>[];
    final strokes = <Stroke>[];
    for (final b in source.blocks) {
      if (!rect.overlaps(_blockRectOf(app, b).inflate(4))) continue;
      if (b.type == BlockType.ink) {
        strokes.addAll(source.strokesOf(b));
      } else {
        visible.add(b);
      }
    }
    visible.sort((a, b) => a.z.compareTo(b.z));

    // The inner surface is laid out at full page coordinates and shifted so
    // that `rect.topLeft` lands at the window's origin — the same page the
    // editor lays out, seen through a hole.
    final surfaceW = rect.right + 100, surfaceH = rect.bottom + 100;
    return SizedBox(
      width: rect.width,
      height: rect.height,
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -rect.left,
              top: -rect.top,
              child: SizedBox(
                width: surfaceW,
                height: surfaceH,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (strokes.isNotEmpty)
                      Positioned(
                        left: 0,
                        top: 0,
                        child: CustomPaint(
                          size: Size.zero,
                          painter: InkPainter(strokes,
                              autoColor: dark
                                  ? OnoteColors.moon100
                                  : OnoteColors.graphite900),
                        ),
                      ),
                    for (final b in visible)
                      Positioned(
                        left: b.x,
                        top: b.y,
                        child: _contentFor(context, b, dark),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The same dispatch as `BlockView`, minus the chrome, applying the
  /// interaction policy from the class comment: navigation and playback live,
  /// every write path structurally absent.
  Widget _contentFor(BuildContext context, Block b, bool dark) {
    switch (b.type) {
      case BlockType.text:
        // MarkdownView directly, BYPASSING both TextBlockView (whose State
        // owns edit-session lifecycle keyed on `editingBlockId`) and the
        // engine's buildReadOnly (which wires the checkbox/tag MUTATORS to
        // the app). Only the safe callbacks exist here: wiki-links navigate,
        // web links open through their own PlatformOpen allow-list, images
        // resolve. A checkbox with no callback is built with `onTap: null`.
        final w = TextBlockView.autoWidth(b, dark: dark);
        return SizedBox(
          width: w,
          child: Padding(
            padding: TextBlockView.insetFor(b),
            child: MarkdownView(
              text: OnoteEditors.active.deserialize(b.content),
              baseStyle: TextBlockView.baseStyle(b, dark: dark),
              onWikiLink: (label, id) => app.openWikiLink(label, id),
              imageResolver: (src) {
                final nb = app.notebookId;
                if (nb == null || !src.startsWith('sha256:')) return null;
                return app.blob(src);
              },
              // Tags are shown (they are part of how the page looks) but not
              // toggleable: no onToggleTag, no onToggleCheckbox.
              tagsByLine: NoteTag.byLine(b.content),
            ),
          ),
        );
      case BlockType.math:
        // Self-sizing, exactly as BlockView renders it in read mode.
        return IgnorePointer(child: MathBlockView(block: b, app: app));
      case BlockType.image:
        return IgnorePointer(
            child: SizedBox(width: b.w, child: ImageBlockView(block: b, app: app)));
      case BlockType.code:
        return IgnorePointer(
            child: SizedBox(width: b.w, child: CodeBlockView(block: b, app: app)));
      case BlockType.table:
        return IgnorePointer(
            child: SizedBox(width: b.w, child: TableBlockView(block: b, app: app)));
      case BlockType.file:
        // Interactive on purpose: playing a lecture recording or opening an
        // attachment READS the source page, and doing it in place is what the
        // user asked windows for. Every control on this card is a read.
        return SizedBox(width: b.w, child: FileBlockView(block: b, app: app));
      case BlockType.flashcard:
        return IgnorePointer(
            child: SizedBox(
                width: b.w, child: FlashcardBlockView(block: b, app: app)));
      case BlockType.embed:
        return _nested(context, b);
      default:
        return const SizedBox.shrink();
    }
  }

  /// An embed inside an embed. Renders live down to [maxDepth], then chips —
  /// and a page already on the chain chips immediately, which is what makes
  /// A-embeds-B-embeds-A terminate on screen and in export alike.
  Widget _nested(BuildContext context, Block b) {
    final ref = PortalRef.parse(b.content);
    if (ref == null) return _chip(context, Icons.crop_free, 'window');
    if (chain.contains(ref.pageId)) {
      return _chip(context, Icons.all_inclusive, 'circular window');
    }
    if (chain.length >= maxDepth) {
      return _chip(context, Icons.layers_outlined, portalTitle(app, ref.pageId));
    }
    final src = PortalSource.of(app, ref.pageId);
    final rect = ref.wholePage ? portalExtentOf(app, src.blocks) : ref.rect!;
    final h = b.w * (rect.height / rect.width);
    return Container(
      width: b.w,
      height: h,
      decoration: _portalBorder(context),
      clipBehavior: Clip.antiAlias,
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.topLeft,
        child: PortalContent(
          app: app,
          source: src,
          rect: rect,
          chain: [...chain, ref.pageId],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: _portalBorder(context),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: OnoteColors.graphite400),
          const SizedBox(width: 4),
          Text(label,
              style:
                  const TextStyle(fontSize: 11, color: OnoteColors.graphite400)),
        ]),
      );
}

BoxDecoration _portalBorder(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(6),
    border:
        Border.all(color: dark ? OnoteColors.night300 : OnoteColors.paper300),
  );
}

/// The source page's current title, surviving rename because the ref is by id
/// (EMBED-5); a title the tree no longer has means the recycle bin or a purge.
String portalTitle(AppState app, String pageId) {
  final n = app.node(pageId);
  if (n == null) return 'Deleted page';
  return n.title.isEmpty ? 'Untitled page' : n.title;
}

/// Is [pageId] still a live page in the tree?
bool portalSourceLive(AppState app, String pageId) => app.node(pageId) != null;

/// The embed block's content view: a badge naming the source, and underneath
/// it the live region — read-only, text-selectable, aspect-locked to the
/// region so resizing the block zooms the window instead of distorting it.
class PortalBlockView extends StatelessWidget {
  const PortalBlockView({super.key, required this.block, required this.app});

  final Block block;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final ref = PortalRef.parse(block.content);
    if (ref == null) {
      return _fallback(context, Icons.crop_free,
          'This window was made by a newer version of Openote.');
    }
    final live = portalSourceLive(app, ref.pageId);
    final src = PortalSource.of(app, ref.pageId);
    if (!live && src.blocks.isEmpty) {
      // Hard-gone: no tree node and no mirror. EMBED-6's tombstone, minus the
      // snapshot we deliberately do not keep.
      return _fallback(context, Icons.link_off,
          'The page this window pointed at was deleted.');
    }
    // Self-embed and cycles: the host page is the root of the chain.
    final hostPage = app.pageId;
    if (hostPage != null && ref.pageId == hostPage && ref.wholePage) {
      // A whole-page window onto its own page recurses by construction —
      // its extent includes itself. A region of its own page is fine.
      return _fallback(context, Icons.all_inclusive,
          'A window cannot show the whole of its own page.');
    }
    final rect = ref.wholePage ? portalExtentOf(app, src.blocks) : ref.rect!;
    if (rect.width < 8 || rect.height < 8) {
      return _fallback(context, Icons.crop_free, 'Nothing to show yet.');
    }

    final title = portalTitle(app, ref.pageId);
    final content = RepaintBoundary(
      // No blanket pointer-blocker here — interactivity is decided per block
      // type inside PortalContent (see the class comment): links navigate,
      // videos play, and nothing that writes is ever constructed. The
      // SelectionArea keeps the windowed text selectable for copying.
      child: SelectionArea(
        child: ClipRect(
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.topLeft,
            child: PortalContent(
              app: app,
              source: src,
              rect: rect,
              chain: [if (hostPage != null) hostPage, ref.pageId],
            ),
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Badge(
          title: title,
          live: live,
          onOpen: () => app.selectPage(ref.pageId),
        ),
        // Aspect-locked to the region: the block stores only a width, height
        // follows, and the one resize handle zooms the whole window.
        AspectRatio(
          aspectRatio: rect.width / rect.height,
          child: live ? content : Opacity(opacity: .5, child: content),
        ),
      ],
    );
  }

  Widget _fallback(BuildContext context, IconData icon, String message) =>
      Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          Icon(icon, size: 16, color: OnoteColors.graphite400),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    fontSize: 12, color: OnoteColors.graphite400)),
          ),
        ]),
      );
}

/// The quiet source badge (EMBED-3/4): names the page, opens it on click —
/// the one interactive surface a portal has.
class _Badge extends StatelessWidget {
  const _Badge({required this.title, required this.live, required this.onOpen});

  final String title;
  final bool live;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = live
        ? (dark ? OnoteColors.moon100 : OnoteColors.graphite700)
        : OnoteColors.graphite400;
    return Tooltip(
      message: live ? 'Open "$title"' : 'This page is in the recycle bin',
      child: InkWell(
        onTap: live ? onOpen : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(children: [
            Icon(Icons.open_in_new, size: 11, color: color),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                live ? title : '$title — deleted',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w500, color: color),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
