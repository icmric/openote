// One inline grammar, proven.
//
// The two renderers used to carry hand-numbered copies of this alternation and
// disagreed in four places, so text changed shape whenever the caret left a
// block. These pin the grammar itself: what matches, what deliberately does
// not, and that the computed group indices line up with the branch order.
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/markdown/md_syntax.dart';

/// Every match in [s], as `kind:inner` — the shape both renderers see.
List<String> scan(String s) => [
      for (final m in mdInlineRe.allMatches(s))
        '${classifyInline(m).kind.name}:${classifyInline(m).inner}'
    ];

/// The source text a renderer would re-emit: markers + inner + markers must
/// reconstruct the match exactly, or the live editor's coverage check trips
/// and the whole block falls back to unstyled text.
void expectCovers(String s) {
  for (final m in mdInlineRe.allMatches(s)) {
    final c = classifyInline(m);
    final full = s.substring(m.start, m.end);
    expect(c.openLen + c.closeLen, lessThanOrEqualTo(full.length),
        reason: 'markers longer than the match for "$full"');
    if (c.kind == MdInline.bareUrl || c.kind == MdInline.extLink) continue;
    expect(full.substring(c.openLen, full.length - c.closeLen), c.inner,
        reason: 'marker widths do not bracket the inner text of "$full"');
  }
}

void main() {
  group('bold + italic — the reported import bug', () {
    test('***word*** is ONE bold-italic match, not bold plus a stray star', () {
      expect(scan('***word***'), ['boldItalic:word']);
    });

    test('it survives in a sentence, next to other emphasis', () {
      expect(scan('a ***both*** and **b** and *i* end'),
          ['boldItalic:both', 'bold:b', 'italic:i']);
    });

    test('markers bracket the inner text exactly', () {
      expectCovers('***word*** **b** *i* `c` ~~s~~ ==h== ++u++');
    });
  });

  group('a literal asterisk stays an asterisk', () {
    test('multiplication is not italics', () {
      expect(scan('2 * 3 * 4'), isEmpty);
    });

    test('a lone star at the end of a line is left alone', () {
      expect(scan('footnote *'), isEmpty);
    });

    test('but a real emphasis run still matches', () {
      expect(scan('*emphasis*'), ['italic:emphasis']);
    });
  });

  group('underscores obey the word-boundary rule', () {
    test('snake_case and a_1 keep their underscores', () {
      expect(scan('snake_case_name'), isEmpty);
      expect(scan('a_1 and b_2'), isEmpty);
      expect(scan('x_i + y_j = z_k'), isEmpty);
      // A word-internal underscore is the dangerous one; `__word__` standing
      // alone really is bold in Markdown, and treating it otherwise would be
      // the surprising choice.
      expect(scan('__init__'), ['bold:init']);
    });

    test('a real underscore emphasis still works', () {
      expect(scan('_italic_'), ['italic:italic']);
      expect(scan('__bold__'), ['bold:bold']);
    });
  });

  group('the rest of the dialect still parses', () {
    test('every kind is reachable', () {
      expect(scan('`code`'), ['code:code']);
      expect(scan('~~gone~~'), ['strike:gone']);
      expect(scan('==note=='), ['highlight:note']);
      expect(scan('++under++'), ['underline:under']);
      expect(scan(r'$x^2$'), [r'math:x^2']);
      expect(scan('{{#C63838 red}}'), ['colour:red']);
      expect(scan('[[Page|id]]'), ['wikiLink:Page']);
      expect(scan('[label](https://a.test)'), ['extLink:label']);
      expect(scan('see https://a.test/x'), ['bareUrl:https://a.test/x']);
    });

    test('the colour marker width covers "{{#hex "', () {
      final m = mdInlineRe.firstMatch('{{#C63838 red}}')!;
      final c = classifyInline(m);
      expect(c.openLen, '{{#C63838 '.length);
      expect(c.closeLen, 2);
      expect(c.target, 'C63838');
      expectCovers('{{#C63838 red}}');
    });

    test('an explicit link beats the bare-url branch at the same spot', () {
      expect(scan('[a](https://b.test)'), ['extLink:a']);
    });

    test('++u++ is underline, and is not eaten by anything else', () {
      expect(scan('++u++ and **b**'), ['underline:u', 'bold:b']);
    });
  });

  group('line grammar — one definition of a bullet', () {
    test('every marker people type is a bullet', () {
      for (final m in ['-', '*', '+']) {
        expect(mdBulletRe.hasMatch('$m item'), isTrue, reason: '"$m item"');
      }
    });

    test('checkboxes are matched before bullets can claim them', () {
      expect(mdCheckboxRe.hasMatch('* [ ] task'), isTrue);
      expect(mdCheckboxRe.firstMatch('- [x] done')?.group(3), 'done');
    });

    test('a divider is not a bullet', () {
      expect(mdDividerRe.hasMatch('---'), isTrue);
      expect(mdDividerRe.hasMatch('***'), isTrue);
    });

    test('headings stop at three, the depth the renderer draws', () {
      expect(mdHeadingRe.hasMatch('# h'), isTrue);
      expect(mdHeadingRe.hasMatch('### h'), isTrue);
      // `####` is body text in BOTH renderers now. It used to be a heading
      // while typing and literal hashes when read, which is the drift this
      // shared grammar exists to prevent.
      expect(mdHeadingRe.hasMatch('#### h'), isFalse);
      expect(mdHeadingRe.hasMatch('#nospace'), isFalse);
    });

    test('both ordered delimiters', () {
      expect(mdNumberedRe.hasMatch('1. a'), isTrue);
      expect(mdNumberedRe.hasMatch('2) b'), isTrue);
      expect(mdNumberedRe.hasMatch('3.14 pi'), isFalse);
    });
  });
}
