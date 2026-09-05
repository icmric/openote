/// **A notebook's own cross-references, made to work.**
///
/// PLANNING has asked for this since the OneNote importer existed: *"Ontenote
/// page links arent imported correctly. Start with onenote:https://…, would be
/// nice if we could attempt to convert this link to a page link within openote
/// … If a matching page cannot be found (as it could be linking to a notebook
/// that hasnt been imported, a deleted page, etc) please allow it to continue
/// linking to onenote."*
///
/// Counted on a real notebook: **142 `onenote:` links in sixty pages**. A
/// contents page is nothing but these, so leaving them all pointing back at
/// OneNote makes the imported copy a shell that keeps sending the student
/// somewhere else.
///
/// ## Why it happens after the import rather than during it
///
/// A link on the first page routinely points at the last one, so the mapping
/// from OneNote's page GUID to the page written for it is only complete once
/// everything has landed — and the import writes progressively on purpose, so
/// that a student can read the beginning while the end is still arriving.
/// Rewriting as we went would therefore fix the backward links and miss every
/// forward one, which is the worse half.
///
/// ## What is left alone, deliberately
///
/// A link whose target was not imported keeps its `onenote:` address exactly.
/// That is the owner's instruction and it is also the better behaviour: the
/// `onenote:` scheme opens OneNote, so an unresolved link still goes where it
/// was meant to go, whereas a rewritten-but-broken one goes nowhere.
library;

import 'graph_client.dart';

/// Rewrite every `onenote:` link in [markdown] whose page was imported.
///
/// Returns the text unchanged when nothing matched, so a caller can skip the
/// write entirely — most pages have no cross-references at all.
String relinkMarkdown(String markdown, Map<String, String> pageIdsByOneNoteId) {
  if (pageIdsByOneNoteId.isEmpty) return markdown;
  if (!markdown.contains('(onenote:')) return markdown;
  return markdown.replaceAllMapped(_link, (m) {
    final href = m.group(2)!;
    final guid = oneNotePageIdIn(href);
    final target = guid == null ? null : pageIdsByOneNoteId[guid];
    if (target == null) return m.group(0)!;
    return '[${m.group(1)}](onote://page/$target)';
  });
}

/// `[label](onenote:…)`.
///
/// The address runs to the closing bracket. OneNote writes `&` and `%` freely
/// in these and a literal `)` never appears — it arrives percent-encoded — so
/// stopping at the first one is safe and keeps the pattern simple.
final RegExp _link = RegExp(r'\[([^\]]*)\]\((onenote:[^)]*)\)');

/// Does this text hold a link worth rewriting?
bool hasOneNoteLink(String markdown) => markdown.contains('(onenote:');
