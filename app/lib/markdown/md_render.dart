import 'dart:typed_data';
import '../editor/inline_atom_view.dart';
import '../model/inline_atom.dart';

import 'package:flutter/material.dart';

import '../core/platform_open.dart';
import '../model/tags.dart';
import '../editor/inline_math_editor.dart';
import '../math/math_view.dart';
import '../theme/onote_theme.dart';
import 'md_syntax.dart';
import 'md_table.dart';
import '../editor/flashcard_view.dart';
import '../study/flashcards.dart' show inlineCardRe;
import '../editor/live_markdown_controller.dart' show kEditorCaretMargin;

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
    this.onPictureMenu,
    this.onToggleCheckbox,
    this.onWikiLink,
    this.imageResolver,
    this.tagsByLine = const {},
    this.onToggleTag,
    this.mathLinkTint,
    this.atomHost,
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

  /// **What this block's inline atoms are, and what they may do** — a table
  /// in a paragraph, today. Null on a surface with no note behind it, and an
  /// atom then reads as its alt text.
  ///
  /// The read view supplies a host at all (rather than drawing atoms dead)
  /// because a table you can resize and click into without first opening the
  /// box is the behaviour tables already had, and losing it would be a
  /// regression dressed as a feature.
  final InlineAtomHost? atomHost;

  /// **This equation has a graph, and one of the two is being looked at.**
  ///
  /// The same hook the live editor sets, on the READ path. Without it a
  /// paragraph that is not being edited could never light up — and clicking a
  /// graph deselects everything, so not being edited is exactly the state a
  /// paragraph is in when its graph is clicked. The link is supposed to work
  /// both ways.
  final Color? Function(String latex)? mathLinkTint;

  /// **Right-click on a picture, with nothing open.**
  ///
  /// The owner: *"right clicking it not in editing mode … should bring up the
  /// option to save the image."* The block's own menu cannot answer this: a
  /// picture in a sentence is characters in the text, so the BLOCK is a
  /// paragraph and `pictureIn` rightly says it holds no picture. The picture
  /// itself is the only thing that knows where it is, so it is the thing that
  /// answers the click.
  ///
  /// Called with the blob reference and where the pointer was.
  final void Function(String src, Offset at)? onPictureMenu;

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
                  mouseCursor: WidgetStateMouseCursor.clickable,
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
          TextSpan(children: inlineSpans(h.group(2)!, baseStyle, dark, onWikiLink, widget.mathLinkTint, widget.atomHost)),
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
      // The box HANGS in the same gutter a bullet does, so a task's body
      // lands on `max(indent, kBulletGutter)` — exactly where a bullet's
      // does, and exactly where the live editor puts it. It used to add its
      // 17+6px icon column ON TOP of the full indent, so a nested task's
      // text sat 23px right of a nested bullet's when read and jumped that
      // far left the moment the caret entered the block.
      return Padding(
        padding: EdgeInsets.only(
            left: (indentPx(cb.group(1)!.length, baseStyle.fontSize) -
                    kBulletGutter)
                .clamp(0.0, double.infinity)),
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
              child: SizedBox(
                width: kBulletGutter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Icon(
                    checked ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 17,
                    color: checked ? scheme.primary : OnoteColors.graphite400,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  // The task's OWN style as the base, not the paragraph's: the editor
                  // builds a done task's runs on its strike and grey, and an
                  // underlined word in one must look the same in both.
                  children: inlineSpans(cb.group(3)!, checked ? baseStyle.copyWith(decoration: TextDecoration.lineThrough, color: OnoteColors.graphite400) : baseStyle, dark, onWikiLink, widget.mathLinkTint, widget.atomHost),
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
                    TextSpan(children: inlineSpans(body, baseStyle, dark, onWikiLink, widget.mathLinkTint, widget.atomHost)),
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
      // As wide as the paragraph, through the same [inlineCardWidth] the
      // editor asks — less the caret margin the editor's field reserves, so
      // clicking into the box does not move the card by those few pixels.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: LayoutBuilder(
          builder: (context, cons) => SizedBox(
            width: inlineCardWidth(cons.maxWidth.isFinite
                ? cons.maxWidth - kEditorCaretMargin
                : null),
            height: kInlineCardHeight,
            child: FlipCard(
              front: cardMatch.group(1) ?? '',
              back: cardMatch.group(2) ?? '',
              compact: true,
            ),
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
    // An atom reference has the same SHAPE as a picture and only the scheme
    // tells them apart — see `_isAtomRef` in live_markdown_controller.dart.
    // It reaches the paragraph below, where the shared inline grammar draws
    // it. (It fell through here anyway, because no resolver can resolve it;
    // depending on that would be depending on an accident.)
    if (img != null &&
        widget.imageResolver != null &&
        !img.group(3)!.startsWith(InlineAtom.scheme)) {
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
        final menu = widget.onPictureMenu;
        return Padding(
          padding: EdgeInsets.only(
              left: indentPx(img.group(1)!.length, baseStyle.fontSize),
              top: sized ? 0 : 4,
              bottom: sized ? 0 : 4),
          child: GestureDetector(
            // Secondary only. Everything else about this picture — a click to
            // open the box, a drag to move it — still belongs to the block.
            onSecondaryTapUp:
                menu == null ? null : (d) => menu(src, d.globalPosition),
            child: sized
                ? Align(alignment: Alignment.topLeft, child: image)
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: image,
                  ),
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
          TextSpan(children: inlineSpans(quote.group(1)!, baseStyle, dark, onWikiLink, widget.mathLinkTint, widget.atomHost)),
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
            // OnoteMath, not a bare Math.tex: it rewrites the constructs this
            // renderer lacks (`\begin{align}`, a top-level `\\`) instead of
            // losing them, and when an equation genuinely cannot be drawn it
            // says so in words. The fallback here used to be the raw LaTeX in
            // graphite400 — 2.80:1 in the contrast audit, and to a student
            // indistinguishable from the app eating their equation and
            // leaving the backslashes behind.
            // The same scale as everything else — a display equation is not
            // a third size (it was 18 against the block's 22 and a
            // sentence's 15).
            child: OnoteMath(dm.group(1)!,
                textStyle: mathStyleIn(baseStyle)),
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
                  plainIndent.group(2)!, baseStyle, dark, onWikiLink, widget.mathLinkTint, widget.atomHost)),
          style: baseStyle,
        ),
      );
    }

    // Paragraph (empty lines keep their height)
    return Text.rich(
      TextSpan(children: inlineSpans(line.isEmpty ? ' ' : line, baseStyle, dark, onWikiLink, widget.mathLinkTint, widget.atomHost)),
      style: baseStyle,
    );
  }
}

