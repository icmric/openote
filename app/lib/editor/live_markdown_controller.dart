import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../markdown/md_render.dart' show indentPx;
import '../theme/onote_theme.dart';
import '../study/flashcards.dart' show inlineCardRe;
import '../theme/tokens.dart';
import 'flashcard_view.dart';

export 'wrap_selection.dart' show WrapSelectionFormatter;

/// A [TextEditingController] that renders Markdown **as you type** (TEXT-2/4):
/// the moment a construct closes (e.g. the second `*` of `**bold**`) the text
/// styles and its markers collapse away; move the caret back into it and the
/// markers reveal so you can edit them (the Obsidian "live preview" model).
///
/// The raw text buffer is unchanged — only the *rendering* transforms — so the
/// stored Markdown stays exactly what the user typed. Every code path is
/// guarded by a coverage check: if span-building ever fails to reproduce the
/// text verbatim, it falls back to an unstyled span, so editing can never
/// corrupt or desync.
class LiveMarkdownController extends TextEditingController {
  LiveMarkdownController({super.text, required this.dark});
  bool dark;

  /// Resolves an in-flow image reference (`sha256:<hash>`) to bytes, so the
  /// picture is shown WHILE the block is being edited and not only after the
  /// caret leaves it. Null, or a reference this cannot resolve, falls back to
  /// the dimmed source text — which is all this editor used to do.
  Uint8List? Function(String src)? imageResolver;

  /// Called after the controller has rewritten its own text, which only an
  /// image resize does. A programmatic edit never fires `TextField.onChanged`,
  /// so without this the new size would draw correctly and then never be saved.
  VoidCallback? onSelfEdit;

  /// Ask the host to widen the block by [extra] logical pixels — see
  /// `OnoteEditSession.requestExtraWidth`. Null means the box cannot grow, and
  /// a picture then clamps to it exactly as it did before.
  void Function(double extra)? requestExtraWidth;

  /// Resolved blobs, so a repaint per keystroke is not a SQLite read per
  /// keystroke. A miss is never cached: the bytes may still be arriving from a
  /// sync, and a notebook the user never leaves would remember the gap forever.
  final Map<String, Uint8List> _blobCache = {};

  Uint8List? _resolveImage(String src) {
    final hit = _blobCache[src];
    if (hit != null) return hit;
    final bytes = imageResolver?.call(src);
    if (bytes != null) _blobCache[src] = bytes;
    return bytes;
  }

  /// Rewrite the ` =WxH` suffix of the image reference occupying
  /// [lineStart]..[lineEnd]. [was] is the line as it read when the drag began.
  ///
  /// The offsets are captured at span-build time and used at drag-end, so they
  /// can be stale — another block's save, an undo, a paste. Rather than trust
  /// them, this re-reads the range and does nothing at all unless it still
  /// holds the same line. A resize that quietly lands on the wrong text would
  /// be a corruption; a resize that quietly does nothing is a lost drag.
  void resizeImageLine(
      int lineStart, int lineEnd, String was, double w, double h) {
    if (lineStart < 0 || lineEnd > text.length || lineStart > lineEnd) return;
    if (text.substring(lineStart, lineEnd) != was) return;
    final m = _imageLineRe.firstMatch(was);
    if (m == null) return;
    final next = '${m.group(1)}![${m.group(2)}](${m.group(3)} '
        '=${w.round()}x${h.round()})';
    if (next == was) return;

    final delta = next.length - was.length;
    int adj(int o) => o <= lineStart
        ? o
        : (o >= lineEnd ? o + delta : lineStart + next.length);
    final sel = selection;
    value = TextEditingValue(
      text: text.replaceRange(lineStart, lineEnd, next),
      selection: sel.isValid
          ? TextSelection(
              baseOffset: adj(sel.baseOffset), extentOffset: adj(sel.extentOffset))
          : sel,
      composing: TextRange.empty,
    );
    onSelfEdit?.call();
  }

