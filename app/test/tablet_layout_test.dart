// A tablet is the desktop layout with finger-sized targets; held upright, the
// navigator folds to a rail that opens as a drawer. A phone held sideways is
// still a phone. See the "Tablet" board on the design canvas.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/l10n/l10n.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/app_shell.dart';
import 'package:openote/ui/device_class.dart';
import 'package:openote/ui/phone_shell.dart';
import 'package:openote/ui/sidebar.dart';
import 'package:openote/ui/ui_scale_host.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  group('which kind of device', () {
    test('a touch device is judged by its shorter side', () {
      expect(classifyDevice(const Size(390, 844), touch: true), DeviceClass.phone);
      expect(classifyDevice(const Size(844, 390), touch: true), DeviceClass.phone,
          reason: 'a phone held sideways is still a phone');
      expect(classifyDevice(const Size(800, 1280), touch: true), DeviceClass.tablet);
      expect(classifyDevice(const Size(1280, 800), touch: true), DeviceClass.tablet);
    });

    test('a computer is judged by its width', () {
      expect(classifyDevice(const Size(1280, 800), touch: false), DeviceClass.desktop);
      expect(classifyDevice(const Size(1000, 500), touch: false), DeviceClass.desktop,
          reason: 'a short, wide window is still a computer');
      expect(classifyDevice(const Size(500, 900), touch: false), DeviceClass.phone);
    });
  });

  late Directory tmp;
  late Repository repo;
  late AppState app;

  Future<void> shell(WidgetTester t, Size size) async {
    AppState.syncLogEnabled = false;
    await t.runAsync(() async {
      tmp = Directory.systemTemp.createTempSync('onote_tablet_');
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Tablet');
      app = AppState(repo)
        ..notebookId = nb.id
        ..spellCheckEnabled = false;
      app.reloadNodes();
      await app.addSection();
      app.reloadNodes();
      await app.selectPage(
          app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
    });
    app.markOnboardingSeen();
    t.view.physicalSize = size;
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
      builder: (context, child) => UiScaleHost(app: app, child: child!),
      home: AppShell(app: app),
    ));
    await t.pump(const Duration(milliseconds: 900));
    await t.pumpAndSettle();
  }

  /// A widget test on a touch device.
  void touchTest(String name, Future<void> Function(WidgetTester t) body) {
    testWidgets(name, (t) async {
      debugTouchPlatform = true;
      try {
        await body(t);
      } finally {
        debugTouchPlatform = null;
      }
    });
  }

  touchTest('a tablet on its side: the desktop layout, drawn larger',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(t, const Size(1280, 800));
    expect(find.byType(Sidebar), findsOneWidget);
    expect(find.byType(PhoneTopBar), findsNothing);
    expect(find.byType(TabletRail), findsNothing);
    expect(app.effectiveUiScale, closeTo(kTabletBoost, .01),
        reason: 'so a 32 px target comes to about 43');
    app.cancelPendingSave();
  });

  touchTest('a tablet upright: a rail, and the menu opens the navigator',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(t, const Size(800, 1280));
    expect(find.byType(Sidebar), findsNothing);
    expect(find.byType(TabletRail), findsOneWidget);
    expect(find.byType(PhoneTopBar), findsNothing,
        reason: 'it keeps the desktop toolbar, not the phone bar');
    await t.tap(find.descendant(
        of: find.byType(TabletRail), matching: find.byIcon(Icons.menu)));
    await t.pumpAndSettle();
    expect(find.byType(PhoneNavigator), findsOneWidget);
    app.cancelPendingSave();
  });

  touchTest('the rail can open the navigator on Recent', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(t, const Size(800, 1280));
    await t.tap(find.descendant(
        of: find.byType(TabletRail), matching: find.byIcon(Icons.history)));
    await t.pumpAndSettle();
    expect(find.byType(PhoneNavigator), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(PhoneNavigator), matching: find.text('SECTIONS')),
        findsNothing,
        reason: 'it opened on Recent, not on the sections');
    app.cancelPendingSave();
  });

  touchTest('a phone held sideways is still a phone, with the tabs as icons',
      (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await shell(t, const Size(844, 390));
    expect(find.byType(PhoneTopBar), findsOneWidget);
    expect(find.byType(Sidebar), findsNothing);
    expect(find.text('Write'), findsNothing, reason: 'no row of words: no room');
    expect(find.byIcon(Icons.add_circle_outline), findsOneWidget,
        reason: 'but Insert is still one tap away');
    app.cancelPendingSave();
  });
}
