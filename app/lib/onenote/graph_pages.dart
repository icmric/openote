/// **A OneNote page fetched over the internet, turned into the shape the
/// importer already understands.**
///
/// ## Why this exists
///
/// Openote could only take a notebook a human had exported from OneNote by
/// hand: open OneNote, find the notebook, File ▸ Export, wait, come back,
/// import. The owner: *"It already feels like a bit hostile design … this is
/// probably one of the highest friction parts of the whole app as it is right
/// as they are setting it up."*
///
/// It was worse than friction on two of the three platforms. **OneNote for Mac
/// cannot export a notebook at all** — no `.one`, no `.onepkg`, only a page at
/// a time as PDF — and there is no OneNote for Linux. Checked on the owner's
/// own machine, the usual workaround does not exist either: the whole OneDrive
/// tree contained exactly one stray `.one` and no `.onetoc2`, because a modern
/// notebook lives in OneNote's own cloud store and is never synced to disk as
/// files. So for a Mac user with a large notebook there was no route in at all.
///
/// Microsoft Graph is the one door open on every platform. It hands back a
/// page as HTML rather than as the binary revision store, which costs
/// fidelity — see [GraphPageLoss] — but it works from inside the app with one
/// sign-in and no export step.
///
/// ## What this file is, and is not
///
/// It is **pure**: HTML and bytes in, plain maps out. No network, no
/// authentication, no `AppState`. Everything expensive to get wrong is
/// therefore testable without a Microsoft account, which is the whole reason
/// the conversion is separated from the fetching.
///
/// The maps it produces are deliberately **the same shape the Rust parser
/// emits** for a `.one` file — `{name, group, section: {pages: […]}}`, each
/// page `{title, level, boxes, images}` — so every hard-won piece of the
/// existing translation is reused rather than rewritten: box geometry, in-flow
/// image rewriting, table column widths, restacking, tag mapping. A OneNote
/// page that arrives over the internet and one that arrives from a file go
/// through exactly the same code from here on.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// What a page lost on the way through Graph, so the import can say so.
///
/// Stated rather than hidden: notes that LOOK complete when something has
/// silently gone is the failure mode this project already refuses elsewhere
/// (the importer counts dropped ink strokes for the same reason).
class GraphPageLoss {
  GraphPageLoss();

  /// Pages that contained handwriting. Graph's HTML has no ink in it at all —
  /// there is no representation of a stroke in the format, so this is a
  /// limitation of the door, not of the reader.
  int inkPages = 0;

  /// Attachments (`<object>`) referenced but not fetched.
  int attachments = 0;

  /// Images whose bytes could not be fetched.
  int images = 0;

  bool get any => inkPages > 0 || attachments > 0 || images > 0;

  GraphPageLoss operator +(GraphPageLoss other) => GraphPageLoss()
    ..inkPages = inkPages + other.inkPages
    ..attachments = attachments + other.attachments
    ..images = images + other.images;
}

/// One image the page referenced, ready to be fetched.
class GraphImageRef {
  const GraphImageRef({
    required this.url,
    required this.index,
    this.width,
    this.height,
    this.inFlow = false,
  });

  /// The Graph resource URL. Fetched by the caller, which is the half that
  /// needs a token.
  final String url;

  /// Position in the page's image list, which is how in-flow images are
  /// referenced from box markdown (`onote-img://N`).
  final int index;

  final double? width;
  final double? height;

  /// Inside a paragraph's flow rather than floating on the canvas.
  final bool inFlow;
}

/// The result of reading one page's HTML: the page map the importer wants,
/// plus the images it still needs bytes for.
class GraphPage {
  const GraphPage({
    required this.page,
    required this.images,
    required this.loss,
  });

  /// `{title, level, boxes, images}` — the parser-shaped map.
  final Map<String, dynamic> page;

  /// Referenced images, in the order the page map's `images` list expects.
  final List<GraphImageRef> images;

  final GraphPageLoss loss;
}

/// OneNote's HTML default when a page carries no explicit position, in the
/// 120-dpi space the rest of the importer works in. Matches the left margin an
/// exported `.one` page lands on, so a mixed notebook does not have two
/// different ideas of where the text starts.
const double kGraphDefaultLeft = 48;
const double kGraphDefaultTop = 90;