  /// Rewrite the card occupying [lineStart]..[lineEnd] with a new front and
  /// back.
  ///
  /// The same shape as [resizeImageLine], and for the same reason: the offsets
  /// are captured when the span is built and used when the dialog closes, so
  /// they can be stale. The range is re-read and nothing happens at all unless
  /// it still holds the line we started from — an edit that quietly lands on
  /// the wrong text would be a corruption.
  void replaceCardLine(
      int lineStart, int lineEnd, String was, String front, String back) {
    if (lineStart < 0 || lineEnd > text.length || lineStart > lineEnd) return;
    if (text.substring(lineStart, lineEnd) != was) return;
    // The delimiters are what make the line a card, so they cannot appear
    // inside it. Stripping beats refusing: the user typed a bracket, not a
    // syntax error, and losing one character is better than losing the card.
    String clean(String v) => v
        .replaceAll(RegExp(r'[\[\]()\r\n]'), ' ')
        // Collapse the gaps the stripping leaves, or `f(x) [sic]` comes back
        // as `f x   sic` — technically intact and visibly mangled.
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final next = '?[${clean(front)}](${clean(back)})';
    if (next == was) return;

    final delta = next.length - was.length;
    int adj(int o) => o <= lineStart
        ? o
        : (o >= lineEnd ? o + delta : lineStart + next.length);
    final sel = selection;
    value = TextEditingValue(
      text: text.replaceRange(lineStart, lineEnd, next),
      selection: sel.isValid
          ? TextSelection(
              baseOffset: adj(sel.baseOffset),
              extentOffset: adj(sel.extentOffset))
          : sel,
      composing: TextRange.empty,
    );
    onSelfEdit?.call();
  }

  // Inline: **b** __b__ *i* _i_ `c` ~~s~~ ==h== ++u++ {{#hex text}}
  // `++u++` is appended LAST so the group numbers the dispatch below relies on
  // are unchanged.
  static final _inlineRe = RegExp(
      r'(\*\*(.+?)\*\*)|(__(.+?)__)|(\*(.+?)\*)|(_(.+?)_)|(`(.+?)`)|(~~(.+?)~~)|(==(.+?)==)|(\{\{#([0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?) (.+?)\}\})'
      r'|(\+\+(.+?)\+\+)');
  static final _headingRe = RegExp(r'^(#{1,6})( +)');

  /// The same line shapes md_render gives extra vertical room to — kept
  /// textually in step with `_reCheckbox` / `_reQuote` there.
  static final _checkboxLineRe = RegExp(r'^(\s*)- \[( |x|X)\]');
  static final _quoteLineRe = RegExp(r'^>\s?');

  /// A whole line that is nothing but an image reference — the in-flow form
  /// (Data Model §5.1). Line-anchored to match the renderer exactly, so what
  /// the editor draws is precisely what read mode turns into a picture.
  /// Groups: 1 indent, 2 alt, 3 src, 4 width, 5 height.
  static final _imageLineRe =
      RegExp(r'^(\s*)!\[([^\]]*)\]\(([^)\s]+)(?:\s+=(\d+)x(\d+))?\)\s*$');
  static final _prefixRe = RegExp(r'^(\s*)(- \[[ xX]\] |[-*] |\d+\. |> )');

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    final base = style ?? const TextStyle();
    final full = text;

    // Don't interfere with IME composition — render raw while composing.
    if (withComposing && value.composing.isValid && !value.composing.isCollapsed) {
      return TextSpan(text: full, style: base);
    }

    final lo = selection.isValid ? math.min(selection.baseOffset, selection.extentOffset) : -1;
    final hi = selection.isValid ? math.max(selection.baseOffset, selection.extentOffset) : -1;

