import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../core/platform_open.dart';
import '../model/tags.dart';
import '../theme/onote_theme.dart';
import 'md_syntax.dart';
import 'md_table.dart';
import '../editor/flashcard_view.dart';
import '../study/flashcards.dart' show inlineCardRe;

/// Interim inline-Markdown rendering (TEXT-2/4 at block granularity):
/// a text block RENDERS its Markdown when not being edited and reveals the
/// raw source while editing. The ADR-0004 bake-off winner replaces this with
/// true as-you-type span-level rendering; this module keeps the same dialect
/// (Data Model Spec §5.2 subset): #/##/### headings, - bullets, 1. numbered,
/// - [ ]/- [x] checkboxes, > quotes, ``` fences, **bold**, *italic*,
/// `code`, ~~strike~~, ==highlight==, and in-flow images
/// `![alt](sha256:<hash>)` resolved from the notebook blob store (Data Model
/// §5.1: a text block is a container of mixed content — images flow WITH the
/// text, OneNote-style, rather than floating over it).
// Line patterns, compiled ONCE. These used to be constructed inside
// `_renderLine`, i.e. eight `RegExp`s per line — ~4000 allocations to parse a
// 500-line imported text block, re-paid on every edit of that block.
final _reHeading = RegExp(r'^(#{1,3})\s+(.*)$');
final _reCheckbox = mdCheckboxRe;
final _reCheckMark = RegExp(r'\[(x|X)\]');
// `* item` and `+ item` are bullets too — this used to accept only `-`,
// so the editor greyed a `* ` marker the reader then ignored.
final _reBullet = mdBulletRe;
final _reNumbered = mdNumberedRe;
final _reImage =
    RegExp(r'^(\s*)!\[([^\]]*)\]\(([^)\s]+)(?:\s+=(\d+)x(\d+))?\)\s*$');
final _reQuote = RegExp(r'^>\s?(.*)$');
final _reDisplayMath = RegExp(r'^\s*\$\$(.+)\$\$\s*$');
final _reDivider = mdDividerRe;
// A plain paragraph carrying the 2-spaces-per-level indent encoding. Only
// matched after every other line form, so lists/checkboxes/images (which do
// their own indent handling) never reach it.
final _rePlainIndent = RegExp(r'^( +)(\S.*)$');
// The inline alternation now lives in md_syntax.dart, shared with the live
// editor so reading and writing cannot drift apart.

/// Indent per nesting level, as a multiple of the text's font size.
///
/// **Measured from OneNote's own PDF export** — the left edge of each nesting
/// level, divided by the font size, on two unrelated pages:
///
/// | sample                   | font size | indent step | ratio |
/// |--------------------------|-----------|-------------|-------|
/// | `Lecture.pdf`            | 8.400 pt  | 20.60 pt    | 2.452 |
/// | `Lecture p2 …pdf`        | 10.728 pt | 26.20 pt    | 2.442 |
///
/// Two things follow. First, the indent is **proportional to font size**, not a
/// fixed pixel step — which is also just correct typography. Second, ours was a
/// flat `6px` per leading space (12px per level, since the importer emits two
/// spaces per level), i.e. barely a quarter of OneNote's ~45px for 11pt text, so
/// nested bullets sat far left of where the source had them.
const double kIndentPerLevel = 2.45;

/// Width of the list-marker gutter. The bullet/number hangs here so the body
/// text starts on the indent itself (OneNote does the same).
const double kBulletGutter = 22.0;

/// Leading spaces → indent in logical pixels. The importer (and Markdown
/// convention) use two spaces per nesting level.
double indentPx(int leadingSpaces, double? fontSize) =>
    (leadingSpaces / 2.0) * kIndentPerLevel * (fontSize ?? 14.0);

class MarkdownView extends StatefulWidget {
  const MarkdownView({
    super.key,
    required this.text,
    required this.baseStyle,
    this.onToggleCheckbox,
    this.onWikiLink,
    this.imageResolver,
    this.tagsByLine = const {},
    this.onToggleTag,
  });

  final String text;
  final TextStyle baseStyle;

  /// Called with the new full text when a checkbox line is toggled.
  final void Function(String newText)? onToggleCheckbox;

