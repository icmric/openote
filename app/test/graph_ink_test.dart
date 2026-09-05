// Handwriting, from the multipart body OneNote actually returns.
//
// Ink was thought to be unreachable over this route, because a page's HTML has
// no representation of a stroke. It has none — but asking for the page with
// `includeinkML=true` returns a MIME multipart body whose second part is
// `application/inkml+xml`. Verified on a real notebook: 301 traces on one
// page, 292 KB against the 6 KB a typical page weighs.
//
// Every sample below is shaped the way that response actually is.
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/onenote/graph_multipart.dart';
import 'package:openote/onenote/graph_pages.dart';
import 'package:openote/onenote/inkml.dart';

/// A multipart body the way Graph writes one.
String multipart(String html, String? inkml, {String b = 'abc-123'}) {
  final out = StringBuffer()
    ..writeln('--$b')
    ..writeln('Content-Type: text/html; charset=utf-8')
    ..writeln()
    ..writeln(html);
  if (inkml != null) {
    out
      ..writeln('--$b')
      ..writeln('Content-Type: application/inkml+xml; charset=utf-8')
      ..writeln()
      ..writeln(inkml);
  }
  out.writeln('--$b--');
  return out.toString();
}

const pageHtml = '<html><body data-absolute-enabled="true">'
    '<div style="position:absolute;left:48px;top:90px;width:600px">'
    '<p>written</p></div></body></html>';

/// Two strokes, in OneNote's own spelling.
const realInk = '''<?xml version="1.0" encoding="utf-8"?>
<inkml:ink xmlns:emma="http://www.w3.org/2003/04/emma" xmlns:msink="http://schemas.microsoft.com/ink/2010/main" xmlns:inkml="http://www.w3.org/2003/InkML">
  <inkml:definitions>
    <inkml:context xml:id="ctxCoordinatesWithPressure">
      <inkml:inkSource xml:id="src">
        <inkml:traceFormat>
          <inkml:channel name="X" type="integer" max="32767" units="himetric" />
          <inkml:channel name="Y" type="integer" max="32767" units="himetric" />
          <inkml:channel name="F" type="integer" max="32767" units="dev" />
        </inkml:traceFormat>
      </inkml:inkSource>
    </inkml:context>
    <inkml:brush xml:id="brush1">
      <inkml:brushProperty name="width" value="25.00001" units="himetric" />
      <inkml:brushProperty name="height" value="25.00001" units="himetric" />
      <inkml:brushProperty name="color" value="#FF0000" />
      <inkml:brushProperty name="transparency" value="0" />
    </inkml:brush>
  </inkml:definitions>
  <inkml:traceGroup>
    <inkml:trace xml:id="t1" contextRef="#ctxCoordinatesWithPressure" brushRef="#brush1">2069 8152 15199, 2069 9773 15199</inkml:trace>
    <inkml:trace xml:id="t2" contextRef="#ctxCoordinatesWithPressure" brushRef="#brush1">7184 9840 32767, 7184 8191 16000</inkml:trace>
  </inkml:traceGroup>
</inkml:ink>''';

/// What almost every page carries: the envelope, and nothing drawn.
const emptyInk = '''<?xml version="1.0" encoding="utf-8"?>
<inkml:ink xmlns:inkml="http://www.w3.org/2003/InkML">
  <inkml:definitions />
  <inkml:traceGroup />
</inkml:ink>''';