    try {
      final children = <InlineSpan>[];
      var pos = 0;
      final lines = full.split('\n');
      for (var i = 0; i < lines.length; i++) {
        _buildLine(lines[i], pos, base, lo, hi, children);
        pos += lines[i].length;
        if (i < lines.length - 1) {
          children.add(const TextSpan(text: '\n'));
          pos += 1;
        }
      }
      final root = TextSpan(style: base, children: children);
      // Safety net: verify exact text coverage.
      final buf = StringBuffer();
      void collect(InlineSpan s) {
        // A placeholder is asked what source text it stands for, so a picture
        // drawn in place of its reference is still proven — character for
        // character — to be the reference and nothing else.
        if (s is _SourceSpan) {
          buf.write(s.source);
        } else if (s is TextSpan) {
          if (s.text != null) buf.write(s.text);
          final ch = s.children;
          if (ch != null) ch.forEach(collect);
        }
      }

      collect(root);
      if (buf.toString() == full) {
        return misspellings.isEmpty ? root : _underlineMisspellings(root, lo, hi);
      }
    } catch (_) {/* fall through */}
    return TextSpan(text: full, style: base);
  }

  /// Misspelled ranges, in raw-text offsets. Set by the editing session; see
  /// `spell/spell_checker.dart` for why the underlines are merged here rather
  /// than through Flutter's own spell-check pipeline.
  List<TextRange> _misspellings = const [];
  List<TextRange> get misspellings => _misspellings;
  set misspellings(List<TextRange> v) {
    if (identical(v, _misspellings)) return;
    _misspellings = v;
    notifyListeners();
  }

  static const _misspellingStyle = TextStyle(
    decoration: TextDecoration.underline,
    decorationStyle: TextDecorationStyle.wavy,
    decorationColor: Color(0xFFD23B3B),
  );

  /// Re-split the finished span tree at misspelling boundaries and merge the
  /// wavy underline in.
  ///
  /// Deliberately a post-pass over the completed tree rather than a change to
  /// the line builder: it consumes and re-emits exactly the same characters in
  /// the same order, so the coverage invariant checked above cannot be broken
  /// by a boundary bug — the worst case is a wrongly-placed underline, never
  /// corrupted text.
  TextSpan _underlineMisspellings(TextSpan root, int caretLo, int caretHi) {
    // A word being typed must not flash red mid-word, so the range under the
    // caret is left alone until the caret leaves it.
    final ranges = [
      for (final r in _misspellings)
        if (!(caretLo >= r.start && caretHi <= r.end)) r
    ];
    if (ranges.isEmpty) return root;

    var offset = 0;
    InlineSpan walk(InlineSpan span) {
      // Placeholders pass through untouched — but their SOURCE length still
      // has to be counted, or every misspelling after a picture would be
      // underlined some characters to the left of the word it belongs to.
      // (Filtering these out instead, which is what this did, deleted the
      // picture from the tree the moment the block contained a typo.)
      if (span is _SourceSpan) {
        offset += span.source.length;
        return span;
      }
      if (span is! TextSpan) return span;
      final text = span.text;
      final children = span.children;
      if (text == null) {
        return TextSpan(
          style: span.style,
          children: children?.map(walk).toList(),
        );
      }
      final start = offset;
      offset += text.length;
      // Hidden marker spans render at 0.1px — an underline there is noise.
      final hidden = (span.style?.fontSize ?? 99) <= 1;
      final overlapping = hidden
          ? const <TextRange>[]
          : [
              for (final r in ranges)
                if (r.start < start + text.length && r.end > start) r
            ];
      if (overlapping.isEmpty) {
        return TextSpan(
            text: text,
            style: span.style,
            children: children?.map(walk).toList());
      }
      // Cut points inside this span, in order.
      final cuts = <int>{0, text.length};
      for (final r in overlapping) {
        cuts.add((r.start - start).clamp(0, text.length));
        cuts.add((r.end - start).clamp(0, text.length));
      }
      final points = cuts.toList()..sort();
      final pieces = <InlineSpan>[];
      for (var i = 0; i < points.length - 1; i++) {
        final a = points[i], b = points[i + 1];
        if (a == b) continue;
        final bad = overlapping
            .any((r) => r.start <= start + a && r.end >= start + b);
        pieces.add(TextSpan(
          text: text.substring(a, b),
          style: bad
              ? (span.style ?? const TextStyle()).merge(_misspellingStyle)
              : span.style,
        ));
      }
      return TextSpan(
        style: span.style,
        children: [...pieces, ...?children?.map(walk)],
      );
    }

    return walk(root) as TextSpan;
  }

  bool _touches(int a, int b, int lo, int hi) =>
      lo >= 0 && hi >= a && lo <= b;

  /// Text that is laid out but must occupy no space.
  ///
  /// `letterSpacing` and `wordSpacing` are added PER CHARACTER in logical
  /// pixels and are not scaled by `fontSize`, so shrinking the font alone left
  /// the base style's 0.25px per character intact — which over the ~25
  /// characters of an image reference is about one character of visible gap.
  /// That was the picture "sitting about 1 char width from the left edge", and
  /// the same phantom width is what pushed a full-width picture onto the next
  /// line. Both have to be zeroed, not just the size.
  TextStyle _hidden(TextStyle base) => base.copyWith(
        color: const Color(0x00000000),
        fontSize: 0.01,
        letterSpacing: 0,
        wordSpacing: 0,
      );
  TextStyle _dim(TextStyle base) =>
      base.copyWith(color: OnoteColors.graphite400);

  void _buildLine(String line, int lineStart, TextStyle base, int lo, int hi,
      List<InlineSpan> out) {
    final lineEnd = lineStart + line.length;
    final onLine = lo >= 0 && hi >= lineStart && lo <= lineEnd;

    // A flashcard written into the prose: `?[front](back)` on its own line.
    // Same placeholder arithmetic as the picture below — the card stands for
    // the line's FIRST character and the rest trails hidden, so the paragraph
    // has exactly as many code units as the raw text and not one caret offset
    // moves. See the long note on the image branch; it is the same trick and
    // the same invariant.
    if (line.isNotEmpty) {
      final card = inlineCardRe.firstMatch(line);
      if (card != null) {
        out.add(_SourceSpan(
          source: line.substring(0, 1),
          alignment: PlaceholderAlignment.top,
          child: _InlineCard(
            key: ValueKey('card@$lineStart'),
            front: card.group(1) ?? '',
            back: card.group(2) ?? '',
            selected: onLine,
            onEdit: (f, b) => replaceCardLine(
                lineStart, lineStart + line.length, line, f, b),
          ),
        ));
        out.add(TextSpan(text: line.substring(1), style: _hidden(base)));
        return;
      }
    }

    // An in-flow image reference, drawn as the picture itself.
    //
    // The obvious way to do this — swap the line for a WidgetSpan — desyncs
    // every selection offset, because N characters of raw text become the one
    // U+FFFC code unit a placeholder occupies. So the line keeps its length:
    // its first N-1 characters are emitted at a hairline size and the last one
    // is what the placeholder stands for. N code units of source, N code units
    // laid out, and the coverage check above proves it on every keystroke.
    //
    // What this costs: the reference is no longer legible or comfortably
    // selectable while editing. That was the complaint — a hash where a
    // picture should be — and the caret still walks the line, so backspacing
    // into it breaks the reference and the source reappears, which is its own
    // explanation of what just happened.
    final img = _imageLineRe.firstMatch(line);
    if (img != null) {
      // Dim and monospace, so a reference standing in for a picture reads as a
      // placeholder rather than as writing. Used both when there are no bytes
      // and when the bytes turn out not to be an image.
      final refStyle = _dim(base).copyWith(
          fontFamily: 'JetBrains Mono',
          fontFamilyFallback: onoteFontFallback,
          fontSize: (base.fontSize ?? 14) * 0.85);
      final bytes = _resolveImage(img.group(3)!);
      if (bytes != null && line.isNotEmpty) {
        // The placeholder goes FIRST and stands for the line's first
        // character; the rest of the reference trails behind it, hidden. The
        // other way round — hidden run first — put every one of those
        // characters between the left edge and the picture, and no amount of
        // shrinking makes N characters occupy exactly nothing. Leading with
        // the picture makes flush-left exact rather than merely close, and
        // leaves the unavoidable remainder somewhere it cannot be seen.
        out.add(_SourceSpan(
          source: line.substring(0, 1),
          alignment: PlaceholderAlignment.top,
          child: _EditImage(
            // Keyed by line so the drag state belongs to THIS picture, and is
            // dropped if the text above it moves and the offsets go stale.
            key: ValueKey('${img.group(3)}@$lineStart'),
            bytes: bytes,
            width: double.tryParse(img.group(4) ?? ''),
            height: double.tryParse(img.group(5) ?? ''),
            indent: indentPx(img.group(1)!.length, base.fontSize),
            selected: onLine,
            onNeedWidth: requestExtraWidth,
            label: line,
            labelStyle: refStyle,
            onResize: (w, h) => resizeImageLine(lineStart, lineEnd, line, w, h),
          ),
        ));
        out.add(TextSpan(text: line.substring(1), style: _hidden(base)));
        return;
      }
      // No bytes — a blob still syncing, or one that never arrived. The
      // reference stays as text so it can be read, fixed or cut out.
      out.add(TextSpan(text: line, style: refStyle));
      return;
    }

    // ── Vertical parity with the read renderer (md_render.dart) ──
    //
    // The two renderers are one text box to the user, so their line boxes must
    // agree or the text visibly shifts on every edit-mode entry and exit. The
    // read side expresses extra room as per-line *padding*, which a TextField
    // cannot have — but a line's box is fontSize × height, so the same pixels
    // can be bought with a height multiplier. Each adjustment below mirrors a
    // specific padding in md_render._renderLine; change one only with the
    // other, and edit_view_metrics_test.dart holds the two within 1px.
    final baseFs = base.fontSize ?? 14;
    final baseH = base.height ?? 1.5;
    if (_checkboxLineRe.hasMatch(line)) {
      // Read draws a 17px checkbox icon with 3px top padding, so its row is
      // at least 20px however small the font.
      final minH = 20.0 / baseFs;
      if (minH > baseH) base = base.copyWith(height: minH);
    } else if (_quoteLineRe.hasMatch(line)) {
      // Read gives a quote a 2px margin above and below.
      base = base.copyWith(height: baseH + 4.0 / baseFs);
    }

    // Heading: markers collapse when the caret isn't on the line.
    final h = _headingRe.firstMatch(line);
    if (h != null) {
      final level = math.min(h.group(1)!.length, 3);
      // Same sizes and weight as the read renderer — it used to be 23/19/16.5
      // at w700 against read's 22/18.5/16 at w600, so the glyphs themselves
      // changed shape on entering edit.
      const sizes = [22.0, 18.5, 16.0];
      final size = sizes[level - 1];
      // Read pads a heading with top 6 + bottom 2 (top 0 on the first line).
      final extra = lineStart == 0 ? 2.0 : 8.0;
      final cStyle = base.copyWith(
          fontSize: size,
          fontWeight: FontWeight.w600,
          height: (size * baseH + extra) / size,
          color: dark ? OnoteColors.moon0 : OnoteColors.graphite900);
      final prefix = line.substring(0, h.end);
      out.add(TextSpan(text: prefix, style: onLine ? _dim(base) : _hidden(base)));
      _inline(line.substring(h.end), lineStart + h.end, cStyle, lo, hi, out);
      return;
    }

    // List / quote / checkbox: keep the prefix (dimmed) so items stay aligned.
    final p = _prefixRe.firstMatch(line);
    if (p != null) {
      out.add(TextSpan(text: line.substring(0, p.end), style: _dim(base)));
      _inline(line.substring(p.end), lineStart + p.end, base, lo, hi, out);
      return;
    }

    _inline(line, lineStart, base, lo, hi, out);
  }

  void _inline(String sub, int regionStart, TextStyle cBase, int lo, int hi,
      List<InlineSpan> out) {
    var last = 0;
    for (final m in _inlineRe.allMatches(sub)) {
      if (m.start > last) {
        out.add(TextSpan(text: sub.substring(last, m.start), style: cBase));
      }
      final absStart = regionStart + m.start;
      final absEnd = regionStart + m.end;
      final reveal = _touches(absStart, absEnd, lo, hi);

      var openLen = 2, closeLen = 2;
      TextStyle inner;
      if (m.group(1) != null) {
        inner = cBase.copyWith(fontWeight: FontWeight.w700);
      } else if (m.group(3) != null) {
        inner = cBase.copyWith(fontWeight: FontWeight.w700);
      } else if (m.group(5) != null) {
        openLen = closeLen = 1;
        inner = cBase.copyWith(fontStyle: FontStyle.italic);
      } else if (m.group(7) != null) {
        openLen = closeLen = 1;
        inner = cBase.copyWith(fontStyle: FontStyle.italic);
      } else if (m.group(9) != null) {
        openLen = closeLen = 1;
        inner = cBase.copyWith(
            fontFamily: 'JetBrains Mono', fontFamilyFallback: onoteFontFallback,
            color: dark ? OnoteColors.ink300 : OnoteColors.ink700,
            backgroundColor:
                dark ? OnoteColors.night100 : OnoteColors.paper100);
      } else if (m.group(11) != null) {
        inner = cBase.copyWith(decoration: TextDecoration.lineThrough);
      } else if (m.group(13) != null) {
        inner = cBase.copyWith(
            backgroundColor: dark
                ? OnoteColors.brass700.withValues(alpha: .45)
                : const Color(0xFFF7E27A));
      } else if (m.group(18) != null) {
        inner = cBase.copyWith(decoration: TextDecoration.underline);
      } else {
        // {{#RRGGBB[AA] text}} — asymmetric markers ('{{#'+hex+' ' … '}}')
        final hex = m.group(16)!;
        openLen = hex.length + 4;
        closeLen = 2;
        final v = int.parse(hex, radix: 16);
        inner = cBase.copyWith(
            color: hex.length == 8
                ? Color(((v & 0xFF) << 24) | (v >> 8))
                : Color(0xFF000000 | v));
      }

      final markStyle = reveal ? _dim(cBase) : _hidden(cBase);
      final full = sub.substring(m.start, m.end);
      // open marker + inner + close marker — substrings guarantee coverage.
      out.add(TextSpan(text: full.substring(0, openLen), style: markStyle));
      out.add(TextSpan(
          text: full.substring(openLen, full.length - closeLen), style: inner));
      out.add(TextSpan(
          text: full.substring(full.length - closeLen), style: markStyle));
      last = m.end;
    }
    if (last < sub.length) {
      out.add(TextSpan(text: sub.substring(last), style: cBase));
    }
  }
}