/// The look of `~subscript~` and `^superscript^`, in ONE place because both
/// renderers have to agree character for character.
///
/// Why a shadow rather than the obvious thing: Flutter's `TextStyle` has no
/// baseline shift, and the live editor cannot reach for a `WidgetSpan` — a
/// placeholder occupies exactly one code unit however many characters it
/// stands in for, so every caret offset after it would move (that is why
/// `_SourceSpan` in live_markdown_controller.dart is only ever used for a
/// single character). Painting the glyph as a zero-blur shadow at an offset
/// and making the glyph itself transparent shifts the INK without touching
/// the metrics, so the raw text keeps exactly as many code units as it had
/// and the coverage check still passes on every keystroke.
///
/// The sizes are relative to [base] rather than absolute, so a text box with
/// its own font size gets sub/superscripts in proportion.
TextStyle subSupStyle(TextStyle base, {required bool sup, required bool dark}) {
  final em = base.fontSize ?? 14;
  // Ink has to be named explicitly: the shadow needs a colour, and the base
  // style inherits its own from the enclosing DefaultTextStyle more often
  // than it carries one.
  final ink =
      base.color ?? (dark ? OnoteColors.moon0 : OnoteColors.graphite900);
  return base.copyWith(
    fontSize: em * 0.72,
    color: const Color(0x00000000),
    shadows: [
      // The rise is 0.26em, not the 0.34em typography would suggest, and the
      // reason is measured: a raised glyph is drawn OUTSIDE its line box, and
      // a text box clips at its own edge. At 0.34em the top of a superscript
      // was cut off on every imported OneNote box (line height 1.2207 —
      // `oneNoteLineHeight`), which is precisely where imported subscripts
      // and superscripts arrive from. 0.26em clears it with room to spare and
      // still sits visibly above the x-height. zz_subsup_probe measured this
      // by counting ink; a line height of 1.0 has no leading at all and would
      // clip any rise whatever, but no block in the app uses one.
      Shadow(color: ink, offset: Offset(0, sup ? -em * 0.26 : em * 0.14)),
    ],
  );
}

