// The code cell as an editor (PLANNING "Code editor"): it knows what
// language it is holding, it says which of them actually run here, and it
// types like an IDE — pairs close, Tab indents, Enter keeps the indent and
// pushes `}` down a line.
//
// Nearly all of it is pure `(text, selection) → (text, selection)`, so it is
// pinned here without a widget; the handful of widget tests only prove the
// wiring (formatters installed, Tab reaching the field, detection landing in
// the block).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/code/code_runner.dart';
import 'package:openote/editor/code_block_view.dart';
import 'package:openote/editor/code_highlight.dart';
import 'package:openote/editor/code_languages.dart';
import 'package:openote/editor/wrap_selection.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

/// `|` is the caret, `[`…`]` a selection — the whole state of a field in one
/// readable string, so a test reads like the thing a person would do.
TextEditingValue _v(String s) {
  // A caret wins over the brackets, so `a[|]` is a caret between real ones.
  final at = s.indexOf('|');
  if (at >= 0) {
    return TextEditingValue(
      text: s.replaceFirst('|', ''),
      selection: TextSelection.collapsed(offset: at),
    );
  }
  final start = s.indexOf('[');
  return TextEditingValue(
    text: s.replaceFirst('[', '').replaceFirst(']', ''),
    selection:
        TextSelection(baseOffset: start, extentOffset: s.indexOf(']') - 1),
  );
}

String _show(TextEditingValue v) {
  final s = v.selection;
  if (s.isCollapsed) return v.text.replaceRange(s.baseOffset, s.baseOffset, '|');
  return v.text
      .replaceRange(s.end, s.end, ']')
      .replaceRange(s.start, s.start, '[');
}

final _dart = languageFor('dart');

/// One character typed at the caret, as the platform would report it.
String _type(String state, String ch, [CodeLanguage? lang]) {
  final before = _v(state);
  final at = before.selection.start;
  final after = TextEditingValue(
    text: before.text.replaceRange(at, before.selection.end, ch),
    selection: TextSelection.collapsed(offset: at + ch.length),
  );
  return _show(applyCodeTyping(before, after, lang ?? _dart) ?? after);
}

/// Backspace at the caret.
String _backspace(String state, [CodeLanguage? lang]) {
  final before = _v(state);
  final at = before.selection.baseOffset;
  final after = TextEditingValue(
    text: before.text.replaceRange(at - 1, at, ''),
    selection: TextSelection.collapsed(offset: at - 1),
  );
  return _show(applyCodeTyping(before, after, lang ?? _dart) ?? after);
}

String _tab(String state, {bool outdent = false, CodeLanguage? lang}) {
  final v = _v(state);
  return _show(handleCodeTab(v, lang ?? _dart, outdent: outdent) ?? v);
}

