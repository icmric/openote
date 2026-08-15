// Headless check of the OneNote-ink import data path:
//   dart run tool/check_ink.dart <parser-output.json>
// Mimics onenote_import.dart's stroke conversion, round-trips through JSON the
// way writePage/readPage do, then decodes with the real Stroke model.
import 'dart:convert';
import 'dart:io';

import 'package:openote/model/models.dart';

void main(List<String> args) {
  final raw = File(args.first).readAsStringSync();
  final start = raw.indexOf('{');
  final result = jsonDecode(raw.substring(start)) as Map<String, dynamic>;
  final pages = (result['pages'] as List?) ?? [result];

  for (final pRaw in pages) {
    final page = (pRaw as Map).cast<String, dynamic>();
    final inkStrokes = (page['ink'] as List?) ?? const [];
    stdout.writeln('page "${page['title']}": ${inkStrokes.length} parser strokes');
    if (inkStrokes.isEmpty) continue;

    // — conversion identical to onenote_import.dart —
    final strokes = <Map<String, dynamic>>[];
    var mnx = double.infinity, mny = double.infinity;
    var mxx = -double.infinity, mxy = -double.infinity;
    for (final sRaw in inkStrokes) {
      final s = (sRaw as Map).cast<String, dynamic>();
      final xs = ((s['x'] as List?) ?? const [])
          .map((e) => (e as num).toDouble())
          .toList();
      final ys = ((s['y'] as List?) ?? const [])
          .map((e) => (e as num).toDouble())
          .toList();
      if (xs.isEmpty || xs.length != ys.length) continue;
      final ps = ((s['p'] as List?) ?? const [])
          .map((e) => (e as num).toDouble())
          .toList();
      for (final v in xs) {
        if (v < mnx) mnx = v;
        if (v > mxx) mxx = v;
      }
      for (final v in ys) {
        if (v < mny) mny = v;
        if (v > mxy) mxy = v;
      }
      strokes.add({
        'id': newIdStub(),
        'brush': {
          'tool': 'pen',
          'color': s['color'] as String? ?? '#211F1B',
          'size': ((s['size'] as num?)?.toDouble() ?? 2.0).clamp(0.6, 24.0),
          'opacity': ((s['opacity'] as num?)?.toDouble() ?? 1.0).clamp(0.05, 1.0),
        },
        'x': xs,
        'y': ys,
        'p': ps,
        'tx': const <double>[],
        'ty': const <double>[],
        't': const <int>[],
        // Mirrors onenote_import.dart: OneNote ink has no timing, and a
        // wall-clock value here would be encoded into the content-addressed
        // blob and defeat its deduplication.
        'strokeStart': 0,
      });
    }
    stdout.writeln('converted: ${strokes.length} strokes, '
        'block rect (${mnx.toStringAsFixed(0)},${mny.toStringAsFixed(0)})..'
        '(${mxx.toStringAsFixed(0)},${mxy.toStringAsFixed(0)})');

    // — round-trip through JSON like writePage → readPage —
    final content = jsonDecode(jsonEncode({'strokes': strokes}))
        as Map<String, dynamic>;
    var decoded = 0, totalPts = 0, pressured = 0;
    for (final sj in content['strokes'] as List) {
      final st = Stroke.fromJson((sj as Map).cast<String, dynamic>());
      decoded++;
      totalPts += st.x.length;
      if (st.p.isNotEmpty) pressured++;
      if (st.x.length != st.y.length) {
        stdout.writeln('  !! parallel-array mismatch in stroke $decoded');
      }
    }
    stdout.writeln('decoded via Stroke.fromJson: $decoded strokes, '
        '$totalPts points, $pressured with pressure — OK');
  }
}

var _n = 0;
String newIdStub() => 'stub-${_n++}';
