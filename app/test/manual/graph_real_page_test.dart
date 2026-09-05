// Run the converter over a response captured from the real service.
//
// Guarded by ONOTE_REAL_PAGE naming a file saved by one of the probes. The
// fixtures in the other tests are shaped like the real thing; this one IS the
// real thing, and it is what catches a shape the fixtures got subtly wrong.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/onenote/graph_pages.dart';

void main() {
  final path = Platform.environment['ONOTE_REAL_PAGE'];
  test('a real page converts', () {
    final source = File(path!).readAsStringSync();
    final r = readGraphPage(source, title: 'Real page');
    final boxes = r.page['boxes'] as List;
    final ink = (r.page['ink'] as List?) ?? const [];
    // ignore: avoid_print
    print('boxes=${boxes.length} images=${(r.page['images'] as List).length} '
        'inkStrokes=${ink.length} lossInk=${r.loss.inkPages} '
        'lossImages=${r.loss.images} attachments=${r.loss.attachments}');
    for (final b in boxes.take(6)) {
      final m = (b as Map);
      final md = (m['markdown'] as String?) ?? '(${m['kind']})';
      // ignore: avoid_print
      print('  ${m['kind']} x=${m['x']} y=${m['y']} flow=${m['flow']} '
          '${md.length > 90 ? '${md.substring(0, 90)}…' : md}');
    }
    expect(boxes, isNotEmpty);
  }, skip: path == null ? 'set ONOTE_REAL_PAGE' : null);
}