void main() {
  // ── The registry ────────────────────────────────────────────────────────
  group('the language list', () {
    test('a fence label reaches the language it names, however spelled', () {
      expect(languageFor('c++').id, 'cpp');
      expect(languageFor('CXX').id, 'cpp');
      expect(languageFor('c#').id, 'csharp');
      expect(languageFor('cs').id, 'csharp');
      expect(languageFor('javascript').id, 'js');
      expect(languageFor('node').id, 'js');
      expect(languageFor('py').id, 'python');
      expect(languageFor('yml').id, 'yaml');
      expect(languageFor(' Dart ').id, 'dart');
    });

    test('anything unknown, empty or missing is plain text, never a crash',
        () {
      expect(languageFor(null).id, kDefaultLanguageId);
      expect(languageFor('').id, kDefaultLanguageId);
      expect(languageFor('brainfuck').id, kDefaultLanguageId);
    });

    test('display names are what a person reads', () {
      expect(languageFor('cpp').name, 'C++');
      expect(languageFor('csharp').name, 'C#');
      expect(languageFor('js').name, 'JavaScript');
      expect(languageFor(kDefaultLanguageId).name, 'Plain text');
    });

    test('the runnable group is EXACTLY what the runner will run', () {
      final marked = [
        for (final l in codeLanguages)
          if (l.group == kRunsHereGroup) l.id
      ];
      expect(marked, ['sql', 'js'], reason: 'and they lead the menu');
      for (final l in codeLanguages) {
        expect(l.runnable, isRunnableLanguage(l.id),
            reason: '${l.id} must not promise a run the runner refuses');
        expect(l.runnable, l.group == kRunsHereGroup,
            reason: 'the group IS the promise');
      }
    });

    test('C, C++ and C# sit together, in that order', () {
      final family = [
        for (final l in codeLanguages)
          if (l.group == 'C family') l.id
      ];
      expect(family, ['c', 'cpp', 'csharp']);
    });

    test('the menu holds every language once, runnable first', () {
      final flat = [
        for (final g in codeLanguageMenu)
          for (final l in g.languages) l.id
      ];
      expect(flat, codeLanguages.map((l) => l.id).toList());
      expect(flat.toSet().length, flat.length, reason: 'no duplicates');
      expect(codeLanguageMenu.first.title, kRunsHereGroup);
      expect(codeLanguageMenu.last.languages.single.id, kDefaultLanguageId);
    });

    test('pairing and wrap-on-selection agree on the pair set', () {
      expect(languageFor('dart').pairs, WrapSelectionFormatter.bracketPairs,
          reason: 'typing ( with a selection wraps, without one pairs — one '
              'set, two halves');
      expect(languageFor('rust').pairs.containsKey("'"), isFalse,
          reason: "&'a str is a lifetime, not an unterminated string");
      expect(languageFor('python').indent, 4);
      expect(languageFor('dart').indent, 2);
    });
  });

  // ── Detection ───────────────────────────────────────────────────────────
  group('detecting the language', () {
    void detects(String id, String source) {
      test('reads $id', () => expect(detectLanguage(source), id));
    }

    detects('python', r'''
def area(r):
    return 3.14 * r * r

print(area(2))
''');
    detects('js', r'''
const nums = [1, 2, 3];
const total = nums.reduce((a, b) => a + b, 0);
console.log(total);
''');
    detects('ts', r'''
interface Student {
  name: string;
  mark: number;
}

function top(list: Student[]): string {
  return list[0].name;
}
''');
    detects('dart', r'''
import 'package:flutter/material.dart';

void main() {
  final greeting = 'hi';
  print(greeting);
}
''');
    detects('rust', r'''
fn main() {
    let mut total = 0;
    for i in 1..10 {
        total += i;
    }
    println!("{}", total);
}
''');
    detects('c', r'''
#include <stdio.h>

int main(void) {
    printf("Hello\n");
    return 0;
}
''');
    detects('cpp', r'''
#include <iostream>

int main() {
    std::string name = "world";
    std::cout << "Hello " << name << std::endl;
    return 0;
}
''');
    detects('csharp', r'''
using System;

namespace Marks
{
    class Program
    {
        static void Main(string[] args)
        {
            Console.WriteLine("Hello");
        }
    }
}
''');
    detects('java', r'''
import java.util.List;

public class Main {
    public static void main(String[] args) {
        System.out.println("Hi");
    }
}
''');
    detects('kotlin', r'''
data class Student(val name: String, val mark: Int)

fun main() {
    val s = Student("Ana", 91)
    println(s.name)
}
''');
    detects('go', r'''
package main

import "fmt"

func main() {
    fmt.Println("Hello")
}
''');
    detects('sql', r'''
SELECT unit, AVG(mark) AS average
FROM results
WHERE mark > 50
GROUP BY unit
ORDER BY average DESC;
''');
    detects('bash', r'''
#!/bin/bash
for f in *.txt; do
  echo "$f"
done
''');
    detects('php', r'''
<?php
$name = "world";
echo "Hello $name";
''');
    detects('json', r'''
{
  "name": "Ana",
  "marks": [91, 82],
  "active": true
}
''');
    detects('yaml', r'''
name: study plan
subjects:
  - maths
  - physics
weekly: true
''');
    detects('html', r'''
<!DOCTYPE html>
<html>
  <body>
    <p>Hello</p>
  </body>
</html>
''');
    detects('css', r'''
.card {
  color: #333;
  padding: 8px;
}
''');

    test('C is not mistaken for C++, nor C++ for C', () {
      expect(detectLanguage('#include <stdio.h>\nint main() { printf("x"); }'),
          'c');
      expect(
          detectLanguage(
              '#include <vector>\nstd::vector<int> v;\nint main() { return 0; }'),
          'cpp');
    });

    test('C# is not mistaken for Java', () {
      expect(
          detectLanguage(
              'using System;\nclass P { static void Main(string[] args) { Console.WriteLine(1); } }'),
          'csharp');
    });

    test('too little to tell stays unknown — silence beats a wrong guess', () {
      expect(detectLanguage(''), isNull);
      expect(detectLanguage('x = 1'), isNull);
      expect(detectLanguage('print("hi")'), isNull);
      expect(detectLanguage('hello world, some ordinary prose'), isNull);
    });

    test('a JavaScript object literal is not JSON', () {
      expect(detectLanguage('const config = { name: "Ana", mark: 91 };'),
          isNot('json'));
    });
  });

  // ── When detection is allowed to act ────────────────────────────────────
  group('auto-language, and when it must keep quiet', () {
    const python = 'def area(r):\n    return 3.14 * r * r\n';

    test('a default block takes the language of what was pasted into it', () {
      expect(
        autoLanguageFor(
            current: 'text',
            userPicked: false,
            autoSet: false,
            previousSource: '',
            source: python),
        'python',
      );
    });

    test('A LANGUAGE THE USER PICKED IS NEVER OVERRIDDEN', () {
      expect(
        autoLanguageFor(
            current: 'sql',
            userPicked: true,
            autoSet: false,
            previousSource: '',
            source: python),
        isNull,
      );
      // Even when the pick is the default itself.
      expect(
        autoLanguageFor(
            current: 'text',
            userPicked: true,
            autoSet: false,
            previousSource: '',
            source: python),
        isNull,
      );
    });

    test('a language that arrived with the content is left alone', () {
      expect(
        autoLanguageFor(
            current: 'rust',
            userPicked: false,
            autoSet: false,
            previousSource: '',
            source: python),
        isNull,
        reason: 'an imported ```rust fence is somebody saying so',
      );
    });

    test('but an earlier GUESS may be revised by more source', () {
      expect(
        autoLanguageFor(
            current: 'js',
            userPicked: false,
            autoSet: true,
            previousSource: 'x',
            source: python),
        'python',
      );
    });

    test('one keystroke is not a reason to re-read the file', () {
      const before = 'def area(r):\n    return 3.14 * r * ';
      expect(
        autoLanguageFor(
            current: 'text',
            userPicked: false,
            autoSet: false,
            previousSource: before,
            source: '${before}r'),
        isNull,
        reason: 'mid-word the label would flicker through three languages',
      );
    });

    test('finishing a line is', () {
      const before = 'def area(r):\n    return 3.14 * r * r';
      expect(
        autoLanguageFor(
            current: 'text',
            userPicked: false,
            autoSet: false,
            previousSource: before,
            source: '$before\n'),
        'python',
      );
    });

    test('detecting what is already set changes nothing', () {
      expect(
        autoLanguageFor(
            current: 'py',
            userPicked: false,
            autoSet: true,
            previousSource: '',
            source: python),
        isNull,
        reason: 'the alias resolves to the same language',
      );
    });
  });

  // ── Pairs ───────────────────────────────────────────────────────────────
  group('pairs close themselves', () {
    test('every opener brings its partner, caret between', () {
      expect(_type('x = |', '('), 'x = (|)');
      expect(_type('x = |', '['), 'x = [|]');
      expect(_type('x = |', '{'), 'x = {|}');
      expect(_type('x = |', '"'), 'x = "|"');
      expect(_type('x = |', "'"), "x = '|'");
      expect(_type('x = |', '`'), 'x = `|`');
    });

    test('typing the CLOSER steps over it instead of doubling it', () {
      expect(_type('call(|)', ')'), 'call()|');
      expect(_type('a[|]', ']'), 'a[]|');
      expect(_type('{|}', '}'), '{}|');
      expect(_type('"|"', '"'), '""|');
      expect(_type('`|`', '`'), '``|');
    });

    test('a pair does not close in front of a word — it would trap it', () {
      expect(_type('|value', '('), '(|value',
          reason: 'wrapping the next word is never what was meant');
      expect(_type('|value', '"'), '"|value');
      expect(_type('x = | rest', '('), 'x = (|) rest',
          reason: 'before a space it is safe');
      expect(_type('f(|)', '('), 'f((|))',
          reason: 'before a closer it is safe');
    });

    test("an apostrophe in a comment is not an unterminated string", () {
      expect(_type('// it|', "'"), "// it'|");
      expect(_type(r'x = "a\|', '"'), r'x = "a\"|',
          reason: 'an escaped quote closes nothing');
    });

    test('Rust does not pair a single quote — that is a lifetime', () {
      final rust = languageFor('rust');
      expect(_type('&|', "'", rust), "&'|");
      expect(_type('x = |', '"', rust), 'x = "|"',
          reason: 'double quotes still pair');
    });

    test('typing over a SELECTION is the wrap formatter, untouched here', () {
      final before = _v('see [foo] here');
      const wrap = WrapSelectionFormatter(
          pairs: WrapSelectionFormatter.bracketPairs, autoCloseFences: false);
      final typed = TextEditingValue(
        text: before.text.replaceRange(4, 7, '('),
        selection: const TextSelection.collapsed(offset: 5),
      );
      final wrapped = wrap.formatEditUpdate(before, typed);
      expect(wrapped.text, 'see (foo) here');
      expect(applyCodeTyping(before, wrapped, _dart), isNull,
          reason: 'pairing must not fire on top of a wrap and double it');
    });
  });

  group('backspace', () {
    test('between an empty pair takes both halves', () {
      expect(_backspace('call(|)'), 'call|');
      expect(_backspace('a[|]'), 'a|');
      expect(_backspace('{|}'), '|');
      expect(_backspace('"|"'), '|');
    });

    test('a pair with something in it loses only the character typed', () {
      expect(_backspace('call(x|)'), 'call(|)');
      expect(_backspace('(|x)'), '|x)');
    });

    test('inside the indent it goes back a LEVEL, undoing Tab', () {
      expect(_backspace('    |x'), '  |x');
      expect(_backspace('  |x'), '|x');
      // Off the grid it lands back ON the grid rather than one further off.
      expect(_backspace('   |x'), '  |x');
      // Python counts in fours.
      expect(_backspace('        |x', languageFor('python')), '    |x');
    });

    test('past the indent it is an ordinary backspace', () {
      expect(_backspace('  ab|'), '  a|');
    });
  });

  // ── Enter ───────────────────────────────────────────────────────────────
  group('Enter', () {
    test('between braces opens a line and pushes the closer below it', () {
      expect(_type('if (x) {|}', '\n'), 'if (x) {\n  |\n}');
      expect(_type('  while (a) {|}', '\n'), '  while (a) {\n    |\n  }',
          reason: "the closer returns to the OPENING line's indent");
      expect(_type('f(|)', '\n'), 'f(\n  |\n)');
      expect(_type('list = [|]', '\n'), 'list = [\n  |\n]');
    });

    test('whitespace already sitting between the pair is absorbed', () {
      expect(_type('x = {| }', '\n'), 'x = {\n  |\n}');
    });

    test('C++ counts an indent in fours', () {
      expect(_type('int main() {|}', '\n', languageFor('cpp')),
          'int main() {\n    |\n}');
    });

    test('after an opener with nothing behind it, one extra level', () {
      expect(_type('if (x) {|', '\n'), 'if (x) {\n  |');
      expect(_type('  if (x) {|', '\n'), '  if (x) {\n    |');
    });

    test("Python's colon opens a block the way a brace does", () {
      final py = languageFor('python');
      expect(_type('def f():|', '\n', py), 'def f():\n    |');
      expect(_type('    if x:|', '\n', py), '    if x:\n        |');
      expect(_type('x = 1:|', '\n', _dart), 'x = 1:\n|',
          reason: 'a colon means nothing in Dart');
    });

    test('an ordinary line keeps the indentation it already had', () {
      expect(_type('    total += 1|', '\n'), '    total += 1\n    |');
      expect(_type('  a|b', '\n'), '  a\n  |b');
    });

    test('at column zero the field\'s own newline is left alone', () {
      final before = _v('done|');
      const after = TextEditingValue(
          text: 'done\n', selection: TextSelection.collapsed(offset: 5));
      expect(applyCodeTyping(before, after, _dart), isNull,
          reason: 'nothing to add — do not rewrite the value for nothing');
    });
  });

  // ── Tab ─────────────────────────────────────────────────────────────────
  group('Tab', () {
    test('inserts spaces, to the next stop rather than blindly two', () {
      expect(_tab('|x'), '  |x');
      expect(_tab(' |x'), '  |x', reason: 'half a level lands ON the grid');
      expect(_tab('ab|'), 'ab  |');
      expect(_tab('|', lang: languageFor('python')), '    |');
    });

    test('Shift+Tab takes a level off the line', () {
      expect(_tab('    x|', outdent: true), '  x|');
      expect(_tab('  x|', outdent: true), 'x|');
      expect(_tab('\tx|', outdent: true), 'x|');
    });

    test('Shift+Tab at the margin does nothing at all', () {
      expect(handleCodeTab(_v('x|'), _dart, outdent: true), isNull);
    });

    test('a selection across lines moves EVERY line, and stays selected', () {
      expect(_tab('[a\nb\nc]'), '[  a\n  b\n  c]');
      expect(_tab('[  a\n  b]', outdent: true), '[a\nb]');
    });

    test('a blank line inside the block gains no trailing whitespace', () {
      expect(_tab('[a\n\nb]'), '[  a\n\n  b]');
    });

    test('a selection inside one line is replaced, VS Code style', () {
      expect(_tab('x = [foo]'), 'x =   |');
    });

    test('an outdent stops at the margin instead of eating the code', () {
      expect(_tab('[a\n  b]', outdent: true), '[a\nb]');
    });
  });

  // ── Highlighting ────────────────────────────────────────────────────────
  group('highlighting C++ and C#', () {
    TextSpan? spanOf(List<TextSpan> spans, String text) {
      for (final s in spans) {
        if (s.text == text) return s;
      }
      return null;
    }

    test('a C++ snippet colours the tokens that make it C++', () {
      const src = '#include <iostream>\n'
          'int main() { std::cout << nullptr; }';
      final spans = highlightCode(src, 'cpp', false);
      expect(spanOf(spans, '#include')?.style, isNotNull,
          reason: 'the directive is a keyword, not grey text');
      expect(spanOf(spans, '<iostream>')?.style, isNotNull,
          reason: 'the header reads as the string it is');
      expect(spanOf(spans, 'std')?.style, isNotNull,
          reason: 'whatever is scoped into by :: is a type');
      expect(spanOf(spans, 'nullptr')?.style, isNotNull);
    });

    test('a C# snippet colours using, var, async and an attribute', () {
      const src = '[TestMethod]\n'
          'public async Task Run() { var x = 1; }';
      final spans = highlightCode(src, 'csharp', false);
      expect(spanOf(spans, '[TestMethod]')?.style, isNotNull,
          reason: 'an attribute on its own line');
      expect(spanOf(spans, 'async')?.style, isNotNull);
      expect(spanOf(spans, 'var')?.style, isNotNull);
      expect(spanOf(spans, 'Task')?.style, isNotNull);
    });

    test('an alias highlights identically to the id it resolves to', () {
      const src = 'int main() { std::cout << 1; }';
      expect(highlightCode(src, 'c++', false).map((s) => s.text).toList(),
          highlightCode(src, 'cpp', false).map((s) => s.text).toList());
      expect(highlightCode('var x = 1;', 'c#', false).first.style,
          highlightCode('var x = 1;', 'csharp', false).first.style);
    });

    test('an array index is not an attribute, a hash in code is not a directive',
        () {
      final spans = highlightCode('  a[0] = b[1];', 'csharp', false);
      expect(spans.any((s) => s.text?.contains('[0]') == true && s.style != null),
          isFalse);
    });
  });

  // ── The wiring ──────────────────────────────────────────────────────────
  group('inside the block', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    late Directory tmp;
    late Repository repo;
    late AppState app;

    setUp(() async {
      if (!haveSqlite) return;
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_codeedit_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('T');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
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

    Future<Block> pump(WidgetTester tester,
        {String language = 'text', String source = 'x = 1'}) async {
      final b = Block(type: BlockType.code, x: 0, y: 0, w: 420, content: {
        'language': language,
        'source': source,
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: app,
            builder: (_, __) => Align(
              alignment: Alignment.topLeft,
              child:
                  SizedBox(width: 420, child: CodeBlockView(block: b, app: app)),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return b;
    }

    Future<void> edit(WidgetTester tester) async {
      final origin = tester.getTopLeft(find.byType(SelectableText));
      await tester.tapAt(origin + const Offset(3, 8));
      await tester.pumpAndSettle();
    }

    testWidgets('the label reads the language, not its id', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await pump(tester, language: 'cpp');
      expect(find.text('C++'), findsOneWidget);
      expect(find.text('cpp'), findsNothing);
    });

    testWidgets('Tab indents the source and can be undone', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = await pump(tester);
      await edit(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(b.content['source'], '  x = 1',
          reason: 'Tab indents rather than leaving the cell');
      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.controller!.selection.baseOffset, 2,
          reason: 'the caret stays after the spaces it just made');
      await tester.pump(const Duration(milliseconds: 900));
    });

    testWidgets('typing ( in the real field pairs it', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = await pump(tester, source: 'f');
      await edit(tester);

      // Park the caret at the end first — the tap put it at the character it
      // landed on, and "one character typed AT the caret" is the whole test.
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'f',
        selection: TextSelection.collapsed(offset: 1),
      ));
      await tester.pump();
      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'f(',
        selection: TextSelection.collapsed(offset: 2),
      ));
      await tester.pumpAndSettle();

      expect(b.content['source'], 'f()',
          reason: 'the formatter is installed on the field');
      await tester.pump(const Duration(milliseconds: 900));
    });

    testWidgets('pasting Python names the block Python, silently',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      const python = 'def area(r):\n    return 3.14 * r * r\n';
      final b = await pump(tester, source: '');
      await edit(tester);

      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: python,
        selection: TextSelection.collapsed(offset: python.length),
      ));
      await tester.pumpAndSettle();

      expect(b.content['language'], 'python');
      expect(b.content['languageAuto'], isTrue);
      expect(find.text('Python'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 900));
    });

    testWidgets('the picker lays out, groups, and marks what runs',
        (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final b = await pump(tester);
      await edit(tester);

      await tester.tap(find.text('Plain text'));
      await tester.pumpAndSettle();

      expect(find.text(kRunsHereGroup), findsOneWidget);
      expect(find.text('C family'), findsOneWidget);
      expect(find.text('C++'), findsOneWidget);
      expect(find.text('Run'), findsNWidgets(2),
          reason: 'SQL and JavaScript, badged where they are chosen');

      await tester.tap(find.text('C++'));
      await tester.pumpAndSettle();

      expect(b.content['language'], 'cpp');
      expect(b.content['languagePicked'], isTrue,
          reason: 'a pick turns detection off for this block, for good');
      await tester.pump(const Duration(milliseconds: 900));
    });

    testWidgets('a picked language survives the same paste', (tester) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      const python = 'def area(r):\n    return 3.14 * r * r\n';
      final b = await pump(tester, language: 'sql', source: '');
      b.content['languagePicked'] = true;
      await edit(tester);

      tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: python,
        selection: TextSelection.collapsed(offset: python.length),
      ));
      await tester.pumpAndSettle();

      expect(b.content['language'], 'sql');
      await tester.pump(const Duration(milliseconds: 900));
    });
  });
}
