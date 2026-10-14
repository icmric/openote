// Every text style combined with every other, in either order.
//
// GitHub #17: *"I'm unable to use more than one text formatting at the same
// time. I'd like to make a word bold and change its color."* It was not
// colour. Neither renderer looked inside a run, so the outer style applied
// and the inner one's markers stayed on the page as text — and that was true
// of EVERY pair. Measured before the fix, over 117 outer/inner pairs: 12 drew
// correctly when read, 2 in the editor.
//
// Four layers, each tested here, because a fix to the drawing alone would
// have left the other three wrong:
//
//   1. both renderers, which must also agree with each other;
//   2. the grammar, where `**big *word***` — italicising the last word of a
//      bold phrase — stopped the bold one star early;
//   3. the caret, which has to know about markers inside markers or it walks
//      into them, and Backspace, which broke the colour of a red bold word;
//   4. the toolbar, which looked for a colour only immediately beside the
//      selection and so wrapped a second colour inside the first.
//
// All of it is decided when text is DRAWN, so notes written before the fix —
// with the markup the toolbar always produced — now show what was meant,
// with nothing to migrate.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/editor/live_markdown_controller.dart';
import 'package:openote/export/md_common.dart' show markdownInline;
import 'package:openote/export/pdf_vector_export.dart' show debugPlainText;
import 'package:openote/markdown/md_render.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

const _red = 0xFFE53935;

/// Each style, how it is written, and the mark it leaves on a style.
final _styles = <String, String Function(String)>{
  'bold': (s) => '**$s**',
  'italic': (s) => '*$s*',
  'bold_': (s) => '__${s}__',
  'italic_': (s) => '_${s}_',
  'underline': (s) => '++$s++',
  'strike': (s) => '~~$s~~',
  'highlight': (s) => '==$s==',
  'colour': (s) => '{{#e53935 $s}}',
  'code': (s) => '`$s`',
  'sup': (s) => '^$s^',
  'sub': (s) => '~$s~',
  'link': (s) => '[$s](https://example.test)',
};

String _kind(String name) => name.replaceAll('_', '');

/// What a style visibly did to a run of text.
Set<String> _marks(TextStyle s, double baseSize) {
  final out = <String>{};
  if ((s.fontWeight ?? FontWeight.normal).value >= FontWeight.w600.value) {
    out.add('bold');
  }
  if (s.fontStyle == FontStyle.italic) out.add('italic');
  final d = s.decoration;
  if (d != null && d.contains(TextDecoration.underline)) out.add('underline');
  if (d != null && d.contains(TextDecoration.lineThrough)) out.add('strike');
  if (s.backgroundColor?.toARGB32() == 0xFFF7E27A) out.add('highlight');
  final shadows = s.shadows ?? const <Shadow>[];
  if (s.color?.toARGB32() == _red ||
      shadows.any((x) => x.color.toARGB32() == _red)) {
    out.add('colour');
  }
  if (s.fontFamily == 'JetBrains Mono') out.add('code');
  if (shadows.isNotEmpty && (s.fontSize ?? baseSize) < baseSize) {
    out.add(shadows.first.offset.dy < 0 ? 'sup' : 'sub');
  }
  return out;
}

/// The pairs that cannot both apply, and say why.
///
/// A subscript and a superscript move the same glyph in opposite directions.
/// `~~~` is how a code fence starts, and strike-around-subscript needs it at
/// both ends. Code is literal — `` `**x**` `` shows its asterisks, by design.
bool _contradiction(String outer, String inner) =>
    {outer, inner}.containsAll({'sup', 'sub'}) ||
    (outer == 'strike' && inner == 'sub') ||
    (outer == 'sub' && inner == 'strike') ||
    outer == 'code';