/// Read one page of Graph HTML.
///
/// [title] and [level] come from the page's Graph metadata rather than from
/// the HTML, because the metadata is authoritative for both and the HTML's
/// `<title>` is occasionally empty on a page whose first line is a picture.
GraphPage readGraphPage(
  String htmlSource, {
  required String title,
  int level = 0,
  String? createdIso,
}) {
  final doc = html_parser.parse(htmlSource);
  final body = doc.body;
  final boxes = <Map<String, dynamic>>[];
  final images = <GraphImageRef>[];
  final imageMaps = <Map<String, dynamic>>[];
  final loss = GraphPageLoss();

  if (body != null) {
    // OneNote emits one absolutely-positioned <div> per outline when the page
    // uses absolute layout, which is the common case and maps one-to-one onto
    // Openote's positioned boxes. A page without them is a single flow, which
    // becomes one box at the default margin.
    final positioned = body.children
        .where((e) => e.localName == 'div' && _hasPosition(e))
        .toList();
    final roots = positioned.isNotEmpty ? positioned : [body];

    for (final root in roots) {
      final at = _positionOf(root);
      _readContainer(
        root,
        left: at.$1,
        top: at.$2,
        width: at.$3,
        boxes: boxes,
        images: images,
        imageMaps: imageMaps,
        loss: loss,
      );
    }
  }

  // Handwriting has no representation in Graph's HTML, so its absence cannot
  // be detected from the HTML either. The caller knows from the page metadata
  // whether ink was there; this flag is set by [markInkLost].
  final page = <String, dynamic>{
    'title': title,
    'level': level.clamp(0, 2),
    'boxes': boxes,
    'images': imageMaps,
    if (createdIso != null) 'created_iso': createdIso,
  };
  return GraphPage(page: page, images: images, loss: loss);
}

/// Walk one container, emitting a box per run of prose and a table per table.
void _readContainer(
  dom.Element root, {
  required double left,
  required double top,
  required double? width,
  required List<Map<String, dynamic>> boxes,
  required List<GraphImageRef> images,
  required List<Map<String, dynamic>> imageMaps,
  required GraphPageLoss loss,
}) {
  final markdown = StringBuffer();

  void flushText() {
    final text = markdown.toString().trimRight();
    if (text.trim().isEmpty) {
      markdown.clear();
      return;
    }
    boxes.add({
      'kind': 'text',
      'x': left,
      'y': top,
      if (width != null) 'w': width,
      'markdown': text,
    });
    markdown.clear();
  }

  for (final node in root.nodes) {
    if (node is! dom.Element) {
      // Loose text directly under the container — rare, but a page whose body
      // is a bare sentence is not worth losing.
      final text = node.text?.trim() ?? '';
      if (text.isNotEmpty) markdown.writeln(text);
      continue;
    }
    switch (node.localName) {
      case 'table':
        flushText();
        final cells = _readTable(node);
        if (cells.isNotEmpty && cells.first.isNotEmpty) {
          boxes.add({
            'kind': 'table',
            'x': left,
            'y': top,
            'cells': cells,
          });
        }
      case 'img':
        final ref = _readImage(node, images.length, inFlow: true);
        if (ref == null) {
          loss.images++;
          break;
        }
        images.add(ref);
        imageMaps.add({'x': left, 'y': top});
        // The same placeholder the `.one` parser writes, so the existing
        // rewrite step turns it into a stored blob reference and the picture
        // flows inside the paragraph rather than floating over it.
        final size = ref.width != null && ref.height != null
            ? ' =${ref.width!.round()}x${ref.height!.round()}'
            : '';
        markdown.writeln('![image](onote-img://${ref.index}$size)');
      case 'object':
        // An attachment. Graph gives a URL, but a file is not something the
        // page translation has a box for, so it is counted and reported
        // rather than silently dropped.
        loss.attachments++;
      case 'div':
        // A nested positioned div: its own box, at its own coordinates.
        flushText();
        final at = _positionOf(node);
        _readContainer(
          node,
          left: at.$1 == kGraphDefaultLeft ? left : at.$1,
          top: at.$2 == kGraphDefaultTop ? top : at.$2,
          width: at.$3 ?? width,
          boxes: boxes,
          images: images,
          imageMaps: imageMaps,
          loss: loss,
        );
      default:
        final md = _blockToMarkdown(node);
        if (md.isNotEmpty) markdown.writeln(md);
    }
  }
  flushText();
}

