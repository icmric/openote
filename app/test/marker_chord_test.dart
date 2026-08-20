// Ctrl + a Markdown marker character wraps the word at the caret in it, and
// pressing it again adds a layer until the grammar stops accepting one.
//
// Everything about "which characters" and "how far" is asserted against
// AppState.markerChordLadders, which is MEASURED from markdown/md_syntax.dart
// rather than listed by hand — so these tests pin the measurement, not a
// second copy of the grammar.
//
// The shell group sends real key events at the real AppShell, because
// reasoning about Flutter key handling from source has been wrong in this
// repo before (see keyboard_regions_test.dart's opening note), and because
// the one detail most likely to make this feature work on one keyboard and
// not another — binding the CHARACTER PRODUCED rather than the key — can only
// be shown by handing the shell an event whose key and character disagree.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/markdown/md_syntax.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';
import 'package:openote/ui/keyboard_map.dart';

import 'support/sqlite.dart';

void main() {
  // ── The ladder, measured ────────────────────────────────────────────────
  group('the chord alphabet comes from the grammar', () {
    final ladders = AppState.markerChordLadders;

    test('exactly the grammar\'s own symmetric inline markers, no others', () {
      // Not "these are the ones we wanted": these are the characters for
      // which md_syntax actually matches `cXc` (or `ccXcc`) as one run. If a
      // branch is added to or removed from the grammar this list moves, which
      // is the point of measuring it.
      expect(ladders.keys.toSet(),
          {'*', '_', '`', '~', '^', r'$', '=', '+'});
    });

    test('asterisks climb to three and stop — ****x**** is not emphasis', () {
      expect(ladders['*'], [1, 2, 3]);
      // The proof, straight from the scanner: a fourth pair pushes the match
      // one asterisk in and strands one at each end.
      final m = mdInlineRe.firstMatch('****x****')!;
      expect(m.start, 1);
      expect(m.group(0), '***x***');
    });

    test('a tilde ladder crosses two marks: subscript, then strikethrough',
        () {
      expect(ladders['~'], [1, 2]);
      expect(classifyInline(mdInlineRe.firstMatch('~x~')!).kind,
          MdInline.subscript);
      expect(classifyInline(mdInlineRe.firstMatch('~~x~~')!).kind,
          MdInline.strike);
      // And three really is refused rather than merely undesired: the match
      // stops one tilde short of the end.
      final m = mdInlineRe.firstMatch('~~~x~~~')!;
      expect(m.end, lessThan('~~~x~~~'.length));
    });

    test('marks whose inner class excludes their own marker cap at one', () {
      expect(ladders['^'], [1]);
      expect(ladders['`'], [1]);
      // The dollar grew a SECOND rung when the display grammar landed
      // (v0.20 D.5): one press wraps an inline equation, a second press
      // makes it display maths — the inline-to-display toggle v0.18 s7
      // promised, arriving through the same ladder bold already taught.
      expect(ladders[r'$'], [1, 2]);
    });

    test('highlight and underline ladders START at two', () {
      // `=x=` and `+x+` are not marks at all, so one press must write both
      // characters or none — there is no rung below two to stand on.
      expect(ladders['='], [2]);
      expect(ladders['+'], [2]);
      expect(mdInlineRe.firstMatch('=x='), isNull);
      expect(mdInlineRe.firstMatch('+x+'), isNull);
    });

    test('a character Markdown does not use has no ladder at all', () {
      for (final ch in ['#', '@', '-', '/', '%', 'a', '8', '"', '|', '.']) {
        expect(ladders[ch], isNull, reason: '"$ch" is not a marker');
      }
    });

    test('every ladder is documented in the keyboard map', () {
      // A shortcut nobody can discover does not exist to a student. `=` and
      // `+` are deliberately absent: Ctrl+= and Ctrl++ are already subscript
      // and superscript, so the chord can never be reached with them on the
      // layouts we ship.
      final writing =
          keyboardMap.firstWhere((s) => s.title == 'While writing');
      final keys = writing.bindings.map((b) => b.keys).join(' ');
      for (final ch in ladders.keys) {
        if (ch == '=' || ch == '+') continue;
        expect(keys, contains('Ctrl+$ch'),
            reason: 'Ctrl+$ch works but Ctrl+/ never mentions it');
      }
    });
  });

  // ── The command ─────────────────────────────────────────────────────────
  group('cycleMarker', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    late Directory tmp;
    late Repository repo;
    late AppState app;
    late TextEditingController c;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_chord_');
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
      c = TextEditingController();
      app.setActiveEditor(c, block, 'text');
    });

    tearDown(() {
      AppState.syncLogEnabled = true;
      if (!haveSqlite) return;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    /// Put `text` in the editor with the caret at `|`, or a selection `«…»`.
    void edit(String spec) {
      final b = spec.indexOf('«');
      if (b >= 0) {
        final e = spec.indexOf('»');
        c.value = TextEditingValue(
          text: spec.replaceAll('«', '').replaceAll('»', ''),
          selection: TextSelection(baseOffset: b, extentOffset: e - 1),
        );
        return;
      }
      final i = spec.indexOf('|');
      c.value = TextEditingValue(
        text: spec.replaceFirst('|', ''),
        selection: TextSelection.collapsed(offset: i),
      );
    }

    test('at the END of a word it wraps that word', () {
      if (!haveSqlite) return;
      edit('hello| world');
      expect(app.cycleMarker('*'), isTrue);
      expect(c.text, '*hello* world');
      // The word stays under the selection, exactly as Ctrl+B leaves it, so
      // the next press has something to climb.
      expect(c.text.substring(c.selection.start, c.selection.end), 'hello');
    });

    test('INSIDE a word it wraps the same whole word', () {
      if (!haveSqlite) return;
      edit('hel|lo world');
      app.cycleMarker('*');
      expect(c.text, '*hello* world');
    });

    test('press again for bold, again for both, and then nothing', () {
      if (!haveSqlite) return;
      edit('hello| world');
      app.cycleMarker('*');
      expect(c.text, '*hello* world');
      app.cycleMarker('*');
      expect(c.text, '**hello** world');
      app.cycleMarker('*');
      expect(c.text, '***hello*** world');
      // The product owner's own example: `****this****` is refused. Note it
      // is refused SILENTLY — writing the markers anyway would leave four
      // asterisks the reader can see and no renderer can match.
      expect(app.cycleMarker('*'), isTrue, reason: 'the chord is still ours');
      expect(c.text, '***hello*** world', reason: 'a fourth layer is refused');
    });

    test('the caret keeps its own character on every rung', () {
      if (!haveSqlite) return;
      edit('say hell|o');
      app.cycleMarker('*');
      // wrapSelection leaves the word selected; the offsets below track that
      // selection through each widening of the opening marker.
      expect(c.selection.start, 5, reason: 'past the one new asterisk');
      expect(c.selection.end, 10);
      app.cycleMarker('*');
      expect(c.text, 'say **hello**');
      expect(c.selection.start, 6, reason: 'the opening marker grew by one');
      expect(c.selection.end, 11);
      app.cycleMarker('*');
      expect(c.text, 'say ***hello***');
      expect(c.selection.start, 7);
      expect(c.selection.end, 12);
      expect(c.text.substring(c.selection.start, c.selection.end), 'hello');
    });

    test('with a real selection it wraps the selection, not the word', () {
      if (!haveSqlite) return;
      edit('one «two three» four');
      app.cycleMarker('*');
      expect(c.text, 'one *two three* four');
      app.cycleMarker('*');
      expect(c.text, 'one **two three** four');
    });

    test('a right-to-left selection wraps the same run', () {
      if (!haveSqlite) return;
      // Dragging backwards puts base after extent; wrapSelection normalises
      // it, and the chord must not undo that by reading baseOffset directly.
      c.value = const TextEditingValue(
        text: 'one two three',
        selection: TextSelection(baseOffset: 7, extentOffset: 4),
      );
      app.cycleMarker('*');
      expect(c.text, 'one *two* three');
    });

    test('the tilde ladder is subscript, then crossed out, then refused', () {
      if (!haveSqlite) return;
      edit('CO2 is not CO|2 yet');
      app.cycleMarker('~');
      expect(c.text, 'CO2 is not ~CO2~ yet');
      expect(scanKinds(c.text), contains(MdInline.subscript));
      app.cycleMarker('~');
      expect(c.text, 'CO2 is not ~~CO2~~ yet',
          reason: 'one more tilde a side IS strikethrough');
      expect(scanKinds(c.text), contains(MdInline.strike));
      app.cycleMarker('~');
      expect(c.text, 'CO2 is not ~~CO2~~ yet', reason: 'three is not a mark');
    });

    test('one-rung ladders wrap once and refuse the second press', () {
      if (!haveSqlite) return;
      for (final ch in ['`', '^']) {
        edit('a wo|rd');
        app.cycleMarker(ch);
        expect(c.text, 'a ${ch}word$ch', reason: '$ch wrapped the word');
        app.cycleMarker(ch);
        expect(c.text, 'a ${ch}word$ch',
            reason: '$ch has one rung and must stay on it');
      }
    });

    test('the dollar ladder climbs to display maths and stops', () {
      if (!haveSqlite) return;
      // Inline to display in one more press (v0.18 s7's promised toggle);
      // the third press has nowhere to go and must change nothing.
      edit('a wo|rd');
      app.cycleMarker(r'$');
      expect(c.text, r'a $word$', reason: 'first press: an inline equation');
      app.cycleMarker(r'$');
      expect(c.text, r'a $$word$$', reason: 'second press: display maths');
      app.cycleMarker(r'$');
      expect(c.text, r'a $$word$$',
          reason: 'no third rung exists, so nothing may change');
    });

    test('highlight is reached in ONE press, because =x= is not a mark', () {
      if (!haveSqlite) return;
      edit('a wo|rd');
      app.cycleMarker('=');
      expect(c.text, 'a ==word==');
      expect(scanKinds(c.text), contains(MdInline.highlight));
      app.cycleMarker('=');
      expect(c.text, 'a ==word==');
    });

    test('underscores climb italic then bold and stop at two', () {
      if (!haveSqlite) return;
      edit('a wo|rd');
      app.cycleMarker('_');
      expect(c.text, 'a _word_');
      app.cycleMarker('_');
      expect(c.text, 'a __word__');
      app.cycleMarker('_');
      expect(c.text, 'a __word__');
    });

    test('a character the grammar does not use is not ours at all', () {
      if (!haveSqlite) return;
      edit('a wo|rd');
      for (final ch in ['#', '@', '-', 'q', '/']) {
        expect(app.cycleMarker(ch), isFalse,
            reason: 'Ctrl+$ch must fall through to the field, not be eaten');
      }
      expect(c.text, 'a word', reason: 'and nothing was written');
    });

    test('already bold AND italic refuses rather than nesting a fourth', () {
      if (!haveSqlite) return;
      // The caret in the `it` of `**bold *it* end**` sits under three
      // asterisks a side. A fourth would write `**bold **it** end**`, which
      // the grammar re-reads as one bold run containing a literal `**` — two
      // asterisks the student can see and cannot remove in one press.
      edit('**bold *i|t* end**');
      app.cycleMarker('*');
      expect(c.text, '**bold *it* end**');
    });

    test('layers COUNT, however they are nested', () {
      if (!haveSqlite) return;
      // `***a *b* c***` puts FOUR asterisks a side around `b`: three from the
      // bold+italic run and one from the italic inside it. Reading only the
      // nearest run would call that one layer, and "add a layer" would then
      // rewrite the OUTER run two asterisks wide — quietly un-italicising a
      // whole phrase the student never touched.
      edit('x ***a *|b* c*** y');
      expect(app.cycleMarker('*'), isTrue);
      expect(c.text, 'x ***a *b* c*** y');
    });

    test('a nested run climbs on its own, not the one around it', () {
      if (!haveSqlite) return;
      edit('==hi wo|rd there==');
      app.cycleMarker('*');
      expect(c.text, '==hi *word* there==');
      app.cycleMarker('*');
      expect(c.text, '==hi **word** there==',
          reason: 'the asterisks climbed; the highlight was left alone');
    });

    test('nothing to wrap writes nothing', () {
      if (!haveSqlite) return;
      edit('a | b');
      app.cycleMarker('*');
      expect(c.text, 'a  b',
          reason: 'a bare `**` at the caret matches no renderer for ever');
    });

    test('a code cell is left alone — ** is multiplication there', () {
      if (!haveSqlite) return;
      final code = Block(
          type: BlockType.code, x: 0, y: 0, content: {'text': 'a = b'});
      app.addBlock(code, recordUndo: false);
      final cc = TextEditingController(text: 'a = b');
      app.setActiveEditor(cc, code, 'text');
      cc.selection = const TextSelection.collapsed(offset: 5);
      expect(app.cycleMarker('*'), isTrue, reason: 'swallowed, not typed');
      expect(cc.text, 'a = b');
    });

    test('a rung records an undo step; a refused press records nothing', () {
      if (!haveSqlite) return;
      edit('a wo|rd');
      app.cycleMarker('*');
      expect(c.text, 'a *word*');
      expect(app.canUndo, isTrue, reason: 'a chord pressed by accident is one '
          'Ctrl+Z away, exactly as Ctrl+B is');
      app.undo(); // moves that step onto the redo stack
      expect(app.canRedo, isTrue);

      c.value = const TextEditingValue(
          text: 'a ***word***',
          selection: TextSelection.collapsed(offset: 7));
      expect(app.cycleMarker('*'), isTrue, reason: 'top of the ladder');
      expect(c.text, 'a ***word***');
      // pushUndo clears the redo stack. A redo that is still live is the
      // proof that the refused press did not touch the history at all — it
      // must be a no-op, not an edit that happens to write the same text.
      expect(app.canRedo, isTrue,
          reason: 'a refused press must not record a step');
    });
  });

  // ── Through the real shell ──────────────────────────────────────────────
  group('the chord from the keyboard', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    late Directory tmp;
    late Repository repo;
    late AppState app;
    late Block a;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_chordkey_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Study');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      final page = app.nodes.firstWhere((n) => n.kind == NodeKind.page);
      a = Block(
          type: BlockType.text,
          x: 40,
          y: 120,
          w: 320,
          h: 170,
          content: {'text': 'hello world'});
      app.importPage(nb.id, page.id, [a], PageProps());
      app.reloadNodes();
      await app.selectPage(page.id);
      app.markOnboardingSeen();
    });

    tearDown(() {
      AppState.syncLogEnabled = true;
      if (!haveSqlite) return;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<void> pumpShell(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: onoteTheme(Brightness.light),
        home: AppShell(app: app),
      ));
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
    }

    /// Start editing the seeded box with the caret at the end of `hello`.
    Future<TextEditingController> editing(WidgetTester tester) async {
      await pumpShell(tester);
      app.select(a.id, edit: true);
      await tester.pumpAndSettle();
      final ctl = app.activeEditor!.controller;
      ctl.selection = const TextSelection.collapsed(offset: 5);
      await tester.pump();
      return ctl;
    }

    /// Press `key` while it produces `character`, returning whether the app
    /// swallowed the keystroke.
    ///
    /// The two are given SEPARATELY on purpose. `*` is Shift+8 on a US
    /// keyboard, so Windows reports the logical key `digit8` and the
    /// character `*` — an event whose key says one thing and whose character
    /// says another is the only way to show which of the two the chord is
    /// bound to.
    Future<bool> press(
      WidgetTester tester,
      LogicalKeyboardKey key, {
      String? character,
      bool ctrl = false,
      bool shift = false,
    }) async {
      if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final handled =
          await tester.sendKeyDownEvent(key, character: character);
      await tester.sendKeyUpEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      return handled;
    }

    Future<void> flush(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
    }

    testWidgets('Ctrl+* climbs italic, bold, both, then refuses',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final ctl = await editing(tester);

      // digit8 + the character `*`: a US keyboard's Shift+8. Binding the KEY
      // would tie this chord to one layout and break it on every other.
      expect(
          await press(tester, LogicalKeyboardKey.digit8,
              character: '*', ctrl: true, shift: true),
          isTrue);
      expect(ctl.text, '*hello* world');
      expect(ctl.selection.start, 1);
      expect(ctl.selection.end, 6);

      await press(tester, LogicalKeyboardKey.digit8,
          character: '*', ctrl: true, shift: true);
      expect(ctl.text, '**hello** world');
      expect(ctl.selection.start, 2, reason: 'the caret rode the wider marker');

      await press(tester, LogicalKeyboardKey.digit8,
          character: '*', ctrl: true, shift: true);
      expect(ctl.text, '***hello*** world');

      await press(tester, LogicalKeyboardKey.digit8,
          character: '*', ctrl: true, shift: true);
      expect(ctl.text, '***hello*** world', reason: 'no fourth layer');
      expect(app.editingBlockId, a.id, reason: 'still writing in the box');
      await flush(tester);
    });

    testWidgets('Ctrl+~ is subscript then crossed out, on the ` key',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final ctl = await editing(tester);
      await press(tester, LogicalKeyboardKey.backquote,
          character: '~', ctrl: true, shift: true);
      expect(ctl.text, '~hello~ world');
      await press(tester, LogicalKeyboardKey.backquote,
          character: '~', ctrl: true, shift: true);
      expect(ctl.text, '~~hello~~ world');
      await flush(tester);
    });

    testWidgets('Ctrl + a character Markdown does not use does NOTHING',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final ctl = await editing(tester);
      // Shift+7 on a US keyboard. Not a marker, so the shell must not eat it:
      // swallowing every Ctrl+punctuation would take dead keys and the
      // field's own accelerators away from the editor.
      final handled = await press(tester, LogicalKeyboardKey.digit7,
          character: '&', ctrl: true, shift: true);
      expect(handled, isFalse, reason: 'the keystroke must reach the field');
      expect(ctl.text, 'hello world');
      await flush(tester);
    });

    testWidgets('plain * ~ ^ and ` still type — the chord needs Ctrl',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The regression this guards: canvas-level handling once shadowed the
      // editors outright (arrows moved between boxes instead of the caret),
      // and a chord keyed on a bare printable character would do it again for
      // the four characters a maths or code note is full of. A widget test
      // cannot show the field INSERTING the character — that happens in the
      // platform text input service, which does not run here — so the claim
      // made is the one that matters: the shell does not handle the key, and
      // writes nothing of its own.
      final ctl = await editing(tester);
      for (final (key, ch) in [
        (LogicalKeyboardKey.digit8, '*'),
        (LogicalKeyboardKey.backquote, '~'),
        (LogicalKeyboardKey.digit6, '^'),
        (LogicalKeyboardKey.backquote, '`'),
      ]) {
        final handled =
            await press(tester, key, character: ch, shift: ch != '`');
        expect(handled, isFalse, reason: 'typing "$ch" was swallowed');
        expect(ctl.text, 'hello world', reason: 'typing "$ch" wrapped a word');
      }
      await flush(tester);
    });

    testWidgets('the older chords still mean what they always did',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final ctl = await editing(tester);

      await press(tester, LogicalKeyboardKey.keyB, character: 'b', ctrl: true);
      expect(ctl.text, '**hello** world', reason: 'Ctrl+B is still bold');
      ctl.selection = const TextSelection.collapsed(offset: 7);
      await press(tester, LogicalKeyboardKey.keyB, character: 'b', ctrl: true);
      expect(ctl.text, 'hello world', reason: 'and still toggles off');

      // Ctrl+= keeps subscript even though `=` has a ladder of its own — the
      // named accelerators are checked first, so nothing was taken away.
      ctl.selection = const TextSelection.collapsed(offset: 5);
      await press(tester, LogicalKeyboardKey.equal,
          character: '=', ctrl: true);
      expect(ctl.text, '~hello~ world');
      expect(ctl.text.contains('=='), isFalse);

      ctl.selection = const TextSelection.collapsed(offset: 3);
      await press(tester, LogicalKeyboardKey.equal,
          character: '+', ctrl: true, shift: true);
      expect(ctl.text, '^hello^ world', reason: 'Ctrl+Shift+= is superscript');
      await flush(tester);
    });

    testWidgets('a letter chord is never mistaken for a marker',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Windows reports Ctrl+Z as U+001A. Without the control-code guard in
      // `_producedCharacter` a raw code point could collide with a marker, so
      // the undo chord is pressed with the character Windows really sends.
      final ctl = await editing(tester);
      await press(tester, LogicalKeyboardKey.keyB, character: 'b', ctrl: true);
      expect(ctl.text, '**hello** world');
      await press(tester, LogicalKeyboardKey.keyZ,
          character: '', ctrl: true);
      expect(app.activeEditor!.controller.text, 'hello world',
          reason: 'Ctrl+Z is undo, not a marker chord');
      await flush(tester);
    });
  });
}

/// Every inline kind md_syntax finds in [t] — the grammar's own reading of
/// what the chord just wrote.
Set<MdInline> scanKinds(String t) => {
      for (final m in mdInlineRe.allMatches(t)) classifyInline(m).kind,
    };