/// Inline span parsing: **bold**, *italic*, `code`, ~~strike~~, ==highlight==,
/// ++underline++, inline math $…$ (TEXT-1a), [[Page|id]] wiki-links (EMBED-1)
/// and external `[label](https://…)` links (TEXT-1).
/// The colour a `{{#rrggbb …}}` or `{{#rrggbbaa …}}` run names.
Color inlineHexColour(String hex) {
  final v = int.parse(hex, radix: 16);
  return hex.length == 8
      ? Color(((v & 0xFF) << 24) | (v >> 8))
      : Color(0xFF000000 | v);
}

const Color _clear = Color(0x00000000);

/// Is [s] drawn through its shadow — a sub- or superscript, whose glyph is
/// clear and whose ink is the shadow [subSupStyle] gives it?
bool _throughShadow(TextStyle s) =>
    s.color == _clear && (s.shadows?.isNotEmpty ?? false);

/// [s] in the colour [c] — the shadow's colour, for text drawn through one.
/// Tinting the glyph instead would draw a sub- or superscript twice, once
/// where it sits and once where it is meant to sit.
TextStyle _inked(TextStyle s, Color c) => _throughShadow(s)
    ? s.copyWith(shadows: [
        for (final x in s.shadows!)
          Shadow(color: c, offset: x.offset, blurRadius: x.blurRadius)
      ])
    : s.copyWith(color: c);

/// [s] with [d] ADDED to whatever line it already has.
///
/// `copyWith(decoration:)` replaces, so strike inside underline used to lose
/// the underline. [around] is consulted when [s] carries no line of its own:
/// the reading view builds its runs as styles RELATIVE to the paragraph, and a
/// ticked task's strike-through lives on the paragraph, not in the run.
TextStyle _decorated(TextStyle s, TextDecoration d, TextStyle around) {
  final have = s.decoration ?? around.decoration;
  final line = have == null || have == TextDecoration.none
      ? d
      : TextDecoration.combine([have, d]);
  return s.copyWith(
      decoration: line,
      // A clear glyph would draw a clear line; use the ink it is drawn in.
      decorationColor: _throughShadow(s) ? s.shadows!.first.color : null);
}

/// **What one inline run adds to the text inside it**, on top of [acc].
///
/// The ONE place a run's look is decided, for both renderers — they used to
/// hold a copy each, which is how bold came to be w700 in one and w600 in
/// the other. [acc] is whatever the runs around this one have built: an
/// absolute style in the live editor, and a style relative to the paragraph
/// in the reading view, which has to inherit the paragraph's own size (a bold
/// word in a heading is heading-sized). [resolved] is the absolute style the
/// text will finally be drawn in, for the kinds that must know it — code is
/// sized from the type around it, a sub- or superscript paints in its ink.
///
/// Runs nest — see [inlineKindNests] — so this is applied once per level:
/// `**{{#e53935 word}}**` is bold, then that bold in red.
///
/// [within] is the kinds of run this one sits inside. Code has a colour and a
/// background of its own, and a run the writer coloured or highlighted on
/// purpose keeps what they chose: what somebody picked beats a default.
TextStyle inlineRunStyle(MdMatch c, TextStyle acc,
    {required TextStyle resolved,
    required bool dark,
    Set<MdInline> within = const {}}) {
  switch (c.kind) {
    case MdInline.bold:
      return acc.copyWith(fontWeight: FontWeight.w600);
    case MdInline.italic:
      return acc.copyWith(fontStyle: FontStyle.italic);
    case MdInline.boldItalic:
      return acc.copyWith(
          fontWeight: FontWeight.w600, fontStyle: FontStyle.italic);
    case MdInline.underline:
      return _decorated(acc, TextDecoration.underline, resolved);
    case MdInline.strike:
      return _decorated(acc, TextDecoration.lineThrough, resolved);
    case MdInline.highlight:
      return acc.copyWith(
          backgroundColor: dark
              ? OnoteColors.brass700.withValues(alpha: .45)
              : const Color(0xFFF7E27A));
    case MdInline.colour:
      return _inked(acc, inlineHexColour(c.target!));
    case MdInline.subscript:
      return subSupStyle(resolved, sup: false, dark: dark);
    case MdInline.superscript:
      return subSupStyle(resolved, sup: true, dark: dark);
    case MdInline.code:
      final mono = acc.copyWith(
          fontFamily: 'JetBrains Mono',
          fontFamilyFallback: onoteFontFallback,
          fontSize: (resolved.fontSize ?? 14) * 0.9,
          backgroundColor: within.contains(MdInline.highlight)
              ? null
              : (dark ? OnoteColors.night100 : OnoteColors.paper100));
      return within.contains(MdInline.colour)
          ? mono
          : _inked(mono, dark ? OnoteColors.ink300 : OnoteColors.ink700);
    default:
      return acc;
  }
}

