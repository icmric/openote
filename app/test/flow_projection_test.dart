// The projection that crosses the isolate boundary must measure identically to
// the box it came from.
//
// **Why this test is load-bearing.** The import writer isolate cannot run
// `restackFlows` (TextPainter is root-isolate-only), so it sends the main
// isolate a cut-down copy of each box — `flowMeasurementInput` — and applies the
// y-coordinates that come back. If someone adds a field to `_measuredFlowHeight`
// and forgets the projection, nothing throws and no test of the restack itself
// fails: the layout just quietly comes back wrong for imported notebooks, which
// is the precise failure (tables sitting too high, boxes overlapping) that
// restackFlows was written to fix in the first place.
//
// So this compares the two paths on the same content and demands they agree
// exactly.

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/export/onenote_import.dart';

/// A box carrying every field the restack reads *plus* the ballast the parser
/// attaches and the restack ignores.
Map<String, dynamic> textBox(int i,
        {double? w, String? font, double? sizePt}) =>
    {
      'kind': 'text',
      'markdown': List.generate(
              5,
              (l) => 'Line $l of box $i, long enough that it wraps at a '
                  'realistic column width rather than sitting on one line.')
          .join('\n'),
      'x': 60.0,
      'y': 120.0 + i * 40,
      'w': w ?? 300.0,
      'h': 180.0,
      'flow': 1,
      if (font != null) 'font': font,
      if (sizePt != null) 'font_size_pt': sizePt,
      // Ignored by the restack, and deliberately present: the projection exists
      // to leave this behind.
      'tags': [
        {'line': 0, 'label': 'Question'}
      ],
      'runs': [
        {'start': 0, 'end': 8, 'bold': true}
      ],
    };

Map<String, dynamic> tableBox(int i) => {
      'kind': 'table',
      'x': 60.0,
      'y': 120.0 + i * 40,
      'w': 420.0,
      'flow': 1,
      'cells': [
        ['Term', 'Definition, which is long enough to wrap inside its column'],
        ['Proposition', 'A statement that is either true or false, not both'],
      ],
      'col_w': [120.0, 300.0],
      'tags': const [],
    };

Map<String, dynamic> mathBox(int i) => {
      'kind': 'math',
      'latex': r'\int_0^\infty e^{-x^2}\,dx',
      'x': 60.0,
      'y': 120.0 + i * 40,
      'flow': 1,
    };

/// Run the restack over [boxes] and report the resulting y per box.
List<double> ysAfterRestack(List<Map<String, dynamic>> boxes) {
  final copies = [for (final b in boxes) Map<String, dynamic>.from(b)];
  restackFlows(copies);
  return [for (final b in copies) (b['y'] as num).toDouble()];
}

/// The same, through the projection — what the writer isolate actually does.
List<double> ysThroughProjection(List<Map<String, dynamic>> boxes) {
  final projected = [for (final b in boxes) flowMeasurementInput(b)];
  restackFlows(projected);
  return [for (final b in projected) (b['y'] as num).toDouble()];
}

void main() {
  void agrees(String what, List<Map<String, dynamic>> boxes) {
    test('$what measures the same through the projection', () {
      final direct = ysAfterRestack(boxes);
      final viaProjection = ysThroughProjection(boxes);
      expect(viaProjection, direct,
          reason: 'flowMeasurementInput has drifted from what restackFlows and '
              '_measuredFlowHeight read — imported $what would be laid out '
              'differently depending on which path measured it');
      // And the restack must actually have done something, or this test would
      // pass just as well with both paths broken.
      expect(direct.toSet().length, greaterThan(1));
    });
  }

  agrees('wrapped text', [textBox(0), textBox(1), textBox(2)]);
  agrees('narrow columns', [
    textBox(0, w: 140),
    textBox(1, w: 140),
    textBox(2, w: 140),
  ]);
  agrees('mixed fonts and sizes', [
    textBox(0, font: 'Calibri', sizePt: 11),
    textBox(1, font: 'Times New Roman', sizePt: 18),
    textBox(2, sizePt: 8),
  ]);
  agrees('tables', [tableBox(0), textBox(1), tableBox(2)]);
  agrees('equations', [textBox(0), mathBox(1), textBox(2)]);
  agrees('in-flow images', [
    {
      ...textBox(0),
      'markdown': 'Before the picture\n'
          '![diagram](onote-img://0 =264x198)\n'
          'After the picture',
    },
    textBox(1),
    textBox(2),
  ]);

  test('the projection leaves the parser ballast behind', () {
    final projected = flowMeasurementInput(textBox(0));
    // Not an efficiency nicety: this is the whole reason it exists. Sending
    // whole boxes stalled the UI thread for 48 ms on a 3000-page notebook.
    expect(projected.containsKey('tags'), isFalse);
    expect(projected.containsKey('runs'), isFalse);
    expect(projected.containsKey('x'), isFalse);
    expect(projected.containsKey('h'), isFalse);
    // ...and keeps what grouping needs.
    expect(projected['flow'], 1);
    expect(projected['y'], isNotNull);
  });

  test('a box with nothing optional set still projects and measures', () {
    // The parser omits fields it could not recover. A projection that assumed
    // they were present would throw on exactly the messiest imported pages.
    final bare = {'kind': 'text', 'markdown': 'hello', 'y': 100.0, 'flow': 1};
    final boxes = [
      bare,
      {...bare, 'y': 140.0}
    ];
    expect(() => ysThroughProjection(boxes), returnsNormally);
    expect(ysThroughProjection(boxes), ysAfterRestack(boxes));
  });
}