/// A card inside a paragraph, in the live editor.
///
/// Deliberately NOT editable in place: you change it by editing the line, the
/// same way you change a link or a picture reference. Backspacing into it
/// breaks the `?[…](…)` shape and the raw text reappears, which is its own
/// explanation of what just happened.
class _InlineCard extends StatelessWidget {
  const _InlineCard({
    super.key,
    required this.front,
    required this.back,
    required this.selected,
    required this.onEdit,
  });

  final String front;
  final String back;
  final bool selected;

  /// Write a new front and back back into the source line.
  final void Function(String front, String back) onEdit;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Container(
          width: 420,
          height: 132,
          // A foreground decoration, so the caret outline costs no layout and
          // the card cannot shift a pixel when the caret enters its line.
          foregroundDecoration: selected
              ? BoxDecoration(
                  borderRadius: OnoteRadius.xlAll,
                  border: Border.all(
                      color: OnoteColors.brass400.withValues(alpha: .85)))
              : null,
          child: FlipCard(
            front: front,
            back: back,
            compact: true,
            trailing: Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.edit_outlined, size: 14),
                color: OnoteColors.graphite400,
                tooltip: 'Edit this card',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () async {
                  final r = await editCardDialog(ctx, front, back);
                  if (r != null) onEdit(r.front, r.back);
                },
              ),
            ),
          ),
        ),
      );
}

