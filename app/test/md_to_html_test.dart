import 'package:flutter_test/flutter_test.dart';
import 'package:openote/markdown/md_to_html.dart';

void main() {
  test('headings, emphasis, code and links', () {
    final html = markdownToHtml(
        '## Title\n\nSome **bold**, *italic* and `code` with [a link](https://x.org).');
    expect(html, contains('<h2>Title</h2>'));
    expect(html, contains('<b>bold</b>'));
    expect(html, contains('<i>italic</i>'));
    expect(html, contains('<code>code</code>'));
    expect(html, contains('<a href="https://x.org">a link</a>'));
  });

  test('markup in the text is escaped, not passed through', () {
    final html = markdownToHtml('<script>alert(1)</script> & more');
    expect(html, isNot(contains('<script>')));
    expect(html, contains('&lt;script&gt;'));
  });

  test('a script link is not made clickable', () {
    final html = markdownToHtml('[x](javascript:alert(1))');
    expect(html, isNot(contains('href')));
  });

  test('tables, lists and fences', () {
    final html = markdownToHtml(
        '| a | b |\n|---|---|\n| 1 | 2 |\n\n- one\n- two\n\n```dart\nvar x = 1 < 2;\n```');
    expect(html, contains('<th>a</th>'));
    expect(html, contains('<td>2</td>'));
    expect(html, contains('<ul><li>one</li><li>two</li></ul>'));
    expect(html, contains('var x = 1 &lt; 2;'));
  });

  test('a picture takes the source the caller gives it, or is dropped', () {
    expect(markdownToHtml('![i](assets/a.png)', imageSrc: (_) => 'data:x'),
        contains('<img src="data:x"'));
    expect(markdownToHtml('![i](assets/a.png)', imageSrc: (_) => null),
        isNot(contains('<img')));
  });
}
