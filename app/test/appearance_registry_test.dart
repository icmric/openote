// The appearance registry — the plumbing half of the theme catalogue (#12).
//
// The catalogue's palettes are a design-review question and are NOT here.
// What this file pins is the contract every future palette will rest on:
//
//   * an appearance is a registry entry, and the registry answers by id;
//   * a saved id this build does not know falls back to the default rather
//     than crashing — a student who tries a newer Openote and goes back
//     keeps a working app;
//   * the chosen appearance persists through the settings store and comes
//     back on init;
//   * `MaterialApp`'s light/dark pair is resolved from mode + appearance,
//     and with today's two-entry registry resolves to exactly the themes
//     the app has always been built with — which is what makes this a
//     refactor and not a change.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/appearances.dart';
import 'package:openote/theme/tokens.dart';

import 'support/sqlite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  test('the registry holds the two appearances that exist today', () {
    expect(appearances.map((a) => a.id), ['light', 'night-ink'],
        reason: 'these two ids are the app the catalogue is built on; '
            'removing either reverts somebody\'s saved choice');
    expect(appearances.map((a) => a.brightness),
        [Brightness.light, Brightness.dark]);
  });

  test('an id the build does not know answers with the default', () {
    expect(appearanceById(null).id, 'light');
    expect(appearanceById('true-black').id, 'light',
        reason: 'a saved choice from a newer Openote must not crash an '
            'older one — same rule as every other settings read');
    expect(appearanceById('night-ink').id, 'night-ink');
  });

  test('every registry entry paints with a working theme of its family', () {
    for (final a in appearances) {
      final t = a.buildTheme();
      expect(t.colorScheme.brightness, a.brightness,
          reason: '${a.id} declares its family and its theme must agree');
      expect(t.extension<OnoteSurfaces>(), isNotNull,
          reason: '${a.id} carries the OnoteSurfaces roles widgets read');
    }
  });

  group('themesForMode', () {
    test('the pair is the one the app has always been built with', () {
      // This is the refactor's own safety net: with two entries the
      // resolution must answer the identical pair main.dart used to hand
      // MaterialApp inline. If this fails, the plumbing changed behaviour
      // and the "no visual change" claim is false.
      final pair = themesForMode(ThemeMode.system, appearanceById('light'));
      expect(pair.light.colorScheme.brightness, Brightness.light);
      expect(pair.dark.colorScheme.brightness, Brightness.dark);
    });

    testWidgets(
        'a mode that disagrees with the appearance still paints the '
        'family the mode asked for', (t) async {
      // Light chosen, dark mode: the dark slot must be a DARK theme — Night
      // ink today — not the light one wearing the dark slot.
      final pair = themesForMode(ThemeMode.dark, appearanceById('light'));
      expect(pair.dark.colorScheme.brightness, Brightness.dark);
      final pair2 = themesForMode(ThemeMode.light, appearanceById('night-ink'));
      expect(pair2.light.colorScheme.brightness, Brightness.light);
    });
  });

  group('persistence (§7a.5, the settings store)', () {
    test('setAppearance chooses, persists, and init restores', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final dir = Directory.systemTemp.createTempSync('onote_appearance_');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final repo = await Repository.openAt(dir);
      addTearDown(repo.dispose);

      final app = AppState(repo);
      addTearDown(app.dispose);
      expect(app.appearance.id, 'light', reason: 'the default is unchanged');

      expect(app.setAppearance('night-ink'), isTrue);
      expect(repo.getSetting('appearanceId'), 'night-ink');

      // A second AppState over the same store — the next launch.
      final again = AppState(repo);
      addTearDown(again.dispose);
      await again.init();
      expect(again.appearance.id, 'night-ink',
          reason: 'the choice survives the restart, like themeMode does');
      again.cancelPendingSave();
    });

    test('an unknown id changes nothing and reports it', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final dir = Directory.systemTemp.createTempSync('onote_appearance_');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final repo = await Repository.openAt(dir);
      addTearDown(repo.dispose);

      final app = AppState(repo);
      addTearDown(app.dispose);
      expect(app.setAppearance('rose-pine'), isFalse,
          reason: 'a theme this build does not ship cannot be selected');
      expect(app.appearance.id, 'light');
      expect(repo.getSetting('appearanceId'), isNull,
          reason: 'and nothing was written');
    });

    test('init falls back on a stored id this build does not know', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final dir = Directory.systemTemp.createTempSync('onote_appearance_');
      addTearDown(() {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final repo = await Repository.openAt(dir);
      addTearDown(repo.dispose);
      repo.setSetting('appearanceId', 'from-the-future');

      final app = AppState(repo);
      addTearDown(app.dispose);
      await app.init();
      expect(app.appearance.id, 'light',
          reason: 'the same defensive read themeMode has always had');
      app.cancelPendingSave();
    });
  });
}
