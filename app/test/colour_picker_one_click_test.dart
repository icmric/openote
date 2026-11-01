// A swatch is a choice, not a proposal.
//
// The owner, on the highlighter's new picker: *"i dont like that i have to
// click the colour and then apply, id like to just click the colour and then
// have it automatically apply. There isnt a preview and its easily undone so
// in my view no need to stage the change. Same deal with the text colour,
// unless they have already expanded the "mix your own colour" menu, in which
// case it should set the colour in there but not automatically close the
// dialouge box (unless they then click the same box again while its still
// selected, in which case close and apply it)."*
//
// So: one click picks, except while the mixer is open — where a swatch is a
// starting point to adjust, and clicking the same one twice says "no, that
// one".
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/color_picker.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_pick1_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('P');
    app = AppState(repo)..notebookId = nb.id;
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

  /// What a swatch of [c] looks like in the tree: the only container painted
  /// exactly that colour at swatch size.
  Finder swatchOf(Color c) => find.byWidgetPredicate((w) =>
      w is Container &&
      w.decoration is BoxDecoration &&
      (w.decoration! as BoxDecoration).color?.toARGB32() == c.toARGB32() &&
      w.constraints?.maxWidth == 24);

  /// A colour from the standard grid, which nothing else in the dialog uses.
  final grid = HSVColor.fromAHSV(1, 140, .85, .95).toColor();
  final grid2 = HSVColor.fromAHSV(1, 240, .85, .95).toColor();

  /// Opens the picker and records what it returns, so a test can read it.
  Future<List<String?>> open(WidgetTester t) async {
    final out = <String?>[];
    var opened = false;
    await t.pumpWidget(MaterialApp(
      theme: onoteTheme(Brightness.light),
      home: Builder(builder: (context) {
        if (!opened) {
          opened = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            out.add(await showOnoteColorPicker(context, app,
                initial: 'C63838', allowAuto: true));
          });
        }
        return const Scaffold(body: SizedBox.expand());
      }),
    ));
    await t.pumpAndSettle();
    return out;
  }

  String hexOf(Color c) {
    String two(num v) =>
        (v * 255).round().toRadixString(16).padLeft(2, '0').toUpperCase();
    return '${two(c.r)}${two(c.g)}${two(c.b)}';
  }

  testWidgets('one click on a swatch applies it and closes', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final out = await open(t);
    expect(swatchOf(grid), findsOneWidget, reason: 'precondition');

    await t.tap(swatchOf(grid));
    await t.pumpAndSettle();

    expect(out, [hexOf(grid)], reason: 'no Apply needed');
    expect(find.text('Mix your own colour'), findsNothing, reason: 'closed');
    expect(app.customColors, contains(hexOf(grid)),
        reason: 'and it is a recent colour now');
    app.cancelPendingSave(); // remembering it armed the workspace debounce
  });

  testWidgets('with the mixer open, a swatch only loads it', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final out = await open(t);
    await t.tap(find.text('Mix your own colour'));
    await t.pumpAndSettle();
    expect(find.text('Hex  #'), findsOneWidget, reason: 'the mixer is open');

    await t.tap(swatchOf(grid));
    await t.pumpAndSettle();

    expect(out, isEmpty, reason: 'nothing returned; the dialog is still up');
    expect(find.text('Hex  #'), findsOneWidget);
    expect(
        t
            .widget<TextField>(find.ancestor(
                of: find.text(hexOf(grid)), matching: find.byType(TextField)))
            .controller!
            .text,
        hexOf(grid),
        reason: 'loaded into the mixer, ready to adjust');
  });

  testWidgets('and clicking the same one again applies it', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final out = await open(t);
    await t.tap(find.text('Mix your own colour'));
    await t.pumpAndSettle();

    await t.tap(swatchOf(grid));
    await t.pumpAndSettle();
    expect(out, isEmpty, reason: 'precondition: staged');

    await t.tap(swatchOf(grid));
    await t.pumpAndSettle();
    expect(out, [hexOf(grid)], reason: 'the second click is the answer');
    app.cancelPendingSave();
  });

  testWidgets('a DIFFERENT swatch while the mixer is open still only loads',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final out = await open(t);
    await t.tap(find.text('Mix your own colour'));
    await t.pumpAndSettle();

    await t.tap(swatchOf(grid));
    await t.pumpAndSettle();
    await t.tap(swatchOf(grid2));
    await t.pumpAndSettle();

    expect(out, isEmpty, reason: 'changing your mind is not deciding');
  });

  testWidgets('NEGATIVE CONTROL: Apply still works, and Cancel still returns'
      ' nothing', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    var out = await open(t);
    await t.tap(find.text('Apply'));
    await t.pumpAndSettle();
    expect(out, ['C63838'], reason: 'the colour it opened on');
    app.cancelPendingSave();

    out = await open(t);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(out, [null]);
  });

  testWidgets('NEGATIVE CONTROL: Automatic still answers on the first click',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final out = await open(t);
    await t.tap(find.text('Mix your own colour'));
    await t.pumpAndSettle();
    await t.tap(find.text('Automatic'));
    await t.pumpAndSettle();
    expect(out, ['auto'],
        reason: 'there is nothing to mix from "whatever contrasts"');
  });
}
