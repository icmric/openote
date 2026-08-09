import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../state/app_state.dart';
import '../theme/onote_theme.dart';

/// The popup PDF viewer: the whole document behind a card or a slide, with
/// REAL text — select it, copy it — because the pages in here are drawn by
/// pdfium from the stored PDF, not from the raster the canvas shows.
///
/// "I want to then be able to click it and open it all in a popup window …
/// and not have to flick between the notebook and browser", and the other
/// half of "highlight and copy text from within it". Text selection is
/// pdfrx's own layer, enabled by default; Ctrl+C and the context menu both
/// copy.
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
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, box) => SizedBox(
          width: box.maxWidth,
          height: box.maxHeight,
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
                initialPageNumber: initialPage + 1,
                params: const PdfViewerParams(
                  // Selection is the point of this dialog existing.
                  textSelectionParams: PdfTextSelectionParams(enabled: true),
                ),
              ),
            ),
          ]),
        ),
      ),
    ),
  );
}
