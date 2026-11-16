// Ctrl+Z and the Undo button are the same action, wherever the cursor is.
//
// Right after a page or group is made, the cursor is in its name (a text field
// with nothing of its own to undo). Ctrl+Z there used to go to that field and do
// nothing, while the button, which calls the app directly, worked.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;

  Future<void> shell(WidgetTester t) async {
    AppState.syncLogEnabled = false;
    await t.runAsync(() async {
      tmp = Directory.systemTemp.createTempSync('onote_undo_key_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('K');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      await app.selectPage(
          app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
    });
    app.markOnboardingSeen();
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    addTearDown(() {
      AppState.syncLogEnabled = true;
      app.cancelPendingSave();
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      home: AppShell(app: app),
    ));
    await t.pump(const Duration(milliseconds: 900));
    await t.pumpAndSettle();
  }

  Future<void> ctrl(WidgetTester t, LogicalKeyboardKey k,
      {bool shift = false}) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyDownEvent(k);
    await t.sendKeyUpEvent(k);
    if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    // The tree step finishes after a page switch, in real time.
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 900));
    await t.pumpAndSettle();
  }

  int pages() => app.nodes.where((n) => n.kind == NodeKind.page).length;
  int groups() =>
      app.nodes.where((n) => n.kind == NodeKind.sectionGroup).length;

  testWidgets('a new page: Ctrl+Z from its title takes it back, Ctrl+Y returns it',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(t);
    final before = pages();
    await t.runAsync(app.addPage);
    await t.pump(const Duration(milliseconds: 900));
    await t.pumpAndSettle();
    expect(pages(), before + 1);
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null ||
        FocusManager.instance.primaryFocus?.context?.widget is EditableText,
        isTrue, reason: 'the cursor is in the new page\'s title');

    await ctrl(t, LogicalKeyboardKey.keyZ);
    expect(pages(), before, reason: 'the same as pressing the button');
    await ctrl(t, LogicalKeyboardKey.keyY);
    expect(pages(), before + 1);
  });

  testWidgets('a new group: Ctrl+Z from its name field takes it back', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(t);
    final before = groups();
    app.addSectionGroup();
    await t.pumpAndSettle();
    expect(groups(), before + 1);
    await ctrl(t, LogicalKeyboardKey.keyZ);
    expect(groups(), before);
  });
}