/// A link's words: its ink, underlined on top of any line already there.
///
/// Inside a run the writer coloured, the link takes THAT colour — the
/// underline still says it is a link. [within] as for [inlineRunStyle].
TextStyle inlineLinkStyle(TextStyle acc, Color ink, TextStyle around,
    {Set<MdInline> within = const {}}) {
  final keep = within.contains(MdInline.colour);
  final c = keep ? (acc.color ?? around.color ?? ink) : ink;
  return _decorated(keep ? acc : acc.copyWith(color: ink),
          TextDecoration.underline, around)
      .copyWith(decorationColor: c);
}

List<InlineSpan> inlineSpans(String text, TextStyle base, bool dark,
    [void Function(String label, String? id)? onWikiLink,
    Color? Function(String latex)? mathLinkTint,
    InlineAtomHost? atomHost]) {
  final spans = <InlineSpan>[];
  _inlineInto(text, base, const TextStyle(), 0, const {}, dark, onWikiLink,
      mathLinkTint, atomHost, spans);
  return spans;
}

/// One level of [inlineSpans]. [acc] is the style the runs around this text
/// have built, RELATIVE to the paragraph — see [inlineRunStyle] for why —
/// [depth] counts the runs it is inside, capped by [kInlineNestDepth], and
/// [within] says which kinds they are.
void _inlineInto(
    String text,
    TextStyle base,
    TextStyle acc,
    int depth,
    Set<MdInline> within,
    bool dark,
    void Function(String label, String? id)? onWikiLink,
    Color? Function(String latex)? mathLinkTint,
    InlineAtomHost? atomHost,
    List<InlineSpan> spans) {
  // The absolute style this level is drawn in, for everything that is not a
  // TextSpan and so cannot inherit one: equations, links, atoms.
  final resolved = base.merge(acc);
  // Plain text at the top level carries no style of its own, exactly as it
  // always has; inside a run it carries the run's.
  TextSpan plain(String t) => TextSpan(text: t, style: depth == 0 ? null : acc);
  var last = 0;
  for (final m in mdInlineRe.allMatches(text)) {
    if (m.start > last) {
      spans.add(plain(text.substring(last, m.start)));
    }
    // One classifier, shared with the live editor (markdown/md_syntax.dart),
    // so reading and writing can never disagree about what a run of text is.
    final c = classifyInline(m);
    switch (c.kind) {
      case MdInline.atom:
        // The SAME widget the live editor mounts (`inlineAtomWidget`), so a
        // table cannot look one way while the caret is in the paragraph and
        // another way when it is not. That single shape-change is what this
        // whole piece of work exists to remove.
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          // **Through a LayoutBuilder, because an atom has to know its room.**
          // A table's columns are fixed widths, and a `RenderTable` given
          // less room than they add up to does not complain and does not
          // clip: it draws its cells where they would have gone, straight
          // over whatever is beside the box. Measured before this line
          // existed — three 400px columns in a 300px box drew cells at x=8,
          // 408 and 808. The live editor passes its own known width in; this
          // is the read path's answer to the same question.
          child: LayoutBuilder(
            builder: (context, cons) => inlineAtomWidget(
              host: atomHost,
              id: c.target!,
              alt: c.inner,
              style: resolved,
              dark: dark,
              maxWidth: cons.maxWidth.isFinite ? cons.maxWidth : null,
            ),
          ),
        ));
      case MdInline.mathEmpty:
        // An equation started and never written into. It should not survive to
        // a saved note at all — the editor sweeps it on the way out — but if
        // one ever does, it reads as NOTHING rather than as two dollar signs.
        break;
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
      // **Every run that can hold others** — GitHub #17. Its inner text is
      // scanned again with this run's style added, so `**{{#e53935 x}}**`
      // and `{{#e53935 **x**}}` are both bold red, rather than bold with
      // `{{#e53935 x}}` written in it. See [inlineKindNests].
      case MdInline.colour:
      case MdInline.boldItalic:
      case MdInline.bold:
      case MdInline.italic:
      case MdInline.underline:
      case MdInline.strike:
      case MdInline.highlight:
      case MdInline.subscript:
      case MdInline.superscript:
        final inner = inlineRunStyle(c, acc,
            resolved: resolved, dark: dark, within: within);
        if (depth < kInlineNestDepth) {
          _inlineInto(c.inner, base, inner, depth + 1, {...within, c.kind},
              dark, onWikiLink, mathLinkTint, atomHost, spans);
        } else {
          spans.add(TextSpan(text: c.inner, style: inner));
        }
      case MdInline.math:
      case MdInline.mathDisplay:
      case MdInline.mathPadded:
        spans.add(WidgetSpan(
          // BASELINE, not `middle`. An equation mid-sentence has to sit on the
          // sentence's baseline the way a word does — that is what "maths on
          // the same line as text" means, and it is what TeX, and OneNote,
          // both do. `middle` centred the equation's BOX on the middle of the
          // text instead, which is only accidentally right: measured by
          // zz_inline_math_probe at 14px, `$x^2$` came out with its `x` on
          // y=31.50 while the words around it sat on y=29.04 — the equation
          // 2.46px (0.18em) below the line it was supposed to be on, sinking
          // further the taller the equation got. flutter_math computes a real
          // baseline for every construct (frac, matrix, sqrt, enclosure all
          // implement `computeDistanceToActualBaseline`), so asking for it
          // gets the TeX-correct position, including the axis-centring a
          // `\begin{cases}` brace needs.
          //
          // The line still GROWS to fit a tall equation — a WidgetSpan's
          // ascent and descent both enter the line's metrics — and only that
          // line: the paragraph above keeps its own height, which is exactly
          // the behaviour asked for ("increase the height of that one line as
          // required").
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          // `compact`: this one sits MID-SENTENCE, so an explanation box
          // would break the paragraph open. It moves into a tooltip instead —
          // and the equation is set in TeX text style, not display style.
          // No `\\displaystyle` prefix any more: every equation is set in
          // display style now, in a sentence exactly as in a box of its own,
          // so the double-dollar form differs only in being centred on a line
          // of its own (the whole-line branch above).
          child: InlineMathAtom(
            latex: c.inner,
            // `resolved`, so an equation inside a coloured run takes the
            // colour — and inside a ticked task, the task's grey.
            style: mathStyleIn(resolved),
            linkTint: mathLinkTint?.call(c.inner),
          ),
        ));
      case MdInline.extLink:
        final ink = dark ? OnoteColors.ink300 : OnoteColors.ink600;
        // The words go through the same walk, one level down, so a word
        // bolded inside a link is bold — the editor draws it that way.
        // Only when there is styling in them — a plain label stays one span
        // of text, exactly as it always was.
        final words = <InlineSpan>[];
        if (depth < kInlineNestDepth && mdInlineRe.hasMatch(c.label!)) {
          // Walked against the LINK's style, as the editor walks them, so a
          // strike inside a link adds to its underline instead of replacing it.
          _inlineInto(
              c.label!,
              inlineLinkStyle(resolved, ink, resolved, within: within),
              const TextStyle(),
              depth + 1,
              {...within, c.kind}, dark, onWikiLink, mathLinkTint, atomHost,
              words);
        }
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _ExternalLink(
              label: c.label!,
              words: words.isEmpty ? null : words,
              url: c.target!,
              base: resolved,
              color: ink,
              within: within),
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
              base: resolved,
              color: dark ? OnoteColors.ink300 : OnoteColors.ink600),
        ));
        if (url.length < raw.length) {
          spans.add(plain(raw.substring(url.length)));
        }
      case MdInline.code:
        // Literal: a code run's text is never scanned again.
        spans.add(TextSpan(
            text: c.inner,
            style: inlineRunStyle(c, acc,
                resolved: resolved, dark: dark, within: within)));
    }
    last = m.end;
  }
  if (last < text.length) {
    spans.add(plain(text.substring(last)));
  }
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
      this.words,
      required this.url,
      required this.color,
      required this.base,
      this.within = const {}});

  /// The runs this link sits inside — see [inlineLinkStyle].
  final Set<MdInline> within;
  final String label;

  /// [label] already walked for runs inside it — a bolded word in a link.
  /// Null for a bare URL, whose label is the address.
  final List<InlineSpan>? words;
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
                text: words == null ? label : null,
                children: words,
                style: inlineLinkStyle(base, color, base, within: within)),
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
