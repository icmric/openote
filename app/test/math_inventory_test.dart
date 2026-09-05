// The inventory ⊆ renderer invariant, as a test rather than a promise
// (plan: v0.18 §3 principle 3, §10).
//
// Every row of the one data table in `math_inventory.dart` is inserted into a
// fresh editor and drawn through the REAL renderer, three ways: as stored, as
// the student sees it mid-edit (caret and empty boxes included), and as the
// button face. If any of them falls back to source, this fails — which is the
// only thing standing between a student and a palette button that hands them
// backslashes.
//
// It is generated from the table, so adding a symbol adds its test. A symbol
// that cannot be drawn cannot be shipped without this going red.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/math/math_editor.dart';
import 'package:openote/math/math_inventory.dart';
import 'package:openote/math/math_tree.dart';
import 'package:openote/math/math_view.dart';
import 'package:openote/ui/math_bar.dart';

void main() {
  Future<bool> drawn(WidgetTester tester, String tex) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 600,
            child: OnoteMath(tex,
                textStyle:
                    const TextStyle(fontSize: 20, color: Colors.black)),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return find.byType(MathSourceFallback).evaluate().isEmpty;
  }

  group('every palette entry renders', () {
    for (final item in mathItems) {
      testWidgets('${item.cat.name}: ${item.id} (${item.name})',
          (tester) async {
        final e = MathEditor.empty();
        e.insertItem(item);

        final stored = e.latex;
        // `words` is the one entry that legitimately stores nothing until it
        // is typed into — an empty `\text{}` should not go to disk. Everything
        // else that stores nothing is a button that does nothing.
        if (item.id != 'words') {
          expect(stored.trim(), isNotEmpty,
              reason: '${item.id} inserts nothing at all');
        }
        expect(await drawn(tester, stored), isTrue,
            reason: '${item.id} stores LaTeX the renderer cannot draw: '
                '$stored');

        // What the student is looking at while the caret is still in it.
        final editing = e.renderTex(const MathTexCtx());
        expect(await drawn(tester, editing), isTrue,
            reason: '${item.id} cannot be drawn mid-edit: $editing');

        // And the button face itself.
        final preview = item.preview;
        if (preview != null) {
          expect(await drawn(tester, preview), isTrue,
              reason: '${item.id} has a button face that cannot be drawn: '
                  '$preview');
        }
      });
    }
  });

  group('the table keeps its own promises', () {
    test('every entry can be found by a plain-words search', () {
      for (final item in mathItems) {
        final hits = searchMathItems(item.name);
        expect(hits.map((i) => i.id), contains(item.id),
            reason: '"${item.name}" does not find ${item.id} — a symbol '
                'nobody can search for may as well not be there');
      }
    });

    test('every entry shows something on its button', () {
      for (final item in mathItems) {
        expect(item.label != null || item.preview != null, isTrue,
            reason: '${item.id} would render as a blank button');
      }
    });

    test('every symbol is reachable by BROWSING, not just by search', () {
      // Adding a symbol used to put it behind no door at all — findable only
      // by knowing to search for the thing you are trying to find. Measured
      // after one batch of additions: 44 of 230 items were unreachable this
      // way. The doors sweep up their categories now, so this is the property
      // that keeps a new row from quietly disappearing.
      final reachable = <String>{...kMathQuickShapes};
      for (final d in kMathDoors) {
        for (final i in mathDoorItems(d)) {
          reachable.add(i.id);
        }
      }
      final orphans = [
        for (final i in mathItems)
          if (!reachable.contains(i.id)) i.id
      ];
      expect(orphans, isEmpty,
          reason: 'behind no door: ${orphans.join(", ")}');
    });

    test('the Greek alphabet is the WHOLE alphabet', () {
      // Asked for the Greek alphabet, "some of it" is a wrong answer. TeX
      // names only eleven capitals — the other thirteen are drawn as Latin
      // capitals, which is what they ARE — and a student hunting for capital
      // sigma has no way to know which eleven are special.
      const names = [
        'alpha', 'beta', 'gamma', 'delta', 'epsilon', 'zeta', 'eta', 'theta',
        'iota', 'kappa', 'lambda', 'mu', 'nu', 'xi', 'omicron', 'pi', 'rho',
        'sigma', 'tau', 'upsilon', 'phi', 'chi', 'psi', 'omega',
      ];
      final greek = mathItemsIn(MathCat.greek).map((i) => i.name).toSet();
      for (final n in names) {
        expect(greek, contains('capital $n'), reason: 'no capital $n');
      }
      // Lower case: `omicron` has no distinct glyph and is deliberately absent.
      for (final n in names.where((n) => n != 'omicron')) {
        expect(greek, contains(n), reason: 'no lower-case $n');
      }
    });

    test('ids are unique', () {
      final seen = <String>{};
      for (final item in mathItems) {
        expect(seen.add(item.id), isTrue, reason: 'duplicate id ${item.id}');
      }
    });

    test('every type-it-yourself tooltip actually works', () {
      // The tooltip is a teaching surface (§5.2). A shortcut that is advertised
      // and does nothing teaches the student the app is lying to them.
      for (final item in mathItems) {
        final t = item.typeIt;
        if (t == null) continue;
        if (RegExp(r'^[A-Za-z]+$').hasMatch(t)) {
          final e = MathEditor.empty();
          for (final ch in t.split('')) {
            e.insertChar(ch);
          }
          e.insertChar(' ');
          // `words` is the one entry that legitimately stores nothing until it
          // is typed into, so it is checked on what it DRAWS instead.
          final produced =
              item.id == 'words' ? e.renderTex(const MathTexCtx()) : e.latex;
          expect(produced.trim(), isNotEmpty,
              reason: '${item.id} advertises "$t" but typing it builds nothing');
          expect(produced, isNot(t),
              reason: '${item.id} advertises "$t" but it stays as letters');
        }
      }
    });

    test('the operator runs fire on their last character', () {
      for (final (run, item) in mathOperatorRuns) {
        final e = MathEditor.empty();
        for (final ch in run.split('')) {
          e.insertChar(ch);
        }
        expect(e.latex, isNot(contains(run[0])),
            reason: '"$run" should have become ${item.id}, got ${e.latex}');
      }
    });

    test('the whole table can be re-opened after being stored', () {
      // Insert → store → re-open. This is the loop a student walks every time
      // they close a page and come back, and a break in it means an equation
      // that can be written but never edited again.
      for (final item in mathItems) {
        final e = MathEditor.empty();
        e.insertItem(item);
        final reopened = MathEditor.open(e.latex);
        expect(reopened, isNotNull,
            reason: '${item.id} stores ${e.latex}, which will not re-open '
                'in the visual editor');
      }
    });
  });
}
