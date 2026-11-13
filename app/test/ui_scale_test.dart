// The interface size: the presets, the limit a small window puts on them, that
// the zoom really changes what the layout sees and where a click lands, that
// changing it never throws the open page away, and that it is remembered.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/state/app_state.dart';
import 'package:openote/state/ui_scale.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/ui_scale_host.dart';

import 'support/sqlite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());
  setUp(() => AppState.syncLogEnabled = false);
  tearDown(() => AppState.syncLogEnabled = true);

  group('the size a window can hold', () {
    test('normal and smaller always apply', () {
      expect(effectiveUiScale(1.0, const Size(500, 400)), 1.0);
      expect(effectiveUiScale(0.75, const Size(500, 400)), 0.75);
      expect(effectiveUiScale(0.9, const Size(1920, 1080)), 0.9);
    });

    test('a big screen allows every preset', () {
      for (final s in kUiScales) {
        expect(effectiveUiScale(s, const Size(1920, 1080)), s, reason: '$s');
      }
    });

    test('a small window holds back the larger ones, never below normal', () {
      // 1366 x 768: height is the limit, 768 / 520 = 1.47.
      final laptop = effectiveUiScale(2.0, const Size(1366, 768));
      expect(laptop, closeTo(768 / kMinLogicalHeight, 1e-9));
      expect(effectiveUiScale(1.25, const Size(1366, 768)), 1.25);
      // A window already smaller than the minimum is drawn at normal, not at
      // less than normal: shrinking it further would not help anyone.
      expect(effectiveUiScale(2.0, const Size(600, 400)), 1.0);
    });

    test('the layout never falls below what Settings needs', () {
      for (final w in [800.0, 1024.0, 1366.0, 1920.0, 2560.0]) {
        for (final h in [600.0, 768.0, 1080.0, 1440.0]) {
          for (final s in kUiScales) {
            final e = effectiveUiScale(s, Size(w, h));
            if (e <= 1.0) continue;
            expect(w / e, greaterThanOrEqualTo(kMinLogicalWidth - 1e-6));
            expect(h / e, greaterThanOrEqualTo(kMinLogicalHeight - 1e-6));
          }
        }
      }
    });

    test('percent labels', () {
      expect(uiScalePercent(0.75), '75%');
      expect(uiScalePercent(1.25), '125%');
      expect(uiScalePercent(2.0), '200%');
    });
  });

  group('the zoom host', () {
    late Directory dir;
    late Repository repo;
    late AppState app;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('onote_scale_');
      repo = await Repository.openAt(dir);
      app = AppState(repo);
    });
    tearDown(() {
      app.dispose();
      repo.dispose();
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    /// The settings write is debounced; let it run out so no timer is left.
    Future<void> done(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    }

    Future<void> mount(WidgetTester t, Widget child, Size window) async {
      t.view.physicalSize = window;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        builder: (context, c) =>
            UiScaleHost(app: app, child: c ?? const SizedBox.shrink()),
        home: Scaffold(body: child),
      ));
    }

    testWidgets('the layout is given 1/scale of the window and draws it bigger',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      Size? seen;
      Size? mq;
      await mount(
          t,
          LayoutBuilder(builder: (context, c) {
            seen = c.biggest;
            mq = MediaQuery.sizeOf(context);
            return const SizedBox.expand();
          }),
          const Size(1600, 1000));
      expect(seen, const Size(1600, 1000), reason: '100% changes nothing');

      app.setUiScale(1.25);
      await t.pump();
      expect(seen, const Size(1280, 800));
      expect(mq, const Size(1280, 800),
          reason: 'anything asking the window size is told the layout size');
      expect(app.effectiveUiScale, 1.25);
      await done(t);
    });

    testWidgets('a click lands on the button drawn under the pointer', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      var taps = 0;
      await mount(
          t,
          Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(100),
              child: SizedBox(
                  width: 100,
                  height: 40,
                  child: ElevatedButton(
                      onPressed: () => taps++, child: const Text('go'))),
            ),
          ),
          const Size(1600, 1000));
      app.setUiScale(1.5);
      await t.pump();
      // At 150% the button sits at 150..300 across and 150..210 down.
      await t.tapAt(const Offset(225, 180));
      expect(taps, 1);
      await t.tapAt(const Offset(120, 120)); // where it WOULD be at 100%
      expect(taps, 1, reason: 'and not where it used to be');
      await done(t);
    });

    testWidgets('changing the size keeps what is open', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await mount(t, const _Counter(), const Size(1600, 1000));
      await t.tap(find.text('0'));
      await t.pump();
      expect(find.text('1'), findsOneWidget);

      for (final s in [1.5, 0.75, 1.0, 2.0]) {
        app.setUiScale(s);
        await t.pump();
        expect(find.text('1'), findsOneWidget,
            reason: 'the page was not rebuilt from nothing at $s');
      }
      await done(t);
    });

    testWidgets('a window too small for the choice shows less, and says so',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await mount(t, const SizedBox.expand(), const Size(1366, 768));
      app.setUiScale(2.0);
      await t.pump();
      expect(app.uiScale, 2.0, reason: 'what was chosen is kept');
      expect(app.effectiveUiScale, closeTo(768 / kMinLogicalHeight, 1e-9));
      expect(app.effectiveUiScale, lessThan(app.uiScale));
      await done(t);
    });
  });

  test('the choice is remembered, and only a known size is', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final dir = Directory.systemTemp.createTempSync('onote_scale_keep_');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    var repo = await Repository.openAt(dir);
    var app = AppState(repo);
    await app.init();
    expect(app.uiScale, 1.0, reason: 'a new install is at 100%');
    app.setUiScale(1.75);
    app.setUiScale(1.33); // not a preset: refused
    expect(app.uiScale, 1.75);
    await app.flushSave();
    app.cancelPendingSave();
    await repo.flushWorkspace();
    app.dispose();
    repo.dispose();

    repo = await Repository.openAt(dir);
    app = AppState(repo);
    await app.init();
    expect(app.uiScale, 1.75);
    expect(app.uiScaleNotifier.value, 1.75, reason: 'and drawn at once');
    app.dispose();
    repo.dispose();
  });
}

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;
  @override
  Widget build(BuildContext context) => Center(
      child: TextButton(onPressed: () => setState(() => n++), child: Text('$n')));
}
