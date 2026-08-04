/// Printing (P13) — the same vector page, through the OS print dialog.
///
/// **Why this is four lines of real work.** Printing used to be pointless: the
/// exporter produced a 2× screenshot, so a printed revision sheet was a blurry
/// picture of a screen. Now that a page is emitted as text, vector ink and
/// embedded images, the thing that goes to the printer is the thing the printer
/// is good at — and `buildPagePdf` was factored out of the exporter for exactly
/// this and for annotated-slide re-export.
///
/// The document sets its own page size (see the sheet logic in
/// `pdf_vector_export.dart`, which follows the note's width and a slide's own
/// shape), so the format the dialog offers is deliberately ignored rather than
/// re-laid-out to A4: a 16:9 lecture slide should print as a 16:9 slide, and
/// the printer driver scales it to whatever paper is loaded.
library;

import 'package:printing/printing.dart';

import '../state/app_state.dart';
import 'pdf_vector_export.dart';

/// Send the open page to the printer. Returns false when there is nothing to
/// print or the user cancelled.
Future<bool> printCurrentPage(AppState app) async {
  final pageId = app.pageId;
  if (pageId == null) return false;
  final page = app.nodes.where((n) => n.id == pageId).firstOrNull;
  if (page == null) return false;
  return Printing.layoutPdf(
    name: page.title.isEmpty ? 'Openote page' : page.title,
    onLayout: (_) => buildPagePdf(app, pageId, title: page.title),
  );
}

/// Send a whole section — a lecture deck, a week's notes — to the printer.
Future<bool> printSection(AppState app, String sectionId) async {
  final section = app.nodes.where((n) => n.id == sectionId).firstOrNull;
  if (section == null || app.pagesOf(sectionId).isEmpty) return false;
  return Printing.layoutPdf(
    name: section.title.isEmpty ? 'Openote section' : section.title,
    onLayout: (_) => buildDeckPdf(app, sectionId, title: section.title),
  );
}