void main() {
  group('splitting the response', () {
    test('the two parts come apart', () {
      final b = readPageBody(multipart(pageHtml, realInk));
      expect(b.html, contains('written'));
      expect(b.inkml, isNotNull);
      expect(b.inkml, contains('inkml:trace'));
    });

    test('a body that is not multipart is all HTML', () {
      // A request without `includeinkML` returns plain HTML, and being
      // tolerant of both is what lets the ink request be made unconditionally.
      final b = readPageBody(pageHtml);
      expect(b.html, contains('written'));
      expect(b.inkml, isNull);
    });

    test('a page with no ink part still reads', () {
      final b = readPageBody(multipart(pageHtml, null));
      expect(b.html, contains('written'));
      expect(b.inkml, isNull);
    });

    test('the closing delimiter is not mistaken for a part', () {
      final b = readPageBody(multipart(pageHtml, emptyInk));
      expect(b.inkml, contains('traceGroup'));
      expect(b.inkml, isNot(contains('--abc-123')));
    });
  });

  group('bodies that are not the happy path', () {
    /// Join with real CRLF, which is what the wire uses and what a Dart
    /// source file cannot hold inside a single-quoted literal.
    String crlf(List<String> lines) => lines.join('\r\n');

    test('CRLF line endings, which is what actually comes down the wire', () {
      final body = crlf([
        '--b',
        'Content-Type: text/html',
        '',
        pageHtml,
        '--b',
        'Content-Type: application/inkml+xml',
        '',
        emptyInk,
        '--b--',
      ]);
      final r = readPageBody(body);
      expect(r.html, contains('written'));
      expect(r.inkml, contains('traceGroup'));
    });

    test('a part with an unfamiliar type is taken as the page', () {
      // A page that imports without its ink beats one that imports as
      // nothing, so an unrecognised part is more likely the page than
      // nothing at all.
      final body = crlf([
        '--b',
        'Content-Type: application/octet-stream',
        '',
        pageHtml,
        '--b--',
      ]);
      expect(readPageBody(body).html, contains('written'));
    });

    test('a part with no blank line is skipped, not misread as content', () {
      final body = crlf([
        '--b',
        'Content-Type: text/html',
        '',
        pageHtml,
        '--b',
        'not-a-part',
        '--b--',
      ]);
      expect(readPageBody(body).html, contains('written'));
    });

    test('an empty body is empty, not a crash', () {
      expect(readPageBody('').html, '');
      expect(readPageBody('').inkml, isNull);
    });

    test('the order of the parts does not matter', () {
      final body = crlf([
        '--b',
        'Content-Type: application/inkml+xml',
        '',
        realInk,
        '--b',
        'Content-Type: text/html',
        '',
        pageHtml,
        '--b--',
      ]);
      final r = readPageBody(body);
      expect(r.html, contains('written'));
      expect(r.inkml, contains('inkml:trace'));
    });
  });

  group('reading the strokes', () {
    test('every trace becomes a stroke', () {
      final strokes = strokesFromInkML(realInk);
      expect(strokes, hasLength(2));
    });

    test('himetric becomes canvas pixels', () {
      // Hundredths of a millimetre; the canvas draws 120 to the inch, and an
      // inch is 2540 himetric.
      final strokes = strokesFromInkML(realInk);
      final xs = (strokes.first['x'] as List).cast<double>();
      expect(xs.first, closeTo(2069 * 120 / 2540, 0.001));
    });

    test('pressure is scaled against the channel maximum', () {
      final strokes = strokesFromInkML(realInk);
      final p1 = (strokes[0]['p'] as List).cast<double>();
      final p2 = (strokes[1]['p'] as List).cast<double>();
      expect(p1.first, closeTo(15199 / 32767, 0.001));
      expect(p2.first, closeTo(1.0, 0.001));
      expect(p2.last, closeTo(16000 / 32767, 0.001));
    });

    test('a brush colour is kept', () {
      final strokes = strokesFromInkML(realInk);
      expect(strokes.first['color'], '#FF0000');
    });

    test('plain black becomes the themed default, not a hard black', () {
      // `auto` is the app's word for "whatever suits the page", which is what
      // keeps imported handwriting legible on a dark theme. An explicit colour
      // the student chose is kept exactly; black is what OneNote writes when
      // they chose nothing.
      final black = realInk.replaceAll('#FF0000', '#000000');
      final strokes = strokesFromInkML(black);
      expect(strokes.first.containsKey('color'), isFalse);
    });

    test('the pen width is converted and clamped', () {
      final strokes = strokesFromInkML(realInk);
      final size = strokes.first['size'] as double;
      expect(size, greaterThanOrEqualTo(0.6));
      expect(size, lessThanOrEqualTo(24.0));
    });

    test('a page nobody drew on yields nothing, and is not a failure', () {
      expect(strokesFromInkML(emptyInk), isEmpty);
    });

    test('malformed InkML costs the ink and not the page', () {
      expect(strokesFromInkML('<inkml:ink><not closed'), isEmpty);
    });

    test('a trace with a single point is dropped', () {
      // One point is not a stroke; it has no length to draw.
      final one = realInk.replaceAll(
          '2069 8152 15199, 2069 9773 15199', '2069 8152 15199');
      expect(strokesFromInkML(one), hasLength(1));
    });

    test('a context without pressure still reads coordinates', () {
      const noF = '''<inkml:ink xmlns:inkml="http://www.w3.org/2003/InkML">
  <inkml:definitions><inkml:context xml:id="c">
    <inkml:inkSource xml:id="s"><inkml:traceFormat>
      <inkml:channel name="X" type="integer" />
      <inkml:channel name="Y" type="integer" />
    </inkml:traceFormat></inkml:inkSource></inkml:context></inkml:definitions>
  <inkml:traceGroup>
    <inkml:trace contextRef="#c">100 200, 300 400</inkml:trace>
  </inkml:traceGroup>
</inkml:ink>''';
      final strokes = strokesFromInkML(noF);
      expect(strokes, hasLength(1));
      expect((strokes.first['p'] as List).cast<double>(), everyElement(1.0));
    });
  });

  group('into the page the importer takes', () {
    test('ink arrives as `ink`, the same key the .one parser uses', () {
      // Parity by construction: `importOneParsedPage` builds the ink block
      // from this key, so both routes go through one piece of code and
      // nothing downstream can tell them apart.
      final r = readGraphPage(multipart(pageHtml, realInk), title: 'Page');
      expect(r.page['ink'], isA<List>());
      expect((r.page['ink'] as List), hasLength(2));
      // And the typed half is still there beside it.
      expect((r.page['boxes'] as List).first['markdown'], 'written');
    });

    test('a page with no ink carries no ink key at all', () {
      final r = readGraphPage(multipart(pageHtml, emptyInk), title: 'Page');
      expect(r.page.containsKey('ink'), isFalse);
      expect(r.loss.inkPages, 0,
          reason: 'an empty traceGroup is the ordinary case, not a loss');
    });

    test('ink that was there and could not be read IS counted as lost', () {
      final broken = realInk.replaceAll('</inkml:ink>', '');
      final r = readGraphPage(multipart(pageHtml, broken), title: 'Page');
      expect(r.loss.inkPages, 1);
    });
  });
}
