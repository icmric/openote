// Putting a selection down keeps the handwriting inside its box.
//
// v1.0.2 bug 20, from GitHub #20: *"the selection box moves but the content
// does not"*. A drag moves strokes with their box per pointer sample; the
// trouble was the step after it. At drag end `settleSelected` clamps every
// selected block to the page — below the title band, inside the sheet — and
// for ink the clamp set the box's `x`/`y` and never touched the strokes, which
// are page-absolute (Ink Spec §3). On a sheet it also NARROWED an ink box too
// wide to fit, over strokes that stayed exactly as wide as they were.
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

class _NoopRepo implements Repository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late AppState app;

  setUp(() {
    app = AppState(_NoopRepo())
      ..notebookId = 'nb'
      ..pageId = 'pg'
      ..spellCheckEnabled = false;
  });

  tearDown(() => app.cancelPendingSave());

  /// One stroke from ([x], [y]) across [w] and down [h], and a box that fits
  /// it exactly — the state a fresh drawing is in.
  Block drawing(double x, double y, {double w = 120, double h = 40}) => Block(
        type: BlockType.ink,
        x: x,
        y: y,
        w: w,
        h: h,
        content: {
          'strokes': [
            {
              'x': [x, x + w / 2, x + w],
              'y': [y, y + h, y + h / 2],
              'p': [0.5, 0.5, 0.5],
              'color': '#222222',
              'width': 2.0,
            }
          ],
        },
      );

  /// Where the strokes actually are.
  Rect inkOf(Block b) {
    final s = (b.content['strokes'] as List).single as Map;
    final xs = [for (final v in s['x'] as List) (v as num).toDouble()];
    final ys = [for (final v in s['y'] as List) (v as num).toDouble()];
    return Rect.fromLTRB(xs.reduce((a, c) => a < c ? a : c),
        ys.reduce((a, c) => a < c ? a : c), xs.reduce((a, c) => a > c ? a : c),
        ys.reduce((a, c) => a > c ? a : c));
  }

  Rect boxOf(Block b) => Rect.fromLTWH(b.x, b.y, b.w, b.h!);

  void putDown(Block b) {
    app.blocks = [b];
    app.selectedIds
      ..clear()
      ..add(b.id);
    app.settleSelected();
  }

  test('dropped over the title band, the drawing comes down with its box', () {
    final b = drawing(200, 20); // above the band, which ends at contentTop
    expect(inkOf(b), boxOf(b), reason: 'precondition: box fits the strokes');

    putDown(b);

    expect(b.y, AppState.contentTop, reason: 'the clamp still applies');
    expect(inkOf(b), boxOf(b),
        reason: 'the strokes moved with the box, not left above it');
  });

  test('dragged past the edge of a sheet, it comes back inside — all of it',
      () {
    app.pageProps = PageProps(layout: 'paged');
    final paper = app.pageProps.paper;
    final b = drawing(paper.width - 40, 300); // mostly off the right edge
    putDown(b);

    expect(b.x + b.w, lessThanOrEqualTo(paper.width - AppState.sheetMargin));
    expect(inkOf(b), boxOf(b));
  });

  test('handwriting too wide for the sheet is never narrowed', () {
    // Narrowing a text box re-wraps its text. Narrowing an ink box re-wraps
    // nothing: it leaves a box that is narrower than what is in it.
    app.pageProps = PageProps(layout: 'paged');
    final paper = app.pageProps.paper;
    final wide = paper.width; // wider than the sheet's writing area
    final b = drawing(10, 300, w: wide);
    putDown(b);

    expect(b.w, wide, reason: 'ink keeps its width');
    expect(b.x, AppState.sheetMargin, reason: 'pinned to the margin');
    expect(inkOf(b), boxOf(b));
  });

  test('NEGATIVE CONTROL: a text box on a sheet is still narrowed to fit', () {
    app.pageProps = PageProps(layout: 'paged');
    final paper = app.pageProps.paper;
    final t = Block(
        type: BlockType.text,
        x: 10,
        y: 300,
        w: paper.width,
        content: {'text': 'A long paragraph.'});
    putDown(t);
    expect(t.w, paper.width - AppState.sheetMargin * 2);
  });

  test('a drag still moves strokes with the box, sample by sample', () {
    // The same arithmetic, now in one place for drag, clamp and the
    // title-band repair.
    final b = drawing(200, 300);
    app.blocks = [b];
    app.selectedIds
      ..clear()
      ..add(b.id);
    app.moveSelectedBy(15, -25);
    expect(inkOf(b), boxOf(b));
    expect(b.x, 215);
    expect(b.y, 275);
  });
}
