// Highlighting in a colour.
//
// Found while fixing GitHub #17 rather than reported: text colour had a full
// picker and the highlighter was one hard-coded yellow — for an app whose
// owner says *"Colour is a really important thing to me that we get right"*
// and whose students highlight to triage a reading list.
//
// `==x==` stays and means the default yellow: it is in notes already and
// every other Markdown tool understands it. A chosen colour is
// `{{=RRGGBB text}}` — the colour span's own shape with `=` where `#` is, so
// the two differ in one character and share their grammar, their toolbar
// command and every nesting rule.
//
// An older Openote draws `{{=7ae2f7 word}}` as that text, which is the owner's
// stated best case for something new: *"its fine if older versions just show
// the raw markdown ... ideally it should always just display the raw text like
// that if its something small."*
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/export/md_common.dart';
import 'package:openote/markdown/md_render.dart';
import 'package:openote/markdown/md_syntax.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

class _NoopRepo implements Repository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _blue = 0xFF7AE2F7;

void main() {
  const base = TextStyle(fontSize: 15, height: 1.5, color: Color(0xFF222222));

  /// The background the word is drawn on, read out of the real span tree.
  Color? backgroundIn(BuildContext ctx, String src, {bool dark = false}) {
    final c = LiveMarkdownController(text: src, dark: dark);
    final root =
        c.buildTextSpan(context: ctx, style: base, withComposing: false);
    Color? found;
    void walk(InlineSpan s, TextStyle acc) {
      if (s is! TextSpan) return;
      final st = s.style == null ? acc : acc.merge(s.style);
      if ((s.text ?? '').contains('word') && (st.fontSize ?? 15) > 1) {
        found = st.backgroundColor;
      }
      s.children?.forEach((x) => walk(x, st));
    }

    walk(root, base);
    c.dispose();
    return found;
  }

  Future<BuildContext> context(WidgetTester t) async {
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    return ctx;
  }

  group('the grammar', () {
    test('it is one run, with the colour as its target', () {
      final m = mdInlineRe.firstMatch('a {{=7ae2f7 word}} b')!;
      final c = classifyInline(m);
      expect(c.kind, MdInline.highlightColour);
      expect(c.target, '7ae2f7');
      expect(c.inner, 'word');
      expect(c.openLen, '{{=7ae2f7 '.length);
      expect(c.closeLen, 2);
    });

    test('alpha is accepted, as it is for a colour', () {
      final c = classifyInline(mdInlineRe.firstMatch('{{=7ae2f780 word}}')!);
      expect(c.kind, MdInline.highlightColour);
      expect(c.target, '7ae2f780');
    });

    test('it holds other runs, so a highlight can be bold', () {
      expect(inlineKindNests(MdInline.highlightColour), isTrue);
      final c = classifyInline(mdInlineRe.firstMatch('{{=7ae2f7 **word**}}')!);
      expect(c.inner, '**word**');
    });

    test('a highlight inside a highlight reads whole', () {
      // What highlighting part of a highlighted phrase writes. A plain lazy
      // body would close on the first `}}` and leave a stray pair.
      final c = classifyInline(
          mdInlineRe.firstMatch('{{=7ae2f7 big {{=f7e27a word}}}}')!);
      expect(c.kind, MdInline.highlightColour);
      expect(c.inner, 'big {{=f7e27a word}}');
    });

    test('and a colour inside a highlight, in either order', () {
      for (final src in [
        '{{=7ae2f7 {{#e53935 word}}}}',
        '{{#e53935 {{=7ae2f7 word}}}}',
      ]) {
        final c = classifyInline(mdInlineRe.firstMatch(src)!);
        expect(c.inner, contains('word'), reason: src);
        expect(c.inner, contains('{{'), reason: '$src holds the other run');
      }
    });

    test('a highlighted subscript, which has its own inner grammar', () {
      final c = classifyInline(mdInlineRe.firstMatch('H~{{=7ae2f7 2}}~O')!);
      expect(c.kind, MdInline.subscript);
      expect(c.inner, '{{=7ae2f7 2}}');
    });

    test('NEGATIVE CONTROL: a plain brace pair is not a highlight', () {
      for (final src in ['{{= word}}', '{{=zzzzzz word}}', '{{=7ae2f7word}}']) {
        final m = mdInlineRe.firstMatch(src);
        final k = m == null ? null : classifyInline(m).kind;
        expect(k, isNot(MdInline.highlightColour), reason: src);
      }
    });
  });

  group('how it is drawn', () {
    testWidgets('the colour it names is the background', (t) async {
      final ctx = await context(t);
      expect(backgroundIn(ctx, '{{=7ae2f7 word}}')?.toARGB32(), _blue);
    });

    testWidgets('and `==x==` still means the default yellow', (t) async {
      final ctx = await context(t);
      expect(backgroundIn(ctx, '==word=='), defaultHighlight(false));
    });

    testWidgets('in dark mode a chosen colour is toned down, not swapped',
        (t) async {
      // A solid highlight behind pale text cannot be read; alpha keeps the
      // text's contrast while the colour stays recognisably the writer's.
      final ctx = await context(t);
      final c = backgroundIn(ctx, '{{=7ae2f7 word}}', dark: true)!;
      expect(c.a, lessThan(1.0));
      expect((c.r * 255).round(), (0x7A), reason: 'the same hue');
      expect((c.b * 255).round(), (0xF7));
    });

    testWidgets('a colour that carries its own alpha is taken as written',
        (t) async {
      final ctx = await context(t);
      final c = backgroundIn(ctx, '{{=7ae2f780 word}}', dark: true)!;
      expect((c.a * 255).round(), 0x80);
    });

    testWidgets('code inside a highlight keeps the highlight', (t) async {
      // Code has a grey background of its own, which would paint over what
      // somebody chose.
      final ctx = await context(t);
      expect(backgroundIn(ctx, '{{=7ae2f7 `word`}}')?.toARGB32(), _blue);
    });
  });

  group('the toolbar', () {
    late AppState app;
    late LiveMarkdownController c;
    late Block block;

    setUp(() {
      app = AppState(_NoopRepo())
        ..notebookId = 'nb'
        ..pageId = 'pg'
        ..spellCheckEnabled = false;
      c = LiveMarkdownController(text: '', dark: false);
      block = Block(type: BlockType.text, x: 0, y: 0, w: 400, content: {});
      app.blocks = [block];
      app.editingBlockId = block.id;
      app.setActiveEditor(c, block, 'text');
    });

    tearDown(() {
      app.cancelPendingSave();
      c.dispose();
    });

    /// Select [word] in [text] and run [go].
    void on(String text, String word, void Function() go) {
      c.text = text;
      block.content['text'] = text;
      final at = text.indexOf(word);
      c.selection = TextSelection(baseOffset: at, extentOffset: at + word.length);
      go();
    }

    test('highlights a fresh selection', () {
      on('a word b', 'word', () => app.applyHighlightColor('7ae2f7'));
      expect(c.text, 'a {{=7ae2f7 word}} b');
      expect(c.selection.textInside(c.text), 'word',
          reason: 'the selection follows the words, not the markers');
    });

    test('re-highlights rather than nesting', () {
      on('{{=7ae2f7 word}}', 'word', () => app.applyHighlightColor('f7e27a'));
      expect(c.text, '{{=f7e27a word}}');
    });

    test('and finds the run through other markers', () {
      // The reason the search descends: bold markers sit between the
      // selection and the highlight.
      on('{{=7ae2f7 **word**}}', 'word',
          () => app.applyHighlightColor('f7e27a'));
      expect(c.text, '{{=f7e27a **word**}}');
    });

    test('takes the highlight off', () {
      on('{{=7ae2f7 word}}', 'word', () => app.applyHighlightColor('auto'));
      expect(c.text, 'word');
    });

    test('a highlight and a colour are changed independently', () {
      // Each command finds its own kind, so one never eats the other.
      on('a word b', 'word', () => app.applyHighlightColor('7ae2f7'));
      on(c.text, 'word', () => app.applyTextColor('e53935'));
      expect(c.text, 'a {{=7ae2f7 {{#e53935 word}}}} b');
      on(c.text, 'word', () => app.applyTextColor('auto'));
      expect(c.text, 'a {{=7ae2f7 word}} b', reason: 'the highlight stays');
      on(c.text, 'word', () => app.applyHighlightColor('auto'));
      expect(c.text, 'a word b');
    });

    test('the button toggles: on, then off', () {
      on('a word b', 'word', app.toggleHighlight);
      expect(c.text, 'a {{=F7E27A word}} b',
          reason: 'the default yellow, until a colour is picked');
      expect(app.selectionIsHighlighted, isTrue);
      on(c.text, 'word', app.toggleHighlight);
      expect(c.text, 'a word b');
      expect(app.selectionIsHighlighted, isFalse);
    });

    test('and it still toggles a plain ==x== off', () {
      // Notes written before colours came along.
      on('a ==word== b', 'word', app.toggleHighlight);
      expect(c.text, 'a word b');
    });

    test('picking a colour remembers it for the button', () {
      on('a word b', 'word', () => app.applyHighlightColor('7ae2f7'));
      expect(app.lastHighlight, '7ae2f7');
      on('c word d', 'word', app.toggleHighlight);
      expect(c.text, 'c {{=7ae2f7 word}} d');
    });

    test('the selection reports its highlight colour', () {
      on('{{=7ae2f7 word}}', 'word', () {});
      expect(app.selectionHighlight, '7ae2f7');
      on('a word b', 'word', () {});
      expect(app.selectionHighlight, isNull);
    });

    test('NEGATIVE CONTROL: not in a code box, where braces are source', () {
      final code = Block(
          type: BlockType.code, x: 0, y: 0, w: 400, content: {'source': ''});
      app.blocks = [code];
      app.editingBlockId = code.id;
      final cc = TextEditingController(text: 'a word b');
      addTearDown(cc.dispose);
      app.setActiveEditor(cc, code, 'source');
      cc.selection = const TextSelection(baseOffset: 2, extentOffset: 6);
      app.applyHighlightColor('7ae2f7');
      expect(cc.text, 'a word b');
    });
  });

  group('exports', () {
    test('Markdown keeps the highlight and loses the colour', () {
      expect(markdownInline('a {{=7ae2f7 word}} b'), 'a ==word== b');
    });

    test('a nested highlight comes out as two, not as broken pairs', () {
      expect(markdownInline('{{=7ae2f7 big {{=f7e27a word}}}}'),
          '==big ==word====');
    });

    test('a colour inside a highlight loses only the colour', () {
      expect(markdownInline('{{=7ae2f7 {{#e53935 word}}}}'), '==word==');
    });

    test('and nothing is left behind in either order', () {
      for (final src in [
        '{{#e53935 {{=7ae2f7 word}}}}',
        '{{=7ae2f7 {{#e53935 word}}}}',
      ]) {
        final out = markdownInline(src);
        expect(out, isNot(contains('{{')), reason: src);
        expect(out, isNot(contains('}}')), reason: src);
        expect(out, contains('word'), reason: src);
      }
    });
  });
}
