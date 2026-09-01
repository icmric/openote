import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../canvas/portal_view.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'onote_dialog.dart';

/// Insert a live page window (EMBED-2): pick a page, then drag out the area of
/// it to show — on a real rendering of the page, because choosing a region of
/// content you cannot see is guesswork. "Whole page" skips the drag.
Future<void> showInsertPortalDialog(
    BuildContext context, AppState app, Offset pagePt) {
  return showOnoteDialog<void>(
    context: context,
    builder: (_) => _InsertPortalDialog(app: app, at: pagePt),
  );
}

class _InsertPortalDialog extends StatefulWidget {
  const _InsertPortalDialog({required this.app, required this.at});

  final AppState app;
  final Offset at;

  @override
  State<_InsertPortalDialog> createState() => _InsertPortalDialogState();
}

class _InsertPortalDialogState extends State<_InsertPortalDialog> {
  String? _pageId;
  String _query = '';

  /// The dragged region, in source-page coordinates.
  Rect? _sel;
  Offset? _dragFrom;

  AppState get app => widget.app;

  void _insert(Rect? rect) {
    final b = app.addBlock(Block(
      type: BlockType.embed,
      x: widget.at.dx,
      y: widget.at.dy,
      w: 380,
      content: PortalRef.contentFor(_pageId!, rect: rect),
    ));
    app.select(b.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 780,
        height: 560,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _pageId == null ? _pickPage(context) : _pickRegion(context),
        ),
      ),
    );
  }

  // ── Step 1: which page ──────────────────────────────────────────────────

  Widget _pickPage(BuildContext context) {
    final q = _query.trim().toLowerCase();
    // The tree in sidebar order: sections head their pages. Filtering keeps a
    // section visible while any of its pages match.
    final rows = <Widget>[];
    var sectionShown = false;
    TreeNode? pendingSection;
    for (final n in app.nodes) {
      if (n.kind == NodeKind.section) {
        pendingSection = n;
        sectionShown = false;
        continue;
      }
      if (n.kind != NodeKind.page) continue;
      final title = n.title.isEmpty ? 'Untitled page' : n.title;
      if (q.isNotEmpty && !title.toLowerCase().contains(q)) continue;
      if (pendingSection != null && !sectionShown) {
        sectionShown = true;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
          child: Text(
            pendingSection.title.isEmpty ? 'Section' : pendingSection.title,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: OnoteColors.graphite400),
          ),
        ));
      }
      rows.add(ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: EdgeInsets.only(left: 8.0 + n.level * 16, right: 8),
        leading: const Icon(Icons.description_outlined, size: 15),
        title: Text(n.id == app.pageId ? '$title  (this page)' : title,
            style: const TextStyle(fontSize: 13)),
        onTap: () => setState(() {
          _pageId = n.id;
          _sel = null;
        }),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Page window', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
            'A live, read-only view of another page — it keeps up as that '
            'page changes.',
            style: TextStyle(fontSize: 12, color: OnoteColors.graphite400)),
        const SizedBox(height: 10),
        TextField(
          autofocus: true,
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search, size: 16),
            hintText: 'Find a page…',
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: Text('No pages match',
                      style: TextStyle(color: OnoteColors.graphite400)))
              : ListView(children: rows),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }

  // ── Step 2: which part of it ────────────────────────────────────────────

  Widget _pickRegion(BuildContext context) {
    final pageId = _pageId!;
    final title = portalTitle(app, pageId);
    final source = PortalSource.of(app, pageId);
    final extent = portalExtentOf(app, source.blocks);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 18),
            tooltip: 'Pick a different page',
            onPressed: () => setState(() {
              _pageId = null;
              _sel = null;
            }),
          ),
          Expanded(
            child: Text('Drag over "$title" to choose what the window shows',
                style: Theme.of(context).textTheme.titleSmall,
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            // Top-left aligned fit, so preview → page mapping is one divide.
            final s = math.min(box.maxWidth / extent.width,
                box.maxHeight / extent.height);
            final shownW = extent.width * s, shownH = extent.height * s;
            return Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: shownW,
                height: shownH,
                child: Stack(children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: dark ? OnoteColors.night0 : OnoteColors.paper0,
                        border: Border.all(
                            color: dark
                                ? OnoteColors.night300
                                : OnoteColors.paper300),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      alignment: Alignment.topLeft,
                      child: PortalContent(
                        app: app,
                        source: source,
                        rect: extent,
                        chain: [pageId],
                      ),
                    ),
                  ),
                  // The marquee, over everything: page coords = local / s.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (d) => setState(() {
                        _dragFrom = d.localPosition / s;
                        _sel = null;
                      }),
                      onPanUpdate: (d) => setState(() {
                        final from = _dragFrom;
                        if (from == null) return;
                        final to = Offset(
                          (d.localPosition.dx / s).clamp(0.0, extent.width),
                          (d.localPosition.dy / s).clamp(0.0, extent.height),
                        );
                        _sel = Rect.fromPoints(from, to);
                      }),
                      onPanEnd: (_) => setState(() {
                        _dragFrom = null;
                        final r = _sel;
                        if (r != null && (r.width < 16 || r.height < 16)) {
                          _sel = null; // a click, not a region
                        }
                      }),
                      child: CustomPaint(
                        painter: _MarqueePainter(
                          rect: _sel,
                          scale: s,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            );
          }),
        ),
        const SizedBox(height: 10),
        Row(children: [
          // A whole-page window onto the page it sits on shows itself
          // showing itself; the region path is fine, so only this is hidden.
          if (pageId != app.pageId)
            OutlinedButton(
              onPressed: () => _insert(null),
              child: const Text('Whole page'),
            ),
          const Spacer(),
          Text(
            _sel == null ? 'Drag to choose an area' : 'Area chosen',
            style:
                const TextStyle(fontSize: 12, color: OnoteColors.graphite400),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _sel == null ? null : () => _insert(_sel),
            child: const Text('Insert window'),
          ),
        ]),
      ],
    );
  }
}

class _MarqueePainter extends CustomPainter {
  _MarqueePainter({required this.rect, required this.scale, required this.color});

  final Rect? rect;
  final double scale;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = rect;
    if (r == null) return;
    final s = Rect.fromLTWH(r.left * scale, r.top * scale, r.width * scale,
        r.height * scale);
    canvas.drawRect(s, Paint()..color = color.withValues(alpha: .10));
    canvas.drawRect(
        s,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: .8));
  }

  @override
  bool shouldRepaint(covariant _MarqueePainter old) =>
      old.rect != rect || old.scale != scale || old.color != color;
}