/// A [WidgetSpan] that remembers the source text it stands in for.
///
/// The whole reason a picture can appear inside a live-editing TextField at
/// all: the coverage check and the misspelling pass both need to know how many
/// characters of the raw buffer this one placeholder accounts for, and a plain
/// WidgetSpan cannot tell them.
class _SourceSpan extends WidgetSpan {
  const _SourceSpan({
    required this.source,
    required super.child,
    super.alignment,
  });

  /// The raw text this placeholder was emitted in place of.
  final String source;
}

/// The smallest a picture may be dragged. Below this the handle is most of the
/// image and there is no way back out.
const double _kMinImageWidth = 48;

/// An in-flow image as it appears WHILE the block is being edited: the picture,
/// a corner handle to resize it, and an outline when the caret is on its line.
///
/// Sizing deliberately mirrors `md_render._renderLine` exactly — the same
/// `BoxFit.contain`, the same top-left anchor, the same 4px of vertical room
/// only when there is no explicit size, the same 640px cap only when there is
/// not. The two renderers are one text box to the user, so a picture that
/// moved or resized on entering edit mode would be the bug this feature was
/// meant to remove.
///
/// One gap survives, knowingly: `PlaceholderAlignment.top` aligns the picture
/// with the top of the FONT, and the line's half-leading sits above that, so
/// edit mode is a few pixels taller than read mode per image line. The only
/// lever that removes it is the field-wide strut, and flattening that would
/// break the parity of every other line shape. Pinned in
/// inline_image_edit_test.dart so it cannot quietly grow.
class _EditImage extends StatefulWidget {
  const _EditImage({
    super.key,
    required this.bytes,
    required this.width,
    required this.height,
    required this.indent,
    required this.selected,
    required this.label,
    required this.labelStyle,
    required this.onResize,
    required this.onNeedWidth,
  });

