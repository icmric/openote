// Measure the binary ink codec against a REAL op log.
//
// Not a test — a measuring instrument. The codec's whole justification is a
// number taken from real handwriting, and an estimate from synthetic strokes
// would be worth very little: real imported ink has a stroke-length
// distribution, a pressure channel and a coordinate range that no generator
// guesses correctly.
//
// Usage:  dart run tool/measure_ink.dart <path to a .oplog>
//
// Strictly read-only.
import 'dart:convert';
import 'dart:io';

import 'package:openote/ink/ink_codec.dart';
import 'package:openote/model/models.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/measure_ink.dart <file.oplog>');
    exit(2);
  }
  var jsonBytes = 0, binRaw = 0, binDeflated = 0;
  var blocks = 0, strokes = 0, points = 0;
  var worstJson = 0, worstBin = 0;

  for (final line in File(args[0]).readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    Map<String, dynamic> op;
    try {
      op = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      continue;
    }
    if (op['op'] != 'block.set') continue;
    final d = op['d'];
    if (d is! Map) continue;
    final blk = d['block'];
    if (blk is! Map || blk['type'] != 'ink') continue;
    final raw = blk['content'];
    if (raw is! Map) continue;
    final list = raw['strokes'];
    if (list is! List || list.isEmpty) continue;

    final parsed = [
      for (final s in list)
        Stroke.fromJson((s as Map).cast<String, dynamic>())
    ];
    // The block's own origin, which is what a migrated block would carry.
    var ox = double.infinity, oy = double.infinity;
    for (final s in parsed) {
      for (var i = 0; i < s.x.length; i++) {
        if (s.x[i] < ox) ox = s.x[i];
        if (s.y[i] < oy) oy = s.y[i];
      }
    }
    if (!ox.isFinite) continue;

    final jsonLen = jsonEncode(list).length;
    final rawBin =
        InkCodec.encode(parsed, originX: ox, originY: oy, deflate: false);
    final defBin = InkCodec.encode(parsed, originX: ox, originY: oy);

    // Verify as we measure: a smaller number is worthless if it is not the
    // same handwriting.
    final back = InkCodec.decode(defBin, originX: ox, originY: oy);
    if (back.length != parsed.length) {
      stderr.writeln('MISMATCH: ${parsed.length} strokes in, '
          '${back.length} out');
      exit(1);
    }
    var maxErr = 0.0;
    for (var i = 0; i < parsed.length; i++) {
      for (var k = 0; k < parsed[i].x.length; k++) {
        final dx = (back[i].x[k] - parsed[i].x[k]).abs();
        final dy = (back[i].y[k] - parsed[i].y[k]).abs();
        if (dx > maxErr) maxErr = dx;
        if (dy > maxErr) maxErr = dy;
      }
    }
    if (maxErr > 1 / (2 * kInkScale) + 1e-9) {
      stderr.writeln('PRECISION FAIL: max error $maxErr px');
      exit(1);
    }

    blocks++;
    strokes += parsed.length;
    for (final s in parsed) {
      points += s.x.length;
    }
    jsonBytes += jsonLen;
    binRaw += rawBin.length;
    binDeflated += defBin.length;
    if (jsonLen > worstJson) {
      worstJson = jsonLen;
      worstBin = defBin.length;
    }
  }

  String mb(int b) => '${(b / 1048576).toStringAsFixed(2)} MB';
  stdout.writeln('ink blocks: $blocks   strokes: $strokes   points: $points');
  stdout.writeln('as JSON:        ${mb(jsonBytes)}  '
      '(${(jsonBytes / points).toStringAsFixed(2)} B/point)');
  stdout.writeln('binary, raw:    ${mb(binRaw)}  '
      '(${(binRaw / points).toStringAsFixed(2)} B/point)  '
      '${(jsonBytes / binRaw).toStringAsFixed(1)}x');
  stdout.writeln('binary, defl:   ${mb(binDeflated)}  '
      '(${(binDeflated / points).toStringAsFixed(2)} B/point)  '
      '${(jsonBytes / binDeflated).toStringAsFixed(1)}x');
  stdout.writeln('largest block:  ${mb(worstJson)} -> ${mb(worstBin)}');
  stdout.writeln('every block verified lossless within '
      '${(1 / (2 * kInkScale)).toStringAsFixed(4)} px');
}
