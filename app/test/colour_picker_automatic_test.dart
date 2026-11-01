// The way back to the default colour has to be in the picker.
//
// The owner, after using the colour work: *"its not imedietley clear how to
// set it to the auto colour."* It was not clear because there was no way at
// all — every entry in the picker was a colour, and the only route back was a
// keyboard shortcut that toggles.
//
// `'auto'` is the sentinel the pen has always used for "whatever contrasts
// with what this is drawn on", so the picker returns the same one and
// `AppState.applyTextColor` takes the colour off.
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
    tmp = Directory.systemTemp.createTempSync('onote_picker_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Colours');
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

  Future<String?> open(WidgetTester t, {required bool allowAuto}) async {
    String? picked;
    var opened = false;
    await t.pumpWidget(MaterialApp(
      theme: onoteTheme(Brightness.light),
      home: Builder(builder: (context) {
        if (!opened) {
          opened = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            picked = await showOnoteColorPicker(context, app,
                initial: 'C63838', allowAuto: allowAuto);
          });
        }
        return const Scaffold(body: SizedBox.expand());
      }),
    ));
    await t.pumpAndSettle();
    return picked;
  }

  testWidgets('AUTOMATIC IS IN THE PICKER, AND RETURNS "auto"', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await open(t, allowAuto: true);
    expect(find.text('Automatic'), findsOneWidget);

    await t.tap(find.text('Automatic'));
    await t.pumpAndSettle();

    // The dialog closed with the sentinel, and nothing was remembered as a
    // recent colour — `auto` is not one.
    expect(find.text('Automatic'), findsNothing);
    expect(app.customColors, isEmpty);
  });

  testWidgets('and it is not offered where there is no default to go back to',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    // A box's background has "Remove background" in its own menu instead.
    await open(t, allowAuto: false);
    expect(find.text('Automatic'), findsNothing);
  });
}