  /// Tags on this block, by 0-based line index (TEXT-5). Rendered as markers
  /// in the line's left gutter — OneNote's model, where a tag decorates a
  /// paragraph rather than living in its text.
  final Map<int, List<NoteTag>> tagsByLine;

  /// Called when a to-do marker is clicked.
  final void Function(int line, bool checked)? onToggleTag;

  /// Called when a `[[Page|id]]` link is tapped (EMBED-1).
  final void Function(String label, String? id)? onWikiLink;

  /// Resolves an image src (e.g. `sha256:<hash>`) to bytes, typically from the
  /// notebook's content-addressed blob store. Null → image lines render as
  /// their literal Markdown.
  final Uint8List? Function(String src)? imageResolver;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

/// Stateful ONLY for the parse cache: a page canvas rebuilds every visible
/// block on each app notify (drag frames, ink commits, typing elsewhere), and
/// re-parsing every text block's Markdown per frame made busy imported pages
/// sluggish. The built subtree is cached and returned identical while
/// (text, style, theme) are unchanged — identical child widgets short-circuit
/// Flutter's rebuild of the whole subtree.
class _MarkdownViewState extends State<MarkdownView> {
  /// Decoded-bytes cache so scrolling doesn't re-query SQLite per frame; the
  /// blob store is content-addressed, so entries can never go stale. Only
  /// successful reads are cached — a miss (e.g. blob not yet written) retries.
  static final Map<String, Uint8List> _imgCache = {};

  Widget? _built;
  String? _builtText;
  TextStyle? _builtStyle;
  bool? _builtDark;

  String get text => widget.text;
  TextStyle get baseStyle => widget.baseStyle;
  void Function(String newText)? get onToggleCheckbox => widget.onToggleCheckbox;
  void Function(String label, String? id)? get onWikiLink => widget.onWikiLink;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (_built != null &&
        _builtText == text &&
        _builtStyle == baseStyle &&
        _builtDark == dark) {
      return _built!;
    }
    final built = _buildFresh(context, dark);
    _built = built;
    _builtText = text;
    _builtStyle = baseStyle;
    _builtDark = dark;
    return built;
  }

