import 'dart:math' as math;

import 'inline_atom.dart';
import 'models.dart';

/// **How tall a block will draw, without drawing it.**
///
/// The canvas measures every block it builds into `AppState.renderSizes`, but
/// it culls whatever is off screen, and a page that is not open is never built
/// at all. Everything that lays content out "below the last box" — the MCP
/// append and insert tools, the PDF importer, page growth — needs an answer for
/// those blocks too, and a wrong one in the LOW direction is the expensive
/// one: the next box lands on top of the previous one.
///
/// The old answer was a flat 60px for every non-text block and a raw character
/// count for text. A 30-line code block (≈630px) was stacked as if it were
/// 60px tall, and a paragraph holding a 12-row table counted the table as one
/// line of text. So this errs HIGH where it has to guess: a gap below a box is
/// a cosmetic nit, an overlap hides somebody's writing.
///
/// Pure, so it is testable without building a widget. The constants are the
/// views' own numbers, named so the two can be kept in step.

/// `CodeBlockView`: 13px JetBrains Mono at height 1.45.
const double kCodeLineHeight = 19;

/// `CodeBlockView`'s header bar and body padding, around the lines.
const double kCodeChrome = 60;

/// Monospace advance at 13px — JetBrains Mono is 0.6em.
const double _kCodeCharW = 13 * 0.6;

/// Inline-table cell text: 13px at height 1.45, inside `kTableCellPad`
/// (5px top and bottom) and a 1px rule.
const double _kCellLine = 13 * 1.45;
const double _kCellChrome = 10 + 1;

/// `kTableRowMin` in `inline_table.dart`.
const double _kRowMin = 24;

/// `md_render`'s heading sizes for `#`, `##`, `###`, and the 6px + 2px of
/// padding it puts round each.
const List<double> _kHeadingSizes = [22.0, 18.5, 16.0];
const double _kHeadingPad = 8;

final RegExp _heading = RegExp(r'^\s{0,3}(#{1,3})\s');
final RegExp _fence = RegExp(r'^\s{0,3}(`{3,}|~{3,})');

/// The estimated drawn height of [b], ignoring any stored `h`.
double estimateBlockHeight(Block b) => switch (b.type) {
      BlockType.text => _textHeight(b),
      BlockType.code => estimateCodeHeight(
          b.content['source'] as String? ?? '', b.w,
          hasOutput: b.content['output'] != null),
      BlockType.table =>
        estimateTableHeight(TableData.from(b.content), b.w - 20) + 16,
      BlockType.image => _imageHeight(b),
      _ => 60,
    };

/// A code block of [source] in a box [width] wide.
double estimateCodeHeight(String source, double width,
    {bool hasOutput = false}) {
  final perLine = ((width - 20) / _kCodeCharW).clamp(8, 400);
  var lines = 0;
  for (final l in source.split('\n')) {
    lines += l.isEmpty ? 1 : (l.length / perLine).ceil();
  }
  // Output is a panel of its own below the source; its size is whatever the
  // program printed, so this is a floor rather than an estimate.
  return lines * kCodeLineHeight + kCodeChrome + (hasOutput ? 60 : 0);
}

/// An inline table drawn into [width] logical px.
///
/// Columns share the width evenly unless widths were stored. A cell too long
/// for its column wraps, and the row grows to its tallest cell.
double estimateTableHeight(TableData t, double width) {
  if (t.rows == 0) return _kRowMin;
  final cols = math.max(1, t.cols);
  final colW = [
    for (var c = 0; c < cols; c++)
      _storedWidth(t, c) ?? math.max(40.0, width / cols),
  ];
  var h = 0.0;
  for (final row in t.cells) {
    var lines = 1;
    for (var c = 0; c < row.length && c < cols; c++) {
      final perLine = math.max(4.0, (colW[c] - 16) / (13 * 0.5));
      for (final l in row[c].split('\n')) {
        lines = math.max(lines, math.max(1, (l.length / perLine).ceil()));
      }
    }
    h += math.max(_kRowMin, lines * _kCellLine + _kCellChrome);
  }
  // A few px of margin above and below the grid.
  return h + 8;
}

double? _storedWidth(TableData t, int c) {
  for (final ws in [t.colWidths, t.impliedColWidths]) {
    if (c < ws.length && ws[c] > 1) return ws[c];
  }
  return null;
}

double _imageHeight(Block b) {
  final nw = (b.content['naturalW'] as num?)?.toDouble();
  final nh = (b.content['naturalH'] as num?)?.toDouble();
  if (nw == null || nh == null || nw <= 0) return 60;
  return b.w * nh / nw;
}

double _textHeight(Block b) {
  final text = b.content['text'] as String? ?? '';
  if (text.isEmpty) return 60;
  final size = (b.content['fontSize'] as num?)?.toDouble() ?? 15;
  final lh = (b.content['lineHeight'] as num?)?.toDouble() ?? 1.5;
  final width = b.w - 20;
  final atoms = text.contains(InlineAtom.scheme)
      ? InlineAtom.allIn(b.content)
      : const <String, InlineAtom>{};

  // Very rough wrap estimate: characters that fit across the box, at ~0.5em
  // per character for a proportional face.
  int wraps(String line, double charW) {
    if (line.isEmpty) return 1;
    final perLine = (width / charW).clamp(8, 400);
    return (line.length / perLine).ceil();
  }

  var h = 0.0;
  var inFence = false;
  for (final line in text.split('\n')) {
    if (_fence.hasMatch(line)) {
      inFence = !inFence;
      h += 8; // the fence itself draws as the code panel's padding
      continue;
    }
    if (inFence) {
      h += wraps(line, _kCodeCharW) * _kCellLine;
      continue;
    }
    final refs = InlineAtom.referencesIn(line);
    if (refs.isNotEmpty) {
      // A reference is a few dozen characters of machinery standing for
      // something that draws as tall as it likes. Count what it draws.
      for (final r in refs) {
        final a = atoms[r.id];
        h += a != null && a.type == 'table'
            ? estimateTableHeight(TableData.from(a.content), width)
            : size * lh;
      }
      final rest = withoutAtomRefs(line).trim();
      if (rest.isNotEmpty) h += wraps(rest, size * 0.5) * size * lh;
      continue;
    }
    final hd = _heading.firstMatch(line);
    if (hd != null) {
      final hs = _kHeadingSizes[hd.group(1)!.length - 1];
      h += wraps(line, hs * 0.55) * hs * lh + _kHeadingPad;
      continue;
    }
    h += wraps(line, size * 0.5) * size * lh;
  }
  return (h + 16).clamp(36, 20000).toDouble();
}