  final Uint8List bytes;

  /// The ` =WxH` suffix, if the reference carries one.
  final double? width, height;
  final double indent;
  final bool selected;

  /// The raw reference, shown if the bytes turn out not to be an image.
  final String label;
  final TextStyle labelStyle;
  final void Function(double w, double h) onResize;

  /// Ask the host for more room. Null when the box cannot grow.
  final void Function(double extra)? onNeedWidth;

  @override
  State<_EditImage> createState() => _EditImageState();
}

class _EditImageState extends State<_EditImage> {
  final _imgKey = GlobalKey();

  /// Live size during a drag. Held here rather than written to the buffer on
  /// every pointer move so the drag is one edit, not a hundred — a hundred
  /// would be a hundred undo entries and a hundred saves.
  double? _dragW, _dragH;
  double _aspect = 1;

  /// The widest this picture may be dragged: the text box itself, minus any
  /// indent. Read from our own incoming constraints rather than through a
  /// LayoutBuilder, because a placeholder inside an editable paragraph is also
  /// laid out during intrinsic-size passes, where a LayoutBuilder cannot go.
  double _maxWidth() {
    final box = context.findRenderObject() as RenderBox?;
    final c = box?.constraints;
    if (c == null || !c.maxWidth.isFinite) return 640;
    final avail = c.maxWidth - widget.indent;
    return avail > _kMinImageWidth ? avail : 640;
  }