  Widget _buildFresh(BuildContext context, bool dark) {
    final lines = text.split('\n');
    final children = <Widget>[];
    var inFence = false;
    final fenceBuf = <String>[];

    void flushFence() {
      if (fenceBuf.isEmpty) return;
      children.add(Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: dark ? OnoteColors.night100 : OnoteColors.paper100,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(fenceBuf.join('\n'),
            style: baseStyle.copyWith(fontFamily: 'JetBrains Mono', fontFamilyFallback: onoteFontFallback, fontSize: 13)),
      ));
      fenceBuf.clear();
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('```')) {
        if (inFence) {
          flushFence();
        }
        inFence = !inFence;
        continue;
      }
      if (inFence) {
        fenceBuf.add(line);
        continue;
      }
      // GFM pipe table. Checked before the per-line path because a table is a
      // multi-line construct — rendering its rows one at a time is exactly what
      // produced the raw-pipes output this replaces.
      final table = parsePipeTable(lines, i);
      if (table != null) {
        children.add(_renderTable(context, table.table, dark));
        i += table.consumed - 1; // the loop's own i++ consumes the last line
        continue;
      }
      children.add(_withTagGutter(i, _renderLine(context, line, i, dark)));
    }
    if (inFence) flushFence();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children.isEmpty ? [Text(' ', style: baseStyle)] : children,
    );
  }

  /// Prefix a rendered line with its tag markers, if it has any.
  ///
  /// A hanging gutter rather than inline content: the tag decorates the
  /// paragraph, so it must not shift the text or become part of it when the
  /// line is edited.
  Widget _withTagGutter(int lineIndex, Widget line) {
    final tags = widget.tagsByLine[lineIndex];
    if (tags == null || tags.isEmpty) return line;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final t in tags)
              if (t.kind == TagKind.todo)
                InkWell(
                  onTap: widget.onToggleTag == null
                      ? null
                      : () => widget.onToggleTag!(lineIndex, !(t.checked ?? false)),
                  child: Icon(
                      (t.checked ?? false)
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 15,
                      color: t.kind.color),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 1),
                  child: Tooltip(
                    message: t.displayLabel,
                    child: Icon(t.kind.icon, size: 14, color: t.kind.color),
                  ),
                ),
            // The deadline, in the note. A due date visible only inside the
            // planner would be a fact about this line that this line does not
            // show — so you would have to remember to go and look, which is the
            // failure the planner itself exists to fix.
            if (_dueOf(tags) case final due?) _dueChip(due),
          ]),
        ),
        Flexible(child: line),
      ],
    );
  }

  /// The due day carried by any tag on this line, parsed. One date per line —
  /// see the tag menu, which enforces that when setting one.
  static DateTime? _dueOf(List<NoteTag> tags) {
    for (final t in tags) {
      if (t.dueDate case final d?) return d;
    }
    return null;
  }

  /// `Fri` inside the coming week, `12 Aug` beyond it, and red once it is past.
  ///
  /// No icon and no "due" label: the tag beside it already says what kind of
  /// thing this is, and the gutter is a hanging indent that must not push the
  /// text about.
  Widget _dueChip(DateTime due) {
    final now = DateTime.now();
    final days = DateTime.utc(due.year, due.month, due.day)
        .difference(DateTime.utc(now.year, now.month, now.day))
        .inDays;
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final label = switch (days) {
      0 => 'today',
      1 => 'tomorrow',
      -1 => 'yesterday',
      > 1 && <= 6 => weekdays[due.weekday - 1],
      _ => '${due.day} ${months[due.month - 1]}',
    };
    return Padding(
      padding: const EdgeInsets.only(left: 3, right: 1),
      child: Text(label,
          style: TextStyle(
              fontSize: 10.5,
              height: 1.2,
              fontWeight: days < 0 ? FontWeight.w700 : FontWeight.w500,
              color:
                  days < 0 ? OnoteColors.danger : OnoteColors.graphite400)),
    );
  }

  Widget _renderTable(BuildContext context, MdTable t, bool dark) {
    final border = dark ? OnoteColors.night100 : OnoteColors.paper100;
    final scheme = Theme.of(context).colorScheme;

    TextAlign textAlign(int col) => switch (t.align[col]) {
          MdAlign.center => TextAlign.center,
          MdAlign.right => TextAlign.right,
          MdAlign.left => TextAlign.left,
        };

    TableRow row(List<String> cells, {required bool header}) => TableRow(
          decoration: header
              ? BoxDecoration(color: scheme.surfaceContainerHighest)
              : null,
          children: [
            for (var c = 0; c < t.columns; c++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  c < cells.length ? cells[c] : '',
                  textAlign: textAlign(c),
                  style: header
                      ? baseStyle.copyWith(fontWeight: FontWeight.w600)
                      : baseStyle,
                ),
              ),
          ],
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      // Horizontally scrollable: a wide pasted table must not force the whole
      // page to scroll sideways.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 240),
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder.all(color: border, width: 1),
            children: [
              row(t.header, header: true),
              for (final r in t.rows) row(r, header: false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _renderLine(BuildContext context, String line, int index, bool dark) {
    final scheme = Theme.of(context).colorScheme;

    // Headings
    final h = _reHeading.firstMatch(line);
    if (h != null) {
      final level = h.group(1)!.length;
      final sizes = [22.0, 18.5, 16.0];
      return Padding(
        padding: EdgeInsets.only(top: index == 0 ? 0 : 6, bottom: 2),
        child: Text.rich(
          TextSpan(children: inlineSpans(h.group(2)!, baseStyle, dark, onWikiLink)),
          style: baseStyle.copyWith(
            fontSize: sizes[level - 1],
            fontWeight: FontWeight.w600,
            color: dark ? OnoteColors.moon0 : OnoteColors.graphite900,
          ),
        ),
      );
    }

    // Checkbox
    final cb = _reCheckbox.firstMatch(line);
    if (cb != null) {
      final checked = cb.group(2)!.toLowerCase() == 'x';
      return Padding(
        padding: EdgeInsets.only(
            left: indentPx(cb.group(1)!.length, baseStyle.fontSize)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: onToggleCheckbox == null
                  ? null
                  : () {
                      final lines = text.split('\n');
                      lines[index] = checked
                          ? lines[index].replaceFirst(_reCheckMark, '[ ]')
                          : lines[index].replaceFirst('[ ]', '[x]');
                      onToggleCheckbox!(lines.join('\n'));
                    },
              child: Padding(
                padding: const EdgeInsets.only(top: 3, right: 6),
                child: Icon(
                  checked ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 17,
                  color: checked ? scheme.primary : OnoteColors.graphite400,
                ),
              ),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: inlineSpans(cb.group(3)!, baseStyle, dark, onWikiLink),
                  style: checked
                      ? baseStyle.copyWith(
                          decoration: TextDecoration.lineThrough,
                          color: OnoteColors.graphite400)
                      : baseStyle,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // A rule BEFORE a bullet. Now that `*` and `+` are bullet characters,
    // `* * *` would otherwise parse as a bullet whose body is `* *`.
    if (_reDivider.hasMatch(line)) return const Divider(height: 12);

    // Bullet / numbered
    final bullet = _reBullet.firstMatch(line);
    final numbered = _reNumbered.firstMatch(line);
    if (bullet != null || numbered != null) {
      final indent =
          indentPx((bullet ?? numbered)!.group(1)!.length, baseStyle.fontSize);
      // The delimiter the writer used, not a decreed one: `2) item` used to
      // draw as `2.` when read and `2)` while editing, so the glyph changed
      // under the caret.
      final marker = bullet != null
          ? '•'
          : '${numbered!.group(2)}${line.trimLeft().startsWith(RegExp(r'\d+\)')) ? ')' : '.'}';
      final body = bullet != null ? bullet.group(2)! : numbered!.group(3)!;
      return Padding(
        // The marker HANGS in the left gutter, so the body text lands exactly on
        // the indent — the way OneNote (and print typography) sets lists. The
        // marker used to occupy inline width, pushing every bulleted line 22px
        // right of its indent; measured against OneNote's PDF that was a
        // constant +22u error on bullet rows.
        padding: EdgeInsets.only(
            left: (indent - kBulletGutter).clamp(0.0, double.infinity)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: kBulletGutter,
                child: Text(marker,
                    style: baseStyle.copyWith(color: OnoteColors.graphite500))),
            Expanded(
                child: Text.rich(
                    TextSpan(children: inlineSpans(body, baseStyle, dark, onWikiLink)),
                    style: baseStyle)),
          ],
        ),
      );
    }

    // A flashcard written into the prose: `?[front](back)` on its own line.
    // The same widget the block form uses, so a card is one object however it
    // got onto the page — see editor/flashcard_view.dart.
    final cardMatch = inlineCardRe.firstMatch(line);
    if (cardMatch != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, minHeight: 132),
          child: FlipCard(
            front: cardMatch.group(1) ?? '',
            back: cardMatch.group(2) ?? '',
            compact: true,
          ),
        ),
      );
    }

    // In-flow image on its own line: ![alt](src) or ![alt](src =WxH) — src is
    // a blob reference (sha256:<hash>); the optional ` =WxH` suffix is the
    // display size in page px (kept from import so a resized image renders at
    // its resized dimensions, not natural pixels). Without a size, natural
    // size capped to the box width.
    final img = _reImage.firstMatch(line);
    if (img != null && widget.imageResolver != null) {
      final src = img.group(3)!;
      var bytes = _imgCache[src];
      if (bytes == null) {
        bytes = widget.imageResolver!(src);
        if (bytes != null) _imgCache[src] = bytes; // never cache a miss
      }
      if (bytes != null) {
        final w = double.tryParse(img.group(4) ?? '');
        final h = double.tryParse(img.group(5) ?? '');
        // An explicit ` =WxH` only ever comes from import, where the size IS
        // OneNote's display rectangle and the flow above it is positioned to
        // match. Treat it as authoritative:
        //
        //  * no `maxWidth` clamp — clamping a >640px image scaled it down but
        //    left `height: h`, so `BoxFit.contain` letterboxed it: drawn small
        //    and centred in a taller slot, shifting the picture off its line.
        //  * no vertical padding — 4px top+bottom is phantom leading OneNote
        //    doesn't have, so every image sat low and everything after it in
        //    the same box inherited the drift.
        //  * top-left anchored, so any residual aspect mismatch shows as a gap
        //    at the bottom rather than moving the image.
        final sized = w != null || h != null;
        final image = Image.memory(bytes,
            width: w,
            height: h,
            fit: BoxFit.contain,
            alignment: Alignment.topLeft,
            gaplessPlayback: true);
        return Padding(
          padding: EdgeInsets.only(
              left: indentPx(img.group(1)!.length, baseStyle.fontSize),
              top: sized ? 0 : 4,
              bottom: sized ? 0 : 4),
          child: sized
              ? Align(alignment: Alignment.topLeft, child: image)
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: image,
                ),
        );
      }
      // Unresolvable blob → fall through to the literal-text rendering below.
    }

    // Quote
    final quote = _reQuote.firstMatch(line);
    if (quote != null) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.only(left: 10),
        decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: OnoteColors.ink300, width: 3))),
        child: Text.rich(
          TextSpan(children: inlineSpans(quote.group(1)!, baseStyle, dark, onWikiLink)),
          style: baseStyle.copyWith(color: OnoteColors.graphite500),
        ),
      );
    }

    // Display math on its own line: $$latex$$ (TEXT-1a / MATH-1 inline).
    // scaleDown keeps a wide equation within the box instead of overflowing.
    final dm = _reDisplayMath.firstMatch(line);
    if (dm != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Math.tex(
              dm.group(1)!,
              textStyle: baseStyle.copyWith(fontSize: 18),
              onErrorFallback: (e) => Text(dm.group(1)!,
                  style: const TextStyle(
                      fontFamily: 'JetBrains Mono', fontFamilyFallback: onoteFontFallback, color: OnoteColors.graphite400)),
            ),
          ),
        ),
      );
    }

    // (The divider is matched above, before bullets can claim `* * *`.)

    // Indented plain paragraph: leading spaces are an INDENT ENCODING
    // (2 spaces = 1 level, same as lists), not content. Rendering them as
    // literal spaces gave ~4px where OneNote gives 2.45×fontSize per level —
    // the other half of the importer's lost-indent defect: the parser now
    // emits the levels, and this is what makes them the right width.
    final plainIndent = _rePlainIndent.firstMatch(line);
    if (plainIndent != null) {
      return Padding(
        padding: EdgeInsets.only(
            left: indentPx(plainIndent.group(1)!.length, baseStyle.fontSize)),
        child: Text.rich(
          TextSpan(
              children: inlineSpans(
                  plainIndent.group(2)!, baseStyle, dark, onWikiLink)),
          style: baseStyle,
        ),
      );
    }

    // Paragraph (empty lines keep their height)
    return Text.rich(
      TextSpan(children: inlineSpans(line.isEmpty ? ' ' : line, baseStyle, dark, onWikiLink)),
      style: baseStyle,
    );
  }
}

