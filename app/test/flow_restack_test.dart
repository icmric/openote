// Re-stacking a container's flow with real text measurement.
//
// The parser can only cost *source* lines at a fixed 22px pitch, so a paragraph
// that wraps to three visual lines is charged for one and everything below it
// rides up — which is why an imported table sat too high and consecutive items
// collided. Font metrics only exist in the renderer's process, so the correction
// happens here.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/export/onenote_import.dart';

void main() {
  Map<String, dynamic> text(int flow, double y, String md, {double? w}) => {
        'kind': 'text',
        'flow': flow,
        'x': 60.0,
        'y': y,
        'markdown': md,
        'font_size_pt': 11.0,
        if (w != null) 'w': w,
      };

  Map<String, dynamic> table(int flow, double y) => {
        'kind': 'table',
        'flow': flow,
        'x': 60.0,
        'y': y,
        'col_w': [61.9, 61.9],
        'cells': [
          ['P', 'Q'],
          ['1', '0'],
        ],
      };

  test('the anchor keeps its parsed position; only what follows moves', () {
    final boxes = <dynamic>[
      text(1, 136.0, 'one line'),
      table(1, 200.0),
    ];
    restackFlows(boxes);
    expect(boxes[0]['y'], 136.0,
        reason: "the first box is OneNote's own offset and is already correct");
    expect(boxes[1]['y'], greaterThan(136.0));
  });

  test('a wrapping paragraph pushes the table down, not up', () {
    // The same text in a narrow box wraps further, so the table must sit lower.
    const long =
        'This is a long paragraph that will certainly wrap several times when '
        'it is laid out inside a narrow container, and every wrapped line has '
        'to be paid for in the flow below it.';
    final narrow = <dynamic>[text(1, 100.0, long, w: 200), table(1, 0.0)];
    final wide = <dynamic>[text(2, 100.0, long, w: 900), table(2, 0.0)];
    restackFlows(narrow);
    restackFlows(wide);
    expect(narrow[1]['y'], greaterThan(wide[1]['y']),
        reason: 'wrapping is exactly what the parser could not see');
    // And the parser's flat estimate — one source line at 22px + 14 gap — is
    // far below the truth for the narrow case.
    expect(narrow[1]['y'], greaterThan(100.0 + 36.0));
  });

  test('an in-flow image is costed at its display height, not a text line', () {
    final withImage = <dynamic>[
      text(1, 100.0, 'intro\n![image](onote-img://0 =264x198)\nafter'),
      table(1, 0.0),
    ];
    final withoutImage = <dynamic>[
      text(2, 100.0, 'intro\nafter'),
      table(2, 0.0),
    ];
    restackFlows(withImage);
    restackFlows(withoutImage);
    final delta =
        (withImage[1]['y'] as double) - (withoutImage[1]['y'] as double);
    expect(delta, closeTo(198.0, 1.0),
        reason: 'a 198px picture must cost 198px, not one 22px line');
  });

  test('boxes outside a flow are left exactly where they were', () {
    final boxes = <dynamic>[
      {'kind': 'table', 'flow': 0, 'x': 60.0, 'y': 500.0, 'cells': <dynamic>[]},
      {'kind': 'image', 'x': 700.0, 'y': 120.0},
    ];
    restackFlows(boxes);
    expect(boxes[0]['y'], 500.0);
    expect(boxes[1]['y'], 120.0);
  });

  test('a single-box flow is untouched — there is nothing below to correct',
      () {
    // This is the common case for imported tables: each sits in its own
    // container with its own recorded offset.
    final boxes = <dynamic>[table(3, 270.2)];
    restackFlows(boxes);
    expect(boxes[0]['y'], 270.2);
  });

  test('separate flows do not interfere', () {
    final boxes = <dynamic>[
      text(1, 100.0, 'a'),
      text(2, 900.0, 'b'),
      table(1, 0.0),
      table(2, 0.0),
    ];
    restackFlows(boxes);
    expect(boxes[0]['y'], 100.0);
    expect(boxes[1]['y'], 900.0);
    expect(boxes[2]['y'], greaterThan(100.0));
    expect(boxes[2]['y'], lessThan(900.0));
    expect(boxes[3]['y'], greaterThan(900.0));
  });

  test('the paced variant lands every box exactly where the sync one does',
      () async {
    // The writer isolate cannot run the restack (TextPainter is root-isolate
    // only), so the main isolate runs it in paced form, yielding between
    // boxes. Same groups, same heights, same accumulation — so the ONLY
    // acceptable difference is the awaits. A paced restack that drifted would
    // misplace imported content depending on which path measured it.
    final make = () => <dynamic>[
          text(
              1,
              100.0,
              'A paragraph long enough to wrap at this width and '
              'occupy several visual lines rather than the one the parser '
              'assumed for it.'),
          table(1, 140.0),
          text(1, 180.0, 'And another wrapping paragraph below the table.'),
          text(2, 90.0, 'A second, separate flow.'),
          text(2, 130.0, 'Whose boxes must move independently.'),
          text(0, 400.0, 'A floating box no flow may touch.'),
        ];

    final sync = make();
    restackFlows(sync);

    var yields = 0;
    final paced = make();
    await restackFlowsPaced(
      paced,
      shouldYield: () => true, // yield after EVERY box — the worst case
      onYield: () async {
        yields++;
        await Future<void>.delayed(Duration.zero);
      },
    );

    expect(yields, greaterThan(0), reason: 'the pacing must actually engage');
    for (var i = 0; i < sync.length; i++) {
      expect(paced[i]['y'], sync[i]['y'],
          reason: 'box $i moved differently under pacing');
    }
  });

  test('chunked measurement is exact: fuzz sync vs paced over nasty content',
      () async {
    // The paced path measures a giant box in 64-line chunks and SUMS — the
    // stall fix for the one atomic TextPainter call pacing couldn't split
    // (216 ms for a 2000-line box). The sum must equal the whole to the bit,
    // or imported content lands differently depending on which path measured
    // it. Seeded, so a failure reproduces.
    final rng = Random(42);
    String randomLine(int i) {
      switch (rng.nextInt(6)) {
        case 0:
          return ''; // empty interior/trailing lines — the probed edge case
        case 1:
          return 'word ' * (1 + rng.nextInt(40)); // wraps a random amount
        case 2:
          return 'x' * (1 + rng.nextInt(300)); // unbreakable long word
        case 3:
          return '![img](onote-img://\$i =264x\${100 + rng.nextInt(200)})';
        case 4:
          return '日本語のテキスト \$i と ελληνικά';
        default:
          return 'Line \$i of ordinary lecture text, medium length.';
      }
    }

    for (var round = 0; round < 20; round++) {
      final lines = rng.nextInt(300) + 1; // includes tiny and giant boxes
      final boxes = <dynamic>[
        {
          'kind': 'text',
          'markdown': List.generate(lines, randomLine).join('\n'),
          'x': 60.0,
          'y': 100.0,
          'w': rng.nextBool() ? 480.0 : 220.0,
          'flow': 1,
          if (rng.nextBool()) 'font_size_pt': 8.0 + rng.nextInt(16),
        },
        {
          'kind': 'table',
          'x': 60.0,
          'y': 140.0,
          'flow': 1,
          'cells': [
            for (var r = 0; r < 1 + rng.nextInt(8); r++)
              ['cell ' * (1 + rng.nextInt(10)), 'word ' * (1 + rng.nextInt(6))]
          ],
          'col_w': [120.0, 220.0],
        },
        text(1, 180.0, 'a plain closing box'),
      ];

      final syncBoxes = [
        for (final b in boxes) Map<String, dynamic>.from(b as Map)
      ];
      restackFlows(syncBoxes);

      final pacedBoxes = [for (final b in boxes) Map<String, dynamic>.from(b)];
      await restackFlowsPaced(
        pacedBoxes,
        shouldYield: () => true, // yield at every opportunity — worst case
        onYield: () => Future<void>.delayed(Duration.zero),
      );

      for (var i = 0; i < syncBoxes.length; i++) {
        expect(pacedBoxes[i]['y'], syncBoxes[i]['y'],
            reason: 'round \$round box \$i (\$lines-line box): paced '
                'measurement diverged from the atomic one');
      }
    }
  });
}