/// One block element as Markdown, which is what a text box stores.
String _blockToMarkdown(dom.Element el, {int depth = 0}) {
  switch (el.localName) {
    case 'h1':
      return '# ${_inline(el)}';
    case 'h2':
      return '## ${_inline(el)}';
    case 'h3':
      return '### ${_inline(el)}';
    case 'h4':
    case 'h5':
    case 'h6':
      return '#### ${_inline(el)}';
    case 'ul':
    case 'ol':
      final out = <String>[];
      var n = 1;
      for (final li in el.children.where((c) => c.localName == 'li')) {
        final pad = '  ' * depth;
        final marker = el.localName == 'ol' ? '${n++}.' : '-';
        // A checkbox in OneNote is a tag on the paragraph, not a list kind.
        final tag = li.attributes['data-tag'] ?? '';
        final box = tag.startsWith('to-do')
            ? (tag.contains('completed') ? '[x] ' : '[ ] ')
            : '';
        out.add('$pad$marker $box${_inlineExcludingLists(li)}'.trimRight());
        // Nested lists live inside the <li>.
        for (final sub in li.children
            .where((c) => c.localName == 'ul' || c.localName == 'ol')) {
          final nested = _blockToMarkdown(sub, depth: depth + 1);
          if (nested.isNotEmpty) out.add(nested);
        }
      }
      return out.join('\n');
    case 'p':
      final tag = el.attributes['data-tag'] ?? '';
      final text = _inline(el);
      if (text.isEmpty) return '';
      if (tag.startsWith('to-do')) {
        return '- ${tag.contains('completed') ? '[x]' : '[ ]'} $text';
      }
      return text;
    case 'br':
      return '';
    default:
      return _inline(el);
  }
}

/// A list item's own text, without the text of any list nested inside it.
///
/// `<li>top<ul><li>under</li></ul></li>` is legal and is what OneNote emits
/// for an indented bullet. Reading the item's whole subtree pulled the child's
/// words into the parent, so the line came out as `- topunder` with `under`
/// then repeated on the line below.
String _inlineExcludingLists(dom.Element li) {
  final shallow = li.clone(true);
  for (final child in shallow.children.toList()) {
    if (child.localName == 'ul' || child.localName == 'ol') child.remove();
  }
  return _inline(shallow);
}

/// Inline content as Markdown: the marks OneNote actually emits.
String _inline(dom.Node node) {
  final out = StringBuffer();
  for (final child in node.nodes) {
    if (child is dom.Text) {
      // `&nbsp;` arrives as U+00A0 and behaves like a space everywhere except
      // in a word count, where a run of them would read as one long word.
      out.write(child.data.replaceAll(' ', ' '));
      continue;
    }
    if (child is! dom.Element) continue;
    final inner = _inline(child);
    switch (child.localName) {
      case 'b':
      case 'strong':
        if (inner.trim().isNotEmpty) out.write('**$inner**');
      case 'i':
      case 'em':
        if (inner.trim().isNotEmpty) out.write('*$inner*');
      case 'u':
        if (inner.trim().isNotEmpty) out.write('<u>$inner</u>');
      case 'del':
      case 's':
      case 'strike':
        if (inner.trim().isNotEmpty) out.write('~~$inner~~');
      case 'code':
        if (inner.trim().isNotEmpty) out.write('`$inner`');
      case 'br':
        out.write('\n');
      case 'a':
        final href = child.attributes['href'];
        if (href == null || href.isEmpty) {
          out.write(inner);
        } else {
          out.write('[${inner.isEmpty ? href : inner}]($href)');
        }
      case 'span':
      case 'font':
        out.write(inner);
      default:
        out.write(inner);
    }
  }
  // Collapse the runs of whitespace HTML treats as one, but keep the explicit
  // line breaks `<br>` produced.
  return out
      .toString()
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .join('\n')
      .trim();
}

