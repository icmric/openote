// Reading a OneNote page that arrived over Microsoft Graph.
//
// These are the whole reason the conversion is separated from the fetching:
// every rule below is checkable without a Microsoft account, a network, or a
// token. The HTML samples are shaped the way Graph actually returns a page —
// absolutely-positioned divs per outline, `data-tag` for checkboxes,
// `data-fullres-src` on images.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/onenote/graph_pages.dart';

/// The envelope Graph wraps every page in.
String wrap(String body, {String style = 'position:absolute;left:48px;top:90px;width:624px'}) =>
    '<html><head><title>T</title></head><body data-absolute-enabled="true">'
    '<div style="$style">$body</div></body></html>';

void main() {
  group('prose', () {
    test('a paragraph becomes one text box at the div position', () {
      final r = readGraphPage(wrap('<p>Hello there</p>'), title: 'Page');
      final boxes = r.page['boxes'] as List;
      expect(boxes, hasLength(1));
      expect(boxes.first['kind'], 'text');
      expect(boxes.first['markdown'], 'Hello there');
      // CSS px scaled into the canvas's 120-dpi space: the `.one` importer
      // beside this converts type as `pt * 120/72`, so geometry placed at 96
      // would be a quarter narrow for the text laid into it.
      expect(boxes.first['x'], 48.0 * kGraphPxToCanvas);
      expect(boxes.first['y'], 90.0 * kGraphPxToCanvas);
      expect(boxes.first['w'], 624.0 * kGraphPxToCanvas);
      // A flow id, or `restackFlows` skips the box entirely and every box in
      // the outline stays piled on the outline's origin.
      expect(boxes.first['flow'], isNotNull);
    });

    test('several paragraphs stay in ONE box, not one box each', () {
      // A box per paragraph would explode a normal page into dozens of
      // floating boxes that the student then has to tidy by hand.
      final r = readGraphPage(wrap('<p>One</p><p>Two</p><p>Three</p>'),
          title: 'Page');
      expect(r.page['boxes'], hasLength(1));
      expect((r.page['boxes'] as List).first['markdown'],
          'One\nTwo\nThree');
    });

    test('bold, italic and links survive as Markdown', () {
      final r = readGraphPage(
          wrap('<p><b>bold</b> and <i>slanted</i> and '
              '<a href="https://example.com">a link</a></p>'),
          title: 'Page');
      expect((r.page['boxes'] as List).first['markdown'],
          '**bold** and *slanted* and [a link](https://example.com)');
    });

    test('headings keep their level', () {
      final r = readGraphPage(wrap('<h1>Big</h1><h2>Smaller</h2>'),
          title: 'Page');
      expect((r.page['boxes'] as List).first['markdown'], '# Big\n## Smaller');
    });

    test('a non-breaking space is a space, not part of a word', () {
      // Left as U+00A0 it reads as one long unbreakable word to the layout and
      // to the word count.
      final r = readGraphPage(wrap('<p>one&nbsp;two</p>'), title: 'Page');
      expect((r.page['boxes'] as List).first['markdown'], 'one two');
    });

    test('styled runs stay on ONE line, not a line each', () {
      // "some text new lines after every char". OneNote does not always wrap a
      // run in a <p>: a positioned outline can hold spans, links and bolds as
      // DIRECT children, and treating every child element as a block put each
      // run on a line of its own. A sentence split into four styled spans came
      // out as four lines; one split per character came out per character.
      final r = readGraphPage(
          wrap('<span>Hel</span><span>lo</span><b> there</b>'),
          title: 'Page');
      expect((r.page['boxes'] as List).first['markdown'],
          'Hello **there**');
    });

    test('a run beside a paragraph does not glue onto it', () {
      // The other half: inline content appends, but a block still has to start
      // its own line or the two run together.
      final r = readGraphPage(
          wrap('<span>lead</span><p>para</p>'), title: 'Page');
      expect((r.page['boxes'] as List).first['markdown'], 'lead\npara');
    });

    test('a blank line between paragraphs survives', () {
      // "if i put an extra return between paragraphs, that is gone and they
      // are now touching, doesnt matter if it was 1 or 10". An empty
      // paragraph is not nothing — it is the gap the student typed.
      final r = readGraphPage(
          wrap('<p>one</p><p></p><p>two</p>'), title: 'Page');
      expect((r.page['boxes'] as List).first['markdown'], 'one\n\ntwo');
    });

    test('a paragraph holding only a break is still a blank line', () {
      // How OneNote actually spells it: 332 `<br>`s against 4 truly empty
      // paragraphs across forty-seven real pages.
      final r = readGraphPage(
          wrap('<p>one</p><p><br/></p><p>two</p>'), title: 'Page');
      expect((r.page['boxes'] as List).first['markdown'], 'one\n\ntwo');
    });

    test('several blank lines stay several', () {
      final r = readGraphPage(
          wrap('<p>one</p><p></p><p><br/></p><p></p><p>two</p>'),
          title: 'Page');
      expect((r.page['boxes'] as List).first['markdown'],
          'one\n\n\n\ntwo');
    });

    test('an empty page produces no boxes rather than an empty one', () {
      final r = readGraphPage(wrap('<p></p><p>   </p>'), title: 'Page');
      expect(r.page['boxes'], isEmpty);
    });
  });

  group('lists', () {
    test('bullets become bullets', () {
      final r = readGraphPage(
          wrap('<ul><li>alpha</li><li>beta</li></ul>'), title: 'Page');
      expect((r.page['boxes'] as List).first['markdown'], '- alpha\n- beta');
    });

    test('numbered lists renumber from one', () {
      final r = readGraphPage(
          wrap('<ol><li>first</li><li>second</li></ol>'), title: 'Page');
      expect((r.page['boxes'] as List).first['markdown'],
          '1. first\n2. second');
    });

    test('a OneNote to-do tag becomes a checkbox', () {
      // OneNote does not have a checkbox list KIND — it is a tag on the
      // paragraph, which is why this is read from `data-tag` and not from the
      // element name.
      final r = readGraphPage(
          wrap('<ul><li data-tag="to-do">open</li>'
              '<li data-tag="to-do:completed">done</li></ul>'),
          title: 'Page');
      expect((r.page['boxes'] as List).first['markdown'],
          '- [ ] open\n- [x] done');
    });

    test('a to-do paragraph outside a list is still a checkbox', () {
      final r = readGraphPage(
          wrap('<p data-tag="to-do:completed">buy milk</p>'), title: 'Page');
      expect((r.page['boxes'] as List).first['markdown'], '- [x] buy milk');
    });

    test('a nested list is indented under its parent', () {
      final r = readGraphPage(
          wrap('<ul><li>top<ul><li>under</li></ul></li></ul>'),
          title: 'Page');
      expect((r.page['boxes'] as List).first['markdown'],
          '- top\n  - under');
    });
  });

  group('tables', () {
    test('a table becomes a rectangular grid of cell markdown', () {
      final r = readGraphPage(
          wrap('<table><tr><td>a</td><td>b</td></tr>'
              '<tr><td>c</td><td>d</td></tr></table>'),
          title: 'Page');
      final table = (r.page['boxes'] as List)
          .firstWhere((b) => b['kind'] == 'table');
      expect(table['cells'], [
        ['a', 'b'],
        ['c', 'd']
      ]);
    });

    test('a ragged table is padded, not dropped', () {
      // A table block holds a rectangle. Dropping the row (or the table) to
      // avoid the problem would lose what the student wrote.
      final r = readGraphPage(
          wrap('<table><tr><td>a</td><td>b</td></tr>'
              '<tr><td>c</td></tr></table>'),
          title: 'Page');
      final table = (r.page['boxes'] as List)
          .firstWhere((b) => b['kind'] == 'table');
      expect(table['cells'], [
        ['a', 'b'],
        ['c', '']
      ]);
    });

    test('a table interrupts the prose into separate boxes', () {
      final r = readGraphPage(
          wrap('<p>before</p><table><tr><td>x</td></tr></table>'
              '<p>after</p>'),
          title: 'Page');
      final boxes = (r.page['boxes'] as List).cast<Map>();
      expect(boxes.map((b) => b['kind']).toList(),
          ['text', 'table', 'text']);
      expect(boxes.first['markdown'], 'before');
      expect(boxes.last['markdown'], 'after');
    });

    test('a table is fitted to the outline it sits in', () {
      // Measured on the real notebook: every `<td>` carried exactly one style
      // property, `border`. OneNote sends NO cell widths, so the earlier
      // attempt to read them was reading something that is never there.
      //
      // With nothing supplied the importer falls back to 140 px a column
      // clamped to 240-900, so a six-column table became 840 px whatever
      // outline it was in — wider than its outline, which is exactly how a
      // table comes to overlap what is beside it.
      final r = readGraphPage(
          wrap('<table><tr><td>a</td><td>b</td><td>c</td>'
              '<td>d</td><td>e</td><td>f</td></tr></table>'),
          title: 'Page');
      final table = (r.page['boxes'] as List)
          .firstWhere((b) => b['kind'] == 'table');
      final outline = 624.0 * kGraphPxToCanvas;
      expect((table['w'] as double), lessThanOrEqualTo(outline + 0.5));
      final cols = (table['col_w'] as List).cast<double>();
      expect(cols, hasLength(6));
      expect(cols.reduce((a, b) => a + b),
          closeTo(table['w'] as double, 0.001));
    });

    test('a column holding more text gets more room', () {
      // The other half of what was wrong: every column got an equal share
      // whatever it held, so a column of single digits took as much room as
      // one holding a sentence.
      final r = readGraphPage(
          wrap('<table><tr>'
              '<td>1</td>'
              '<td>a much longer cell with a whole sentence in it</td>'
              '</tr></table>'),
          title: 'Page');
      final table = (r.page['boxes'] as List)
          .firstWhere((b) => b['kind'] == 'table');
      final cols = (table['col_w'] as List).cast<double>();
      expect(cols[1], greaterThan(cols[0]));
    });

    test('no column is squeezed to nothing', () {
      // A column of empty cells still has to be clickable.
      final r = readGraphPage(
          wrap('<table><tr>'
              '<td></td>'
              '<td>${'x' * 400}</td>'
              '</tr></table>'),
          title: 'Page');
      final table = (r.page['boxes'] as List)
          .firstWhere((b) => b['kind'] == 'table');
      final cols = (table['col_w'] as List).cast<double>();
      expect(cols[0], greaterThanOrEqualTo(48.0));
    });

    test('a table outside any sized outline still gets sane widths', () {
      final r = readGraphPage(
          '<html><body><table><tr><td>a</td><td>b</td></tr></table></body>'
          '</html>',
          title: 'Page');
      final table = (r.page['boxes'] as List)
          .firstWhere((b) => b['kind'] == 'table');
      final cols = (table['col_w'] as List).cast<double>();
      expect(cols, hasLength(2));
      expect(cols.every((c) => c > 0), isTrue);
    });

    test('cell formatting is kept', () {
      final r = readGraphPage(
          wrap('<table><tr><td><b>x</b></td></tr></table>'), title: 'Page');
      final table = (r.page['boxes'] as List)
          .firstWhere((b) => b['kind'] == 'table');
      expect(table['cells'], [
        ['**x**']
      ]);
    });
  });

  group('images', () {
    test('an image is referenced by index so it flows in the paragraph', () {
      final r = readGraphPage(
          wrap('<p>see</p><img width="300" height="200" '
              'src="https://graph.example/resources/1/\$value" />'),
          title: 'Page');
      expect(r.images, hasLength(1));
      expect(r.images.first.url, contains('resources/1'));
      expect((r.page['boxes'] as List).first['markdown'],
          contains('![image](onote-img://0 =300x200)'));
    });

    test('the full-resolution source wins over the display copy', () {
      final r = readGraphPage(
          wrap('<img src="https://graph.example/small" '
              'data-fullres-src="https://graph.example/full" />'),
          title: 'Page');
      expect(r.images.first.url, 'https://graph.example/full');
    });

    test('an image with no source is counted as lost, not crashed on', () {
      final r = readGraphPage(wrap('<img alt="broken" />'), title: 'Page');
      expect(r.images, isEmpty);
      expect(r.loss.images, 1);
      expect(r.loss.any, isTrue);
    });

    test('attachments are counted rather than silently dropped', () {
      // Notes that LOOK complete when something has gone is the failure mode
      // this project refuses elsewhere too.
      final r = readGraphPage(
          wrap('<object data-attachment="notes.pdf" '
              'data="https://graph.example/r/1" type="application/pdf" />'),
          title: 'Page');
      expect(r.loss.attachments, 1);
    });
  });

  group('attachImageBytes', () {
    test('bytes land on the right image, with its size', () {
      final r = readGraphPage(
          wrap('<img width="120" height="80" src="https://g/x" />'),
          title: 'Page');
      final loss = GraphPageLoss();
      attachImageBytes(
          r.page, r.images, [Uint8List.fromList([1, 2, 3])], loss);
      final maps = (r.page['images'] as List).cast<Map>();
      expect(maps, hasLength(1));
      expect(maps.first['bytes'], isA<Uint8List>());
      expect(maps.first['w'], 120.0);
      expect(maps.first['h'], 80.0);
      expect(loss.any, isFalse);
    });

    test('an image whose bytes never arrived is removed and counted', () {
      final r = readGraphPage(
          wrap('<img src="https://g/x" /><img src="https://g/y" />'),
          title: 'Page');
      final loss = GraphPageLoss();
      attachImageBytes(
          r.page, r.images, [null, Uint8List.fromList([9])], loss);
      final maps = (r.page['images'] as List).cast<Map>();
      // The surviving one stays; the failed one costs its picture and nothing
      // else on the page.
      expect(maps, hasLength(1));
      expect(loss.images, 1);
    });
  });

  group('page shape', () {
    test('the map is what the existing importer already consumes', () {
      // The point of the whole file: a page from the internet and a page from
      // a .one file go through the same translation from here on.
      final r = readGraphPage(wrap('<p>x</p>'), title: 'My page', level: 2);
      expect(r.page['title'], 'My page');
      expect(r.page['level'], 2);
      expect(r.page['boxes'], isA<List>());
      expect(r.page['images'], isA<List>());
    });

    test('a level deeper than the app allows is clamped, not rejected', () {
      final r = readGraphPage(wrap('<p>x</p>'), title: 'P', level: 9);
      expect(r.page['level'], 2);
    });

    test('an indented paragraph does not drag the box to the left edge', () {
      // `margin-left` contains the substring `left`, and the position regex
      // had no boundary — so OneNote's indented paragraphs re-read the
      // outline's x as their own margin and moved the box to x=0.
      final r = readGraphPage(
          wrap('<p style="margin-left:36px;margin-top:0pt">indented</p>'),
          title: 'Page');
      final boxes = r.page['boxes'] as List;
      expect(boxes.first['x'], 48.0 * kGraphPxToCanvas,
          reason: 'the OUTLINE decides x, not a paragraph margin inside it');
    });

    test('a nested unpositioned div keeps its parent flow and origin', () {
      // Given its own flow it becomes an independent anchor, and the restacker
      // then leaves it sitting exactly on top of the content above it.
      final r = readGraphPage(
          wrap('<p>one</p><div><p>two</p></div>'), title: 'Page');
      final boxes = (r.page['boxes'] as List).cast<Map>();
      expect(boxes.length, greaterThanOrEqualTo(2));
      expect(boxes[0]['flow'], boxes[1]['flow']);
      expect(boxes[0]['x'], boxes[1]['x']);
    });

    test('a page with no positioned div still reads', () {
      // Not every page uses absolute layout; one that does not is a single
      // flow and becomes one box at the default margin.
      final r = readGraphPage(
          '<html><body><p>plain</p></body></html>', title: 'P');
      final boxes = r.page['boxes'] as List;
      expect(boxes, hasLength(1));
      expect(boxes.first['x'], kGraphDefaultLeft);
    });

    test('two outlines become two boxes at their own coordinates', () {
      final html = '<html><body data-absolute-enabled="true">'
          '<div style="position:absolute;left:48px;top:90px;width:300px">'
          '<p>left</p></div>'
          '<div style="position:absolute;left:400px;top:200px;width:250px">'
          '<p>right</p></div></body></html>';
      final r = readGraphPage(html, title: 'P');
      final boxes = (r.page['boxes'] as List).cast<Map>();
      expect(boxes, hasLength(2));
      expect(boxes[0]['x'], 48.0 * kGraphPxToCanvas);
      expect(boxes[1]['x'], 400.0 * kGraphPxToCanvas);
      expect(boxes[1]['y'], 200.0 * kGraphPxToCanvas);
      expect(boxes[1]['markdown'], 'right');
      // Separate outlines are separate flows, so the restacker never runs one
      // into the other.
      expect(boxes[0]['flow'], isNot(boxes[1]['flow']));
    });
  });

  group('graphSection', () {
    test('wraps pages the way the importer expects', () {
      final s = graphSection(name: 'Week 1', pages: [
        {'title': 'A', 'boxes': [], 'images': []}
      ]);
      expect(s['name'], 'Week 1');
      expect((s['section'] as Map)['pages'], hasLength(1));
      expect(s.containsKey('group'), isFalse);
    });

    test('a section group is carried as the parser spells it', () {
      final s = graphSection(name: 'Week 1', group: 'Y1/S2', pages: const []);
      expect(s['group'], 'Y1/S2');
    });
  });

  group('createdMsFromIso', () {
    test('reads what Graph sends', () {
      final ms = createdMsFromIso('2026-03-14T01:59:26Z');
      expect(ms, DateTime.utc(2026, 3, 14, 1, 59, 26).millisecondsSinceEpoch);
    });

    test('nothing, and nonsense, are both null rather than a wrong date', () {
      expect(createdMsFromIso(null), isNull);
      expect(createdMsFromIso(''), isNull);
      expect(createdMsFromIso('sometime last tuesday'), isNull);
    });
  });
}