  void _startDrag() {
    // The current size is read off the render tree rather than computed from
    // the image's natural dimensions, which would need an async decode. What
    // is on screen is what the user grabbed.
    final box = _imgKey.currentContext?.findRenderObject() as RenderBox?;
    final size = (box != null && box.hasSize) ? box.size : null;
    if (size == null || size.width <= 0 || size.height <= 0) return;
    final w = widget.width, h = widget.height;
    _aspect = (w != null && h != null && h > 0) ? w / h : size.width / size.height;
    // The drag starts from the STORED width when there is one, not from the
    // size on screen: a picture whose `=WxH` is wider than its box is drawn
    // clamped, and starting from the clamped size would shrink it the moment
    // it was touched.
    final from = (w != null && w > 0) ? w : size.width;
    _wanted = from;
    setState(() {
      _dragW = from;
      _dragH = from / _aspect;
    });
  }

  /// Where the pointer has asked the picture to be, ignoring what will fit.
  ///
  /// Tracked separately from [_dragW] because the two diverge whenever the box
  /// is the limit: the pointer keeps going, the picture cannot, and the box is
  /// asked to catch up. Accumulating deltas into the CLAMPED width instead
  /// would silently swallow every pixel of overshoot, so dragging out and back
  /// would not return to where it started.
  double? _wanted;