/// Inline span parsing: **bold**, *italic*, `code`, ~~strike~~, ==highlight==,
/// ++underline++, inline math $…$ (TEXT-1a), [[Page|id]] wiki-links (EMBED-1)
/// and external `[label](https://…)` links (TEXT-1).
List<InlineSpan> inlineSpans(String text, TextStyle base, bool dark,
    [void Function(String label, String? id)? onWikiLink]) {
  final spans = <InlineSpan>[];
  final pattern = mdInlineRe;
  var last = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start)));
    }
    // One classifier, shared with the live editor (markdown/md_syntax.dart),
    // so reading and writing can never disagree about what a run of text is.
    final c = classifyInline(m);
    switch (c.kind) {
      case MdInline.wikiLink:
        final label = c.label!;
        final id = c.target;
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _WikiLink(
            label: label,
            onTap: onWikiLink == null ? null : () => onWikiLink(label, id),
            color: dark ? OnoteColors.ink300 : OnoteColors.ink600,
          ),
        ));
      case MdInline.colour:
        final hx = c.target!;
        final v = int.parse(hx, radix: 16);
        spans.add(TextSpan(
          text: c.inner,
          style: TextStyle(
              color: hx.length == 8
                  ? Color(((v & 0xFF) << 24) | (v >> 8))
                  : Color(0xFF000000 | v)),
        ));
      case MdInline.math:
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Math.tex(
            c.inner,
            textStyle: base,
            onErrorFallback: (e) => Text(c.inner,
                style: const TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontFamilyFallback: onoteFontFallback,
                    color: OnoteColors.graphite400)),
          ),
        ));
      case MdInline.extLink:
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _ExternalLink(
              label: c.label!,
              url: c.target!,
              base: base,
              color: dark ? OnoteColors.ink300 : OnoteColors.ink600),
        ));
      case MdInline.bareUrl:
        // Trailing sentence punctuation belongs to the writer, not to the
        // address — "see https://a.test/x." must not link the full stop.
        final raw = c.target!;
        final url = raw.replaceFirst(RegExp(r'[.,;:!?]+$'), '');
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _ExternalLink(
              label: _shortUrl(url),
              url: url,
              base: base,
              color: dark ? OnoteColors.ink300 : OnoteColors.ink600),
        ));
        if (url.length < raw.length) {
          spans.add(TextSpan(text: raw.substring(url.length)));
        }
      case MdInline.underline:
        spans.add(TextSpan(
            text: c.inner,
            style: const TextStyle(decoration: TextDecoration.underline)));
      case MdInline.boldItalic:
        // `***both***`. Without this branch the `**` alternative claimed it
        // as `***both**`, which rendered bold with a stray asterisk — the
        // reported import bug, and reachable by pressing Ctrl+B then Ctrl+I.
        spans.add(TextSpan(
            text: c.inner,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontStyle: FontStyle.italic)));
      case MdInline.bold:
        spans.add(TextSpan(
            text: c.inner,
            style: const TextStyle(fontWeight: FontWeight.w600)));
      case MdInline.italic:
        spans.add(TextSpan(
            text: c.inner,
            style: const TextStyle(fontStyle: FontStyle.italic)));
      case MdInline.code:
        spans.add(TextSpan(
          text: c.inner,
          style: TextStyle(
            fontFamily: 'JetBrains Mono',
            fontFamilyFallback: onoteFontFallback,
            fontSize: (base.fontSize ?? 14) * 0.9,
            color: dark ? OnoteColors.ink300 : OnoteColors.ink700,
            backgroundColor: dark ? OnoteColors.night100 : OnoteColors.paper100,
          ),
        ));
      case MdInline.strike:
        spans.add(TextSpan(
            text: c.inner,
            style: const TextStyle(decoration: TextDecoration.lineThrough)));
      case MdInline.highlight:
        spans.add(TextSpan(
            text: c.inner,
            style: TextStyle(
                backgroundColor: dark
                    ? OnoteColors.brass700.withValues(alpha: .45)
                    : const Color(0xFFF7E27A))));
    }
    last = m.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last)));
  }
  return spans;
}