/// A table as the rectangular grid of per-cell Markdown the importer stores.
List<List<String>> _readTable(dom.Element table) {
  final rows = <List<String>>[];
  // `tbody` is implied by the HTML parser even when the source omits it, so
  // querying for `tr` anywhere below is both simpler and more tolerant.
  for (final tr in table.querySelectorAll('tr')) {
    final cells = <String>[];
    for (final td in tr.children) {
      if (td.localName != 'td' && td.localName != 'th') continue;
      cells.add(_inline(td));
    }
    if (cells.isNotEmpty) rows.add(cells);
  }
  if (rows.isEmpty) return const [];
  // Rectangular, because a ragged grid is not something a table block can
  // hold: pad short rows rather than dropping the row or the table.
  final width = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
  for (final r in rows) {
    while (r.length < width) {
      r.add('');
    }
  }
  return rows;
}

GraphImageRef? _readImage(dom.Element img, int index, {bool inFlow = false}) {
  // `data-fullres-src` is the original; `src` is OneNote's display copy. The
  // original is what somebody importing their notes wants.
  final url = img.attributes['data-fullres-src']?.trim().isNotEmpty == true
      ? img.attributes['data-fullres-src']!.trim()
      : (img.attributes['src']?.trim() ?? '');
  if (url.isEmpty) return null;
  return GraphImageRef(
    url: url,
    index: index,
    width: double.tryParse(img.attributes['width'] ?? ''),
    height: double.tryParse(img.attributes['height'] ?? ''),
    inFlow: inFlow,
  );
}

bool _hasPosition(dom.Element el) =>
    (el.attributes['style'] ?? '').contains('position:absolute');

/// `(left, top, width)` from an element's inline style, in the importer's
/// coordinate space. OneNote writes them in px at 96 dpi.
(double, double, double?) _positionOf(dom.Element el) {
  final style = el.attributes['style'] ?? '';
  double? read(String name) {
    final m = RegExp('$name\\s*:\\s*(-?[0-9.]+)\\s*px').firstMatch(style);
    if (m == null) return null;
    return double.tryParse(m.group(1)!);
  }

  return (
    read('left') ?? kGraphDefaultLeft,
    read('top') ?? kGraphDefaultTop,
    read('width'),
  );
}

/// Attach fetched bytes to a page's image list, in place.
///
/// Separated from [readGraphPage] because fetching needs a token and reading
/// does not — which is what keeps every rule above testable offline.
void attachImageBytes(
  Map<String, dynamic> page,
  List<GraphImageRef> refs,
  List<Uint8List?> bytes,
  GraphPageLoss loss,
) {
  final maps = (page['images'] as List?)?.cast<Map<String, dynamic>>();
  if (maps == null) return;
  for (var i = 0; i < maps.length && i < refs.length; i++) {
    final data = i < bytes.length ? bytes[i] : null;
    if (data == null || data.isEmpty) {
      loss.images++;
      continue;
    }
    maps[i]['bytes'] = data;
    if (refs[i].width != null) maps[i]['w'] = refs[i].width;
    if (refs[i].height != null) maps[i]['h'] = refs[i].height;
  }
  // An image whose bytes never arrived leaves a map with no `bytes`, which the
  // existing translation already skips — so a failed picture costs the picture
  // and nothing else on the page.
  maps.removeWhere((m) => m['bytes'] == null);
}

/// Wrap converted pages into the section shape the importer takes.
///
/// [group] is the section-group path, `/`-joined, exactly as the `.one` parser
/// reports it — the translation turns it into ` › ` for display.
Map<String, dynamic> graphSection({
  required String name,
  String? group,
  required List<Map<String, dynamic>> pages,
}) =>
    {
      'name': name,
      if (group != null && group.isNotEmpty) 'group': group,
      'section': {'pages': pages},
    };

/// The page's created time, as the importer's millisecond stamp.
int? createdMsFromIso(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  return DateTime.tryParse(iso)?.millisecondsSinceEpoch;
}

/// Debug helper: the JSON an importer test can be fed directly.
String encodeSections(List<Map<String, dynamic>> sections) =>
    const JsonEncoder.withIndent('  ').convert(sections);