  void _updateDrag(Offset delta) {
    if (_dragW == null) return;
    final wanted = (_wanted ?? _dragW!) + delta.dx;
    _wanted = wanted;
    final avail = _maxWidth();
    // Push past the edge and the BOX grows, rather than the picture stopping.
    // The request is for the shortfall only; the host owns Block.w and the
    // chrome between it and this placeholder's constraints.
    if (wanted > avail) widget.onNeedWidth?.call(wanted - avail);
    // Still clamped to what is available THIS frame. The growth lands on the
    // next one, and until it does, drawing wider than the box would mean
    // writing a `=WxH` the picture is not actually rendered at — the text and
    // the picture would disagree about a number the user can see.
    final next =
        wanted.clamp(_kMinImageWidth, math.max(_kMinImageWidth, avail)) as double;
    setState(() {
      _dragW = next;
      _dragH = next / _aspect;
    });
  }


  void _endDrag() {
    final w = _dragW, h = _dragH;
    // Cleared and committed in the same frame: the rebuild the commit causes
    // carries the new size, so the picture never flashes back to the old one.
    setState(() {
      _dragW = _dragH = null;
      _wanted = null;
    });
    if (w != null && h != null && h > 0) widget.onResize(w, h);
  }

  /// Set when the bytes are not a picture at all — a truncated sync, a bad
  /// import, a reference to something that was never an image.
  bool _undecodable = false;

  @override
  Widget build(BuildContext context) {
    if (_undecodable) {
      // Same answer as a blob that is missing entirely: show the reference, so
      // there is something to see, fix or cut out rather than a blank gap.
      return Padding(
        padding: EdgeInsets.only(left: widget.indent),
        child: Text(widget.label, style: widget.labelStyle),
      );
    }
    final w = _dragW ?? widget.width;
    final h = _dragH ?? widget.height;
    final sized = w != null || h != null;
    final image = Image.memory(widget.bytes,
        key: _imgKey,
        width: w,
        height: h,
        fit: BoxFit.contain,
        alignment: Alignment.topLeft,
        gaplessPlayback: true,
        // The decode fails asynchronously, so the swap has to wait for the
        // frame that is already building.
        errorBuilder: (_, __, ___) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _undecodable = true);
          });
          return const SizedBox.shrink();
        });
    return Padding(
      padding: EdgeInsets.only(
          left: widget.indent, top: sized ? 0 : 4, bottom: sized ? 0 : 4),
      child: Stack(
        children: [
          Container(
            // A foreground decoration, so the outline costs no layout: with a
            // real border the picture would shift a pixel every time the caret
            // entered its line.
            foregroundDecoration: widget.selected
                ? BoxDecoration(
                    border: Border.all(
                        color: OnoteColors.brass400.withValues(alpha: .85)))
                : null,
            child: sized
                ? image
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: image,
                  ),
          ),
          Positioned(right: 0, bottom: 0, child: _handle()),
        ],
      ),
    );
  }

  /// The corner grip.
  ///
  /// It claims the pointer on the FIRST movement rather than after a pan's
  /// 36px slop, because the field's own selection drag settles at 18px and
  /// would otherwise win the arena on every slow drag — the handle worked when
  /// yanked and did nothing when eased, which is the worst of both. A grip that
  /// exists for one purpose and is 18px across can afford to be certain.
  Widget _handle() => MouseRegion(
        cursor: SystemMouseCursors.resizeUpLeftDownRight,
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            ImmediateMultiDragGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                    ImmediateMultiDragGestureRecognizer>(
              ImmediateMultiDragGestureRecognizer.new,
              (r) => r.onStart = (_) {
                _startDrag();
                return _ResizeDrag(onMove: _updateDrag, onDone: _endDrag);
              },
            ),
          },
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: OnoteColors.brass400.withValues(alpha: .92),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(6)),
            ),
            child: const Icon(Icons.south_east, size: 12, color: Colors.white),
          ),
        ),
      );
}

class _ResizeDrag extends Drag {
  _ResizeDrag({required this.onMove, required this.onDone});
  final ValueChanged<Offset> onMove;
  final VoidCallback onDone;

  @override
  void update(DragUpdateDetails details) => onMove(details.delta);

  @override
  void end(DragEndDetails details) => onDone();

  /// A cancelled drag still commits what was dragged so far. The alternative —
  /// snapping back — loses work for no reason the user can see.
  @override
  void cancel() => onDone();
}

// WrapSelectionFormatter moved to wrap_selection.dart, where every content
// editor can reach it without importing this whole controller — the export
// keeps existing importers compiling.