void main() {
  const base = TextStyle(fontSize: 15, height: 1.5, color: Color(0xFF222222));

  // ── 1. Both renderers ────────────────────────────────────────────────────

  /// The reading view, drawn for real: a link is its own widget, and only a
  /// pumped tree shows what is inside it.
  Future<({String visible, Set<String> marks})> read(
      WidgetTester t, String src) async {
    await t.pumpWidget(MaterialApp(
      home: Material(
        child: Text.rich(TextSpan(children: inlineSpans(src, base, false)),
            style: base),
      ),
    ));
    final visible = StringBuffer();
    var marks = <String>{};
    for (final rt in t.widgetList<RichText>(find.byType(RichText))) {
      void walk(InlineSpan s, TextStyle acc) {
        if (s is! TextSpan) return;
        final st = s.style == null ? acc : acc.merge(s.style);
        final txt = s.text;
        if (txt != null && txt.isNotEmpty) {
          visible.write(txt);
          if (txt.contains('word')) marks = _marks(st, 15);
        }
        s.children?.forEach((c) => walk(c, st));
      }

      walk(rt.text, base);
    }
    // A link's arrow is decoration, not the text.
    return (
      visible: visible.toString().replaceAll(' ↗', '').replaceAll('￼', ''),
      marks: marks
    );
  }

  /// The editor, as its controller draws the buffer — hidden markers are the
  /// spans drawn at a hairline.
  ({String visible, Set<String> marks}) edit(BuildContext ctx, String src) {
    final c = LiveMarkdownController(text: src, dark: false);
    final root =
        c.buildTextSpan(context: ctx, style: base, withComposing: false);
    final visible = StringBuffer();
    var marks = <String>{};
    void walk(InlineSpan s, TextStyle acc) {
      if (s is! TextSpan) return;
      final st = s.style == null ? acc : acc.merge(s.style);
      final txt = s.text;
      if (txt != null && txt.isNotEmpty && (st.fontSize ?? 15) > 1) {
        visible.write(txt);
        if (txt.contains('word')) marks = _marks(st, 15);
      }
      s.children?.forEach((x) => walk(x, st));
    }

    walk(root, base);
    c.dispose();
    return (visible: visible.toString(), marks: marks);
  }

  Future<BuildContext> context(WidgetTester t) async {
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    return ctx;
  }

  group('one style inside another', () {
    testWidgets('THE REPORTED ONE: bold and colour, in both orders', (t) async {
      final ctx = await context(t);
      for (final src in ['**{{#e53935 word}}**', '{{#e53935 **word**}}']) {
        final e = edit(ctx, src);
        expect(e.visible, 'word', reason: 'editor, $src');
        expect(e.marks, containsAll({'bold', 'colour'}), reason: 'editor, $src');
        final r = await read(t, src);
        expect(r.visible, 'word', reason: 'reading, $src');
        expect(r.marks, containsAll({'bold', 'colour'}), reason: 'reading, $src');
      }
    });

    testWidgets('every pair, both ways round, in the editor', (t) async {
      final ctx = await context(t);
      final wrong = <String>[];
      for (final o in _styles.keys) {
        for (final i in _styles.keys) {
          if (_kind(o) == _kind(i) || _contradiction(_kind(o), _kind(i))) {
            continue;
          }
          final src = _styles[o]!(_styles[i]!('word'));
          final want = {_kind(o), _kind(i)}
            ..remove('link')
            ..addAll({if (o == 'link' || i == 'link') 'underline'});
          final e = edit(ctx, src);
          if (e.visible != 'word' || !e.marks.containsAll(want)) {
            wrong.add('$src -> "${e.visible}" ${e.marks}');
          }
        }
      }
      expect(wrong, isEmpty);
    });

    testWidgets('and the same pairs when read', (t) async {
      final wrong = <String>[];
      for (final o in _styles.keys) {
        for (final i in _styles.keys) {
          if (_kind(o) == _kind(i) || _contradiction(_kind(o), _kind(i))) {
            continue;
          }
          final src = _styles[o]!(_styles[i]!('word'));
          final want = {_kind(o), _kind(i)}
            ..remove('link')
            ..addAll({if (o == 'link' || i == 'link') 'underline'});
          final r = await read(t, src);
          if (r.visible != 'word' || !r.marks.containsAll(want)) {
            wrong.add('$src -> "${r.visible}" ${r.marks}');
          }
        }
      }
      expect(wrong, isEmpty);
    });

    testWidgets('a style on PART of another — the start or the end of it',
        (t) async {
      // `**big *word***`: italicise the last word of a bold phrase. The
      // closing `**` sits against the italic's `*`, which plain bold may not
      // end on, so it stopped one star early. 25 of these broke.
      final ctx = await context(t);
      final wrong = <String>[];
      for (final o in _styles.keys) {
        for (final i in _styles.keys) {
          // A run inside the same style is not something the toolbar writes —
          // applying bold inside bold takes the bold off. Sub- and
          // superscripts are one token, with no space for "part of".
          if (_kind(o) == _kind(i) || _contradiction(_kind(o), _kind(i))) {
            continue;
          }
          if ({'sup', 'sub', 'link'}.contains(_kind(o)) || i == 'link') {
            continue;
          }
          for (final atEnd in [false, true]) {
            final inner = _styles[i]!('word');
            final src = _styles[o]!(atEnd ? 'big $inner' : '$inner big');
            final want = atEnd ? 'big word' : 'word big';
            final e = edit(ctx, src);
            final r = await read(t, src);
            if (e.visible != want || r.visible != want) {
              wrong.add('$src -> editor "${e.visible}", read "${r.visible}"');
            }
          }
        }
      }
      expect(wrong, isEmpty);
    });

    testWidgets('a colour inside a colour — recolouring part of a phrase',
        (t) async {
      final ctx = await context(t);
      for (final src in [
        '{{#1e88e5 big {{#e53935 word}}}}',
        '{{#1e88e5 {{#e53935 word}} big}}',
      ]) {
        final e = edit(ctx, src);
        expect(e.visible, contains('word'));
        expect(e.visible, isNot(contains('{{')), reason: src);
        expect(e.visible, isNot(contains('}}')), reason: src);
        expect(e.marks, contains('colour'),
            reason: 'the inner colour is the one on the word');
      }
    });

    testWidgets('and the editor and the reading view agree, pair for pair',
        (t) async {
      // Text that changes shape on click-in is its own bug; this whole
      // grammar exists to stop that.
      final ctx = await context(t);
      for (final src in [
        '**{{#e53935 word}}**',
        '==**word**==',
        '~~++word++~~',
        '**big *word***',
        '{{#e53935 ^word^}}',
        '^{{#e53935 word}}^',
        '[**word**](https://example.test)',
      ]) {
        final e = edit(ctx, src);
        final r = await read(t, src);
        expect(r.visible, e.visible, reason: src);
        expect(r.marks, e.marks, reason: src);
      }
    });
  });

  group('the Markdown export', () {
    test('keeps every other style and drops colour, at any depth', () {
      // Colour is not standard Markdown, so the export degrades it to its
      // text. One pass of that took a colour inside a colour only as far as
      // the first `}}`.
      expect(markdownInline('**{{#e53935 word}}**'), '**word**');
      expect(markdownInline('{{#e53935 **word**}}'), '**word**');
      expect(markdownInline('{{#1e88e5 big {{#e53935 word}}}}'), 'big word');
    });

    test('and the PDF prints the words, whatever the nesting', () {
      // The PDF draws text plain, so all it must do is lose every marker.
      String pdf(String t) => debugPlainText(Block(
          type: BlockType.text, x: 0, y: 0, w: 400, content: {'text': t}));
      expect(pdf('**{{#e53935 word}}**'), 'word');
      expect(pdf('{{#e53935 **word**}}'), 'word');
      expect(pdf('{{#1e88e5 big {{#e53935 word}}}}'), 'big word');
    });
  });

  // ── 3. The caret ──────────────────────────────────────────────────────────

  group('the caret, with markers inside markers', () {
    test('knows every hidden marker, at every depth', () {
      final c = LiveMarkdownController(
          text: '**{{#e53935 word}}**', dark: false);
      expect(
          c.hiddenMarkerRanges().map((r) => '${r.start}-${r.end}').toSet(),
          {'0-2', '18-20', '2-12', '16-18'},
          reason: 'bold\'s two, and the colour\'s two inside it');
      c.dispose();
    });

    TextEditingValue at(String text, int caret) => TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: caret));

    test('Backspace at the end deletes the last letter, not a marker', () {
      // The bold run's "last character before my closer" is the colour's
      // `}`. Asking one run at a time, Backspace broke the colour.
      final c = LiveMarkdownController(dark: false);
      final r = c.markerAwareDelete(at('**{{#e53935 word}}**', 20),
          forward: false)!;
      expect(r.text, '**{{#e53935 wor}}**');
      c.dispose();
    });

    test('emptying nested runs takes every marker with them', () {
      final c = LiveMarkdownController(dark: false);
      final r = c.markerAwareDelete(at('a **{{#e53935 w}}** b', 19),
          forward: false)!;
      expect(r.text, 'a  b', reason: 'no `****` or `{{#e53935 }}` left over');
      c.dispose();
    });

    test('Delete at the start deletes the first letter', () {
      final c = LiveMarkdownController(dark: false);
      final r = c.markerAwareDelete(at('**{{#e53935 word}}**', 0),
          forward: true)!;
      expect(r.text, '**{{#e53935 ord}}**');
      c.dispose();
    });

    test('Backspace at the start of a run after another run', () {
      // Old behaviour: deleted one of the bold run's closing `*`.
      final c = LiveMarkdownController(dark: false);
      final r = c.markerAwareDelete(at('**ab**{{#e53935 cd}}', 16),
          forward: false)!;
      expect(r.text, '**a**{{#e53935 cd}}');
      c.dispose();
    });
  });

  // ── 4. The toolbar ────────────────────────────────────────────────────────

  group('the toolbar, in either order', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());
    late Directory tmp;
    late Repository repo;
    late AppState app;
    late LiveMarkdownController c;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_stylecombo_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('T');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      await app.selectPage(
          app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
      final block =
          Block(type: BlockType.text, x: 0, y: 0, content: {'text': ''});
      app.addBlock(block, recordUndo: false);
      // The real controller, so its idea of what is hidden is the one used.
      c = LiveMarkdownController(dark: false);
      app.setActiveEditor(c, block, 'text');
    });

    tearDown(() {
      AppState.syncLogEnabled = true;
      if (!haveSqlite) return;
      app.cancelPendingSave();
      c.dispose();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    /// Text with `«…»` marking the selection.
    void put(String spec) {
      final b = spec.indexOf('«');
      final e = spec.indexOf('»') - 1;
      c.value = TextEditingValue(
          text: spec.replaceAll('«', '').replaceAll('»', ''),
          selection: TextSelection(baseOffset: b, extentOffset: e));
    }

    test('bold, then colour', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      put('a «word» b');
      app.wrapSelection('**');
      app.applyTextColor('e53935');
      expect(c.text, 'a **{{#e53935 word}}** b');
    });

    test('colour, then bold', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      put('a «word» b');
      app.applyTextColor('e53935');
      app.wrapSelection('**');
      expect(c.text, 'a {{#e53935 **word**}} b');
    });

    for (final (label, src, want) in [
      ('colour inside bold', 'a **{{#e53935 «word»}}** b', 'a {{#e53935 word}} b'),
      ('bold inside colour', 'a {{#e53935 **«word»**}} b', 'a {{#e53935 word}} b'),
    ]) {
      test('taking bold off: $label', () {
        if (!haveSqlite) return markTestSkipped('sqlite unavailable');
        put(src);
        app.wrapSelection('**');
        expect(c.text, want);
      });
    }

    for (final (label, src, want) in [
      ('colour inside bold', 'a **{{#e53935 «word»}}** b', 'a **word** b'),
      ('bold inside colour', 'a {{#e53935 **«word»**}} b', 'a **word** b'),
    ]) {
      test('taking colour off: $label', () {
        // The second was the bug: the colour's opener is not right beside the
        // selection — the bold's is — so the toggle wrapped a second red
        // inside the first instead of removing it.
        if (!haveSqlite) return markTestSkipped('sqlite unavailable');
        put(src);
        app.toggleTextColor();
        expect(c.text, want);
      });
    }

    test('recolouring a red bold word changes the one colour run', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      put('a {{#e53935 **«word»**}} b');
      app.applyTextColor('1e88e5');
      expect(c.text, 'a {{#1e88e5 **word**}} b');
    });

    test('a selection dragged over the invisible markers is the same one', () {
      // Markers have no width, so a drag can start and end either side of
      // them. All of the run selected, markers included, is still "this word".
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      put('a «{{#e53935 **word**}}» b');
      app.wrapSelection('**');
      expect(c.text, 'a {{#e53935 word}} b');
    });

    test('italicising the last word of a bold phrase', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      put('**big «word»**');
      app.wrapSelection('*');
      expect(c.text, '**big *word***',
          reason: 'what the toolbar has always written — and it now reads');
    });

    test('recolouring part of a coloured phrase', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      put('{{#1e88e5 big «word»}}');
      app.applyTextColor('e53935');
      expect(c.text, '{{#1e88e5 big {{#e53935 word}}}}');
    });
  });
}
