import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Paint a widget that is not on screen, and hand back the pixels.
///
/// **Why this exists.** The vector PDF exporter can emit text, paths and
/// images, and that covers everything Openote draws except one thing:
/// equations. Maths is laid out by `flutter_math_fork`, which is a widget
/// tree — there is no way to ask it for glyph positions, so the exporter wrote
/// the LaTeX source instead and a note full of algebra printed as backslashes.
///
/// "its fine to rasterise it into an image, it does not need to remain
/// selectable ... if we are able to render it on screen there must be a way to
/// render it in the pdf too". Quite so, and this is that way: build the same
/// widget against a private pipeline, drive one frame by hand, and read the
/// repaint boundary.
///
/// **Not on screen** is the whole difficulty. Exporting a section renders pages
/// that are closed and therefore never mounted, so borrowing a boundary from
/// the live tree does not work — the subtree has to be given an owner, a view
/// and a frame of its own.
///
/// Every failure returns null rather than throwing. A missing equation is a
/// bad export; an export that dies because one equation would not lay out is a
/// worse one, and the caller falls back to printing the source.
Future<Uint8List?> rasteriseOffscreen(
  Widget child, {
  double maxWidth = 2000,
  double pixelRatio = 3,
}) async {
  try {
    final boundary = RenderRepaintBoundary();
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final renderView = RenderView(
      view: view,
      // topLeft, and loose constraints: the boundary must shrink-wrap the
      // equation. Centring it inside a fixed box would bake whitespace into
      // the picture and the PDF would place the equation off its own baseline.
      child: RenderPositionedBox(
          alignment: Alignment.topLeft, child: boundary),
      configuration: ViewConfiguration(
        logicalConstraints: BoxConstraints(maxWidth: maxWidth),
        devicePixelRatio: pixelRatio,
      ),
    );
    final pipelineOwner = PipelineOwner()..rootNode = renderView;
    renderView.prepareInitialFrame();

    final buildOwner = BuildOwner(focusManager: FocusManager());
    final element = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    ).attachToRenderTree(buildOwner);

    buildOwner
      ..buildScope(element)
      ..finalizeTree();
    pipelineOwner
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();

    if (!boundary.hasSize || boundary.size.isEmpty) return null;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    // Drop the subtree so its render objects can be collected — an export of
    // fifty equations otherwise holds fifty live pipelines. Detaching the
    // root node is the supported way in; `Element.deactivate`/`unmount` are
    // framework-internal and the analyzer is right to refuse them.
    renderView.detach();
    pipelineOwner.rootNode = null;
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
