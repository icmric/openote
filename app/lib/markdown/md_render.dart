import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../theme/onote_theme.dart';

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
class MarkdownView extends StatelessWidget {
  const MarkdownView({
    super.key,
    required this.text,
    required this.baseStyle,
    this.onToggleCheckbox,
    this.onWikiLink,
    this.imageResolver,
  });

  final String text;
  final TextStyle baseStyle;

  /// Called with the new full text when a checkbox line is toggled.
  final void Function(String newText)? onToggleCheckbox;

  /// Called when a `[[Page|id]]` link is tapped (EMBED-1).
  final void Function(String label, String? id)? onWikiLink;

  /// Resolves an image src (e.g. `sha256:<hash>`) to bytes, typically from the
  /// notebook's content-addressed blob store. Null → image lines render as
  /// their literal Markdown.
  final Uint8List? Function(String src)? imageResolver;

  /// Decoded-bytes cache so scrolling doesn't re-query SQLite per frame; the
  /// blob store is content-addressed, so entries can never go stale.
  static final Map<String, Uint8List?> _imgCache = {};

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
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
            style: baseStyle.copyWith(fontFamily: 'monospace', fontSize: 13)),
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
      children.add(_renderLine(context, line, i, dark));
    }
    if (inFence) flushFence();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children.isEmpty ? [Text(' ', style: baseStyle)] : children,
    );
  }

  Widget _renderLine(BuildContext context, String line, int index, bool dark) {
    final scheme = Theme.of(context).colorScheme;

    // Headings
    final h = RegExp(r'^(#{1,3})\s+(.*)$').firstMatch(line);
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
    final cb = RegExp(r'^(\s*)- \[( |x|X)\]\s?(.*)$').firstMatch(line);
    if (cb != null) {
      final checked = cb.group(2)!.toLowerCase() == 'x';
      return Padding(
        padding: EdgeInsets.only(left: cb.group(1)!.length * 6.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: onToggleCheckbox == null
                  ? null
                  : () {
                      final lines = text.split('\n');
                      lines[index] = checked
                          ? lines[index].replaceFirst(RegExp(r'\[(x|X)\]'), '[ ]')
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

    // Bullet / numbered
    final bullet = RegExp(r'^(\s*)-\s+(.*)$').firstMatch(line);
    final numbered = RegExp(r'^(\s*)(\d+)\.\s+(.*)$').firstMatch(line);
    if (bullet != null || numbered != null) {
      final indent = (bullet ?? numbered)!.group(1)!.length * 6.0;
      final marker = bullet != null ? '•' : '${numbered!.group(2)}.';
      final body = bullet != null ? bullet.group(2)! : numbered!.group(3)!;
      return Padding(
        padding: EdgeInsets.only(left: indent),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 22,
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

    // In-flow image on its own line: ![alt](src) or ![alt](src =WxH) — src is
    // a blob reference (sha256:<hash>); the optional ` =WxH` suffix is the
    // display size in page px (kept from import so a resized image renders at
    // its resized dimensions, not natural pixels). Without a size, natural
    // size capped to the box width.
    final img = RegExp(r'^(\s*)!\[([^\]]*)\]\(([^)\s]+)(?:\s+=(\d+)x(\d+))?\)\s*$')
        .firstMatch(line);
    if (img != null && imageResolver != null) {
      final src = img.group(3)!;
      final bytes = _imgCache.putIfAbsent(src, () => imageResolver!(src));
      if (bytes != null) {
        final w = double.tryParse(img.group(4) ?? '');
        final h = double.tryParse(img.group(5) ?? '');
        return Padding(
          padding: EdgeInsets.only(
              left: img.group(1)!.length * 6.0, top: 4, bottom: 4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Image.memory(bytes,
                width: w, height: h, fit: BoxFit.contain, gaplessPlayback: true),
          ),
        );
      }
      // Unresolvable blob → fall through to the literal-text rendering below.
    }

    // Quote
    final quote = RegExp(r'^>\s?(.*)$').firstMatch(line);
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
    final dm = RegExp(r'^\s*\$\$(.+)\$\$\s*$').firstMatch(line);
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
                      fontFamily: 'monospace', color: OnoteColors.graphite400)),
            ),
          ),
        ),
      );
    }

    // Divider
    if (RegExp(r'^\s*(-{3,}|\*{3,})\s*$').hasMatch(line)) {
      return const Divider(height: 12);
    }

    // Paragraph (empty lines keep their height)
    return Text.rich(
      TextSpan(children: inlineSpans(line.isEmpty ? ' ' : line, baseStyle, dark, onWikiLink)),
      style: baseStyle,
    );
  }
}

/// Inline span parsing: **bold**, *italic*, `code`, ~~strike~~, ==highlight==,
/// inline math $…$ (TEXT-1a), and [[Page|id]] wiki-links (EMBED-1).
List<InlineSpan> inlineSpans(String text, TextStyle base, bool dark,
    [void Function(String label, String? id)? onWikiLink]) {
  final spans = <InlineSpan>[];
  final pattern = RegExp(
      r'(\[\[([^\]|]+)(?:\|([^\]]+))?\]\])|(\*\*(.+?)\*\*)|(\*(.+?)\*)|(`(.+?)`)|(~~(.+?)~~)|(==(.+?)==)|(\$([^$\n]+?)\$)|(\{\{#([0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?) (.+?)\}\})');
  var last = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start)));
    }
    if (m.group(1) != null) {
      // Wiki-link [[label|id]]
      final label = m.group(2)!;
      final id = m.group(3);
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _WikiLink(
          label: label,
          onTap: onWikiLink == null ? null : () => onWikiLink(label, id),
          color: dark ? OnoteColors.ink300 : OnoteColors.ink600,
        ),
      ));
    } else if (m.group(16) != null) {
      // Coloured text {{#RRGGBB[AA] text}}
      final hx = m.group(17)!;
      final v = int.parse(hx, radix: 16);
      spans.add(TextSpan(
        text: m.group(18),
        style: TextStyle(
            color: hx.length == 8
                ? Color(((v & 0xFF) << 24) | (v >> 8))
                : Color(0xFF000000 | v)),
      ));
    } else if (m.group(14) != null) {
      // Inline math $…$
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Math.tex(
          m.group(15)!,
          textStyle: base,
          onErrorFallback: (e) => Text(m.group(15)!,
              style: TextStyle(
                  fontFamily: 'monospace', color: OnoteColors.graphite400)),
        ),
      ));
    } else if (m.group(4) != null) {
      spans.add(TextSpan(
          text: m.group(5), style: const TextStyle(fontWeight: FontWeight.w600)));
    } else if (m.group(6) != null) {
      spans.add(TextSpan(
          text: m.group(7), style: const TextStyle(fontStyle: FontStyle.italic)));
    } else if (m.group(8) != null) {
      spans.add(TextSpan(
        text: m.group(9),
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: (base.fontSize ?? 14) * 0.9,
          color: dark ? OnoteColors.ink300 : OnoteColors.ink700,
          backgroundColor: dark ? OnoteColors.night100 : OnoteColors.paper100,
        ),
      ));
    } else if (m.group(10) != null) {
      spans.add(TextSpan(
          text: m.group(11),
          style: const TextStyle(decoration: TextDecoration.lineThrough)));
    } else if (m.group(12) != null) {
      spans.add(TextSpan(
          text: m.group(13),
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
