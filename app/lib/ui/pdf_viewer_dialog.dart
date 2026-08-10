import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'onote_dialog.dart';

/// The popup PDF viewer: the whole document behind a card or a slide, with
/// REAL text — select it, copy it — because the pages in here are drawn by
/// pdfium from the stored PDF, not from the raster the canvas shows.
///
/// Sized as a WINDOW over the page, not a takeover: "currently its the whole
/// page which is overwhelming". A reader popup should feel like holding the
/// document up, with the notebook still visibly behind it.
Future<void> showPdfViewerDialog(
  BuildContext context,
  AppState app, {
  required String hash,
  String? title,
  int initialPage = 0,
}) {
  final bytes = app.blob(hash);
  if (bytes == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("The PDF isn't on this computer yet — still syncing?")));
    return Future.value();
  }
  final controller = PdfViewerController();
  return showOnoteDialog<void>(
    context: context,
    builder: (context) {
      final screen = MediaQuery.of(context).size;
      // Enough to read an A4 page comfortably, never a takeover. Small
      // screens degrade toward full-window because there a big dialog IS
      // the only readable size.
      final w = math.min(760.0, screen.width * 0.72);
      final h = math.min(820.0, screen.height * 0.85);
      return Dialog(
        child: SizedBox(
          width: w,
          height: h,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(children: [
                const Icon(Icons.picture_as_pdf_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title ?? 'PDF',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                const Text('Drag to select text · Ctrl+C copies',
                    style: TextStyle(
                        fontSize: 11, color: OnoteColors.graphite400)),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: PdfViewer.data(
                bytes,
                sourceName: hash,
                controller: controller,
                initialPageNumber: initialPage + 1,
                params: PdfViewerParams(
                  // Selection is the point of this dialog existing.
                  textSelectionParams:
                      const PdfTextSelectionParams(enabled: true),
                  // A wheel tick at the default 0.2 moved barely a fifth of a
                  // screen — "scrolling doesn't take me very far". 1.0 is a
                  // real scroll step.
                  scrollByMouseWheel: 1.0,
                  // And a draggable thumb for covering a 100-page deck in one
                  // gesture — "nor is there a scroll bar to help moving large
                  // amounts".
                  viewerOverlayBuilder: (context, size, handleLinkTap) => [
                    PdfViewerScrollThumb(
                      controller: controller,
                      orientation: ScrollbarOrientation.right,
                      thumbSize: const Size(36, 80),
                      thumbBuilder:
                          (context, thumbSize, pageNumber, controller) =>
                              Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: .85),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${pageNumber ?? ''}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ]),
        ),
      );
    },
  );
}
