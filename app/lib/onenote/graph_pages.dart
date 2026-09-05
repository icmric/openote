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

/// **CSS pixels into the canvas's own space.**
///
/// Graph writes geometry as CSS px, which are 96 to the inch. The canvas works
/// at 120 — the `.one` importer beside this converts type as `sizePt * 120/72`
/// and every coordinate the Rust parser emits is in that space. Placing boxes
/// at 96-dpi coordinates while their text is laid out at 120 makes every line
/// a quarter wider than the box holding it, which is most of "many things are
/// just generally off": text overflows its box, wraps early, and a narrow one
/// wraps to a word or a letter a line.
const double kGraphPxToCanvas = 120.0 / 96.0;

/// Where a page's content starts when it says nothing, already in canvas
/// space. OneNote's own default outline sits half an inch in.
const double kGraphDefaultLeft = 48 * kGraphPxToCanvas;
const double kGraphDefaultTop = 90 * kGraphPxToCanvas;

/// Tag names that belong to a LINE rather than starting one.
///
/// This distinction is the whole of "some text new lines after every char".
/// OneNote does not always wrap a run in a `<p>` — a positioned outline can
/// hold `<span>`s, links and `<b>`s as direct children — and treating every
/// child element as a block put each of those runs on a line of its own. A
/// sentence broken into four styled spans came out as four lines, and one
/// broken per character came out per character.
const Set<String> kInlineTags = {
  'a', 'abbr', 'b', 'big', 'cite', 'code', 'del', 'em', 'font', 'i', 'kbd',
  'mark', 'q', 's', 'samp', 'small', 'span', 'strike', 'strong', 'sub',
  'sup', 'time', 'tt', 'u', 'var',
};

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

    // **One flow per outline, and this is not optional.**
    //
    // Every box an outline produces starts at that outline's origin, because
    // HTML says where the OUTLINE is and nothing about where the third
    // paragraph inside it ends up. `restackFlows` is what turns those
    // coincident boxes into a column, measuring each one's real height with a
    // TextPainter — but it only groups boxes that carry a `flow`, and skips
    // everything else. Emitting no flow meant nothing was ever restacked, so a
    // heading, its paragraph and its table were all written at the same point
    // and drawn on top of one another. That was "some tables are all over the
    // place".
    var flow = 0;
    for (final root in roots) {
      final at = _positionOf(root);
      _readContainer(
        root,
        left: at.$1,
        top: at.$2,
        width: at.$3,
        flow: ++flow,
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
  required int flow,
  required List<Map<String, dynamic>> boxes,
  required List<GraphImageRef> images,
  required List<Map<String, dynamic>> imageMaps,
  required GraphPageLoss loss,
}) {
  final markdown = StringBuffer();

  /// Append to the line being built. Inline runs and loose text use this.
  void writeInline(String text) {
    if (text.isEmpty) return;
    markdown.write(text);
  }

  /// Start a new line for a block. Never doubles a newline that is there.
  void writeBlock(String md) {
    if (md.isEmpty) return;
    final soFar = markdown.toString();
    if (soFar.isNotEmpty && !soFar.endsWith('\n')) {
      markdown.write('\n');
    }
    markdown
      ..write(md)
      ..write('\n');
  }

  void flushText() {
    final text = markdown.toString().trimRight();
    if (text.trim().isEmpty) {
      markdown.clear();
      return;
    }
    boxes.add({
      'kind': 'text',
      'flow': flow,
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
      // is a bare sentence is not worth losing. Appended, not given a line:
      // it is part of whatever run surrounds it.
      final text = node.text ?? '';
      if (text.trim().isNotEmpty) {
        writeInline(text.replaceAll('\u00A0', ' '));
      }
      continue;
    }
    // A styled run, a link, a bit of bold: part of the current line, and
    // carrying its OWN mark rather than only its children's.
    if (kInlineTags.contains(node.localName)) {
      writeInline(inlineElement(node));
      continue;
    }
    switch (node.localName) {
      case 'table':
        flushText();
        final cells = _readTable(node);
        if (cells.isNotEmpty && cells.first.isNotEmpty) {
          // **The widths OneNote chose, not a guess per column.** Without
          // them the importer falls back to 140 px a column clamped to
          // 240–900, which is wider than most real tables and the reason
          // *"they all default to larger when they should be smaller"* and
          // *"overlap horizontally"*: the box is right vertically, because
          // the rows are, and wrong across because every column was given
          // the same invented share of an invented total.
          final colW = _columnWidths(node, cells.first.length);
          boxes.add({
            'kind': 'table',
            'flow': flow,
            'x': left,
            'y': top,
            'cells': cells,
            if (colW != null) 'col_w': colW,
            if (colW != null)
              'w': colW.reduce((a, b) => a + b),
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
        writeBlock('![image](onote-img://${ref.index}$size)');
      case 'object':
        // An attachment. Graph gives a URL, but a file is not something the
        // page translation has a box for, so it is counted and reported
        // rather than silently dropped.
        loss.attachments++;
      case 'div':
        flushText();
        // A nested div that positions ITSELF is a separate outline and gets a
        // flow of its own; one that does not is part of this one and must keep
        // both the position and the flow, or the restacker treats it as an
        // unrelated anchor and leaves it sitting on its parent.
        final nested = _hasPosition(node);
        final at = _positionOf(node);
        _readContainer(
          node,
          left: nested ? at.$1 : left,
          top: nested ? at.$2 : top,
          width: (nested ? at.$3 : null) ?? width,
          flow: nested ? flow * 1000 + 1 : flow,
          boxes: boxes,
          images: images,
          imageMaps: imageMaps,
          loss: loss,
        );
      default:
        writeBlock(_blockToMarkdown(node));
    }
  }
  flushText();
}

/// One block element as Markdown, which is what a text box stores.
String _blockToMarkdown(dom.Element el, {int depth = 0}) {
  switch (el.localName) {
    case 'h1':
      return '# ${_inline(el).trim()}';
    case 'h2':
      return '## ${_inline(el).trim()}';
    case 'h3':
      return '### ${_inline(el).trim()}';
    case 'h4':
    case 'h5':
    case 'h6':
      return '#### ${_inline(el).trim()}';
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
        out.add('$pad$marker $box${_inlineExcludingLists(li).trim()}'
            .trimRight());
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
      final text = _inline(el).trim();
      if (text.isEmpty) return '';
      if (tag.startsWith('to-do')) {
        return '- ${tag.contains('completed') ? '[x]' : '[ ]'} $text';
      }
      return text;
    case 'br':
      return '';
    default:
      return _inline(el).trim();
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

/// Inline content as Markdown: the children of [node], with their own marks.
///
/// **Does not trim.** A fragment's leading and trailing spaces are what hold
/// it apart from the run beside it — trimming here glued `<span>Hello</span>`
/// to `<b> there</b>` and produced "Hellothere". Trimming happens once, where
/// a block or a whole box is finished.
String _inline(dom.Node node) {
  final out = StringBuffer();
  for (final child in node.nodes) {
    if (child is dom.Text) {
      // `&nbsp;` arrives as U+00A0 and behaves like a space everywhere except
      // in a word count, where a run of them would read as one long word.
      out.write(child.data.replaceAll('\u00A0', ' '));
      continue;
    }
    if (child is! dom.Element) continue;
    out.write(inlineElement(child));
  }
  return _collapseSpaces(out.toString());
}

/// One inline element **including the markup for its own tag**.
///
/// Separated from [_inline] because both callers need it and only one of them
/// used to have it: `_inline` applied a tag's marks while walking a parent's
/// children, so an element reached directly — a `<b>` sitting as a direct
/// child of a positioned outline, which OneNote emits freely — had its
/// contents read and its bold silently dropped.
String inlineElement(dom.Element el) {
  if (el.localName == 'br') return '\n';
  final inner = _inline(el);
  switch (el.localName) {
    case 'b':
    case 'strong':
      return _mark(inner, '**');
    case 'i':
    case 'em':
      return _mark(inner, '*');
    case 'del':
    case 's':
    case 'strike':
      return _mark(inner, '~~');
    case 'code':
      return _mark(inner, '`');
    case 'u':
      return _mark(inner, '<u>', close: '</u>');
    case 'a':
      final href = el.attributes['href'];
      if (href == null || href.isEmpty) return inner;
      final label = inner.trim();
      return label.isEmpty ? '[$href]($href)' : '[$label]($href)';
    default:
      return inner;
  }
}

/// Wrap [inner] in [marker], leaving its outer whitespace OUTSIDE the marks.
///
/// `** there**` is not bold in any Markdown renderer — emphasis cannot open on
/// a space — so the spaces are hoisted out and the words wrapped, giving
/// ` **there**`. Whitespace-only content is returned untouched rather than
/// wrapped around nothing.
String _mark(String inner, String marker, {String? close}) {
  final lead = RegExp(r'^\s*').firstMatch(inner)!.group(0)!;
  final tail = RegExp(r'\s*$').firstMatch(inner)!.group(0)!;
  if (lead.length + tail.length >= inner.length) return inner;
  final core = inner.substring(lead.length, inner.length - tail.length);
  return '$lead$marker$core${close ?? marker}$tail';
}

/// Runs of spaces and tabs collapse the way HTML lays them out, per line.
/// Explicit breaks from `<br>` survive.
String _collapseSpaces(String s) => s
    .split('\n')
    .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' '))
    .join('\n');

/// The width of each column, in canvas space, or null when OneNote did not
/// say.
///
/// Read from the first row, because that is where OneNote puts them and a
/// later row's spanned cell would measure the wrong thing. Returned only when
/// there is one width per column and all of them are sane — a partial or
/// nonsense array would stretch the wrong columns, which is worse than the
/// fallback it replaces.
List<double>? _columnWidths(dom.Element table, int columns) {
  final firstRow = table.querySelector('tr');
  if (firstRow == null) return null;
  final widths = <double>[];
  for (final cell in firstRow.children) {
    if (cell.localName != 'td' && cell.localName != 'th') continue;
    final style = cell.attributes['style'] ?? '';
    final m = RegExp(r'(?:^|[;{\s])width\s*:\s*([0-9.]+)\s*px')
        .firstMatch(style);
    final raw = m == null ? null : double.tryParse(m.group(1)!);
    if (raw == null || raw <= 1) return null;
    widths.add(raw * kGraphPxToCanvas);
  }
  return widths.length == columns ? widths : null;
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
      cells.add(_inline(td).trim());
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

/// `(left, top, width)` from an element's inline style, in the CANVAS's
/// coordinate space — Graph writes CSS px, which are 96 to the inch.
(double, double, double?) _positionOf(dom.Element el) {
  final style = el.attributes['style'] ?? '';
  double? read(String name) {
    // The property must START a declaration. Without the boundary, `left`
    // also matches `margin-left` and `padding-left` — and OneNote puts
    // `margin-left` on indented paragraphs, so an indented bullet dragged its
    // whole box to x=0 and left the rest of the outline behind it.
    final m = RegExp('(?:^|[;{\\s])$name\\s*:\\s*(-?[0-9.]+)\\s*px')
        .firstMatch(style);
    if (m == null) return null;
    final v = double.tryParse(m.group(1)!);
    return v == null ? null : v * kGraphPxToCanvas;
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