/// A clickable page link chip rendered inline (EMBED-1).
/// An external `[label](https://…)` link. Hands the URL to the OS default
/// browser; the scheme allow-list lives in [PlatformOpen] because note content
/// is untrusted.
/// A bare URL, shortened for reading. The scheme and `www.` carry no meaning to
/// the reader, and a lecture link can be 200 characters — the full address
/// stays in the tooltip and is what actually opens.
String _shortUrl(String url) {
  var s = url.replaceFirst(RegExp(r'^https?://(www\.)?'), '');
  if (s.endsWith('/')) s = s.substring(0, s.length - 1);
  if (s.length <= 52) return s;
  return '${s.substring(0, 34)}…${s.substring(s.length - 14)}';
}

class _ExternalLink extends StatelessWidget {
  const _ExternalLink(
      {required this.label,
      required this.url,
      required this.color,
      required this.base});
  final String label;
  final String url;
  final Color color;

  /// The surrounding text's style. A WidgetSpan's child does NOT inherit the
  /// enclosing TextSpan style, so without this a link renders at the app's
  /// default size in the middle of a heading or a 20pt note.
  final TextStyle base;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: url,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () async {
            final ok = await PlatformOpen.url(url);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Couldn't open $url")));
            }
          },
          child: Text.rich(TextSpan(children: [
            TextSpan(
                text: label,
                style: base.copyWith(
                    color: color,
                    decoration: TextDecoration.underline,
                    decorationColor: color)),
            TextSpan(
                text: ' ↗',
                style: base.copyWith(
                    color: color, fontSize: (base.fontSize ?? 14) * 0.78)),
          ])),
        ),
      ),
    );
  }
}

class _WikiLink extends StatelessWidget {
  const _WikiLink({required this.label, required this.onTap, required this.color});
  final String label;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link, size: 14, color: color),
            const SizedBox(width: 2),
            Text(
              label,
              style: TextStyle(
                  color: color,
                  decoration: TextDecoration.underline,
                  decorationColor: color),
            ),
          ],
        ),
      ),
    );
  }
}
