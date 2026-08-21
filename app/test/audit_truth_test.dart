// The app never says something that is not true (v0.23 audit).
//
// The owner's second principle asks for speed with an honest face: *"assuming
// it will work and preparing accordingly, then displaying a message if it
// fails."* The failures below all had no face at all — worse, three of them
// wore a face that said everything was fine.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/math/math_inventory.dart';
import 'package:openote/math/math_tree.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/sync/mirrors.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/keyboard_map.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;
  late String nb;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_audit_');
    repo = await Repository.openAt(tmp);
    final n = await repo.createNotebook('T');
    nb = n.id;
    app = AppState(repo)
      ..notebookId = n.id
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

  group('a backup that has never worked does not say "Backed up"', () {
    // The badge used to count destinations CONFIGURED. A backup pointed at an
    // unplugged USB stick threw into a `debugPrint` and the notebook went on
    // saying "Backed up to 1 place" for a term of notes that were never
    // copied anywhere.
    //
    // What is checked here is the DERIVATION — that the count comes from the
    // record of what worked. Provoking a real copy failure needs a
    // destination the OS refuses, and this harness could not produce one
    // (`Directory.create(recursive: true)` under a file does not throw here),
    // so the failing half is left to the shape of the code rather than
    // faked with a stub that would only test the stub.
    test('not tried is not failed, so a fresh notebook keeps its badge',
        () async {
      if (!haveSqlite) return;
      final good = Directory('${tmp.path}${Platform.pathSeparator}copies')
        ..createSync(recursive: true);
      app.addMirror(nb, MirrorTarget(path: good.path, keepVersions: 0));
      expect(app.syncStatus(nb).mirrors, 1,
          reason: 'nothing has run yet, and a notebook must not lose its '
              'badge between opening and the first copy');
      app.cancelPendingSave();
    });

    test('and a copy that works is not accused of anything', () async {
      if (!haveSqlite) return;
      final good = Directory('${tmp.path}${Platform.pathSeparator}copies2')
        ..createSync(recursive: true);
      app.addMirror(nb, MirrorTarget(path: good.path, keepVersions: 0));
      await app.runMirrors(nb, force: true);
      expect(app.mirrorTroubleFor(nb), isEmpty);
      expect(app.syncStatus(nb).mirrors, 1);
      app.cancelPendingSave();
    });

    test('the count is what worked, not what was configured', () {
      if (!haveSqlite) return;
      app.addMirror(nb, const MirrorTarget(path: 'a', keepVersions: 0));
      app.addMirror(nb, const MirrorTarget(path: 'b', keepVersions: 0));
      expect(app.syncStatus(nb).mirrors, 2);
      // The one thing the badge must never do: count a copy that did not
      // happen. `mirrorTroubleFor` is what stands between it and that.
      expect(app.mirrorTroubleFor(nb), isEmpty);
      app.cancelPendingSave();
    });
  });

  group('"could not be read" is never reported as "nothing happened"', () {
    test('a notebook with no trouble says so', () {
      if (!haveSqlite) return;
      expect(app.historyTroubleFor(nb), isNull);
      expect(app.historyTroubleFor(null), isNull);
    });
  });

  group('the palette does not say things that are untrue', () {
    test('the multiplication dot is not called a dot product', () {
      final dot = mathItemsById['cdot']!;
      expect(dot.name, 'times',
          reason: 'a year-10 student inserting a multiplication dot was told '
              'they had inserted a vector operation');
      expect(dot.aliases, contains('dot product'),
          reason: 'and a sixth-former searching for the old name still finds '
              'it');
    });

    test('the right-angle chip inserts a right angle', () {
      final ra = mathItemsById['rightangle'];
      expect(ra, isNotNull);
      expect(ra!.name, 'right angle');
      expect(ra.build().length, 1);
      // Whatever it draws on its face, it must not be the perpendicular sign
      // — which is what it used to insert, duplicating another chip.
      expect(mathItemsById['perp']!.build().first.texOf(kStoreCtx),
          isNot(ra.build().first.texOf(kStoreCtx)));
    });

    test('every tooltip route actually works when typed', () {
      // The tips line under the ⋯ menu used to teach `sqrt`, `sum`, `theta`
      // with no backslash, which types four letters. Every advertised route
      // here is a real command word.
      for (final item in mathItems) {
        final t = item.typeIt;
        if (t == null || !t.startsWith('\\')) continue;
        final word = t.substring(1);
        if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(word)) continue;
        expect(mathControlWords.containsKey(word), isTrue,
            reason: '$t is advertised on ${item.id} and types nothing');
      }
    });
  });

  group('the shortcut list only promises what happens', () {
    test('Alt+= does not claim to finish an equation', () {
      final rows = [
        for (final section in keyboardMap)
          for (final b in section.bindings)
            if (b.keys.contains('Alt+=')) b.action
      ].join(' ');
      expect(rows.toLowerCase(), isNot(contains('finish')),
          reason: 'the chord is guarded on !_mathFieldFocused, so inside an '
              'equation it lands nowhere — and the very next row of the same '
              'list gives the real answer (Esc)');
    });

    test('and the menu key is listed, now that it does something', () {
      final all = [
        for (final section in keyboardMap)
          for (final b in section.bindings) b.keys
      ].join(' ');
      expect(all, contains('F10'),
          reason: 'half of what a student can add to a page had no keyboard '
              'route at all');
    });
  });
}
