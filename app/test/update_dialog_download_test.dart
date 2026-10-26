// Where the update button goes when Openote cannot install it itself, and
// what it says.
//
// The owner, on a Fedora VM: *"i cannot update entirely within openote on
// there … the update button was there but it just linked me to github where I
// had to download and install it again."* That is the designed fallback —
// Windows ships an installer that can replace the app in place, and nothing
// else does (see `_UpdateDialogState._canAutoUpdate`) — but two things about
// it were wrong.
//
// **Where it went.** The GitHub release page is seven assets and a wall of
// notes, and a Linux reader has to know whether they want the `.deb`, the
// `.rpm` or the `.tar.gz`. openote.org detects the system and puts the right
// one first, which is the whole reason that page exists.
//
// **What it said.** *"On this system the update installs from a downloaded
// package — the button opens the download page."* explains the mechanism and
// buries the instruction, so a browser opened and people read it as the
// button having failed. The owner: *"I want to make it more clear they do
// need to install the file again … Keep it simple and rely on as little text
// as possible."*
//
// And all of it in the reader's own language, which none of this dialog was.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/core/platform_open.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/update_dialog.dart';
import 'package:openote/update/app_update.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  // **No `windowsSetupUrl`, which is what puts every platform down the
  // download path.** `_canAutoUpdate` is `Platform.isWindows && the asset
  // exists`, so a release without an installer behaves on Windows exactly as
  // every release behaves on Linux and macOS — and these run the same
  // everywhere rather than only on CI's Linux box.
  const info = UpdateInfo(
    version: '9.9.9',
    pageUrl: 'https://github.com/icmric/openote/releases/tag/v9.9.9',
    notes: 'Something new.',
  );

  late List<String> opened;
  late Directory tmp;
  late Repository repo;
  late AppState app;

  setUp(() async {
    opened = [];
    if (haveSqlite) {
      AppState.syncLogEnabled = false;
      tmp = Directory.systemTemp.createTempSync('onote_updatedlg_');
      repo = await Repository.openAt(tmp);
      app = AppState(repo)..updateAvailable = info;
    }
    PlatformOpen.debugHandOff = (t) async {
      opened.add(t);
      return true;
    };
  });

  tearDown(() {
    PlatformOpen.debugHandOff = null;
    if (!haveSqlite) return;
    AppState.syncLogEnabled = true;
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pump(WidgetTester t, {Locale locale = const Locale('en')}) async {
    await t.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: kOnoteLocalizations,
      supportedLocales: kOnoteLocales,
      theme: onoteTheme(Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showUpdateDialog(context, app),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets('the button opens openote.org, not the release page', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t);
    final l = await _en();

    expect(find.text(l.updateDownload), findsOneWidget);
    await t.tap(find.text(l.updateDownload));
    await t.pumpAndSettle();

    expect(opened, ['https://openote.org'],
        reason: 'the site picks the right file for the reader’s system; the '
            'release page makes them choose between seven assets');
    expect(opened.single, isNot(contains('github.com')));
  });

  testWidgets('and it says, in one line, that they install it', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t);
    final l = await _en();
    expect(find.text(l.updateInstallYourself), findsOneWidget);
    // Short enough that it is read rather than skimmed past — the old line
    // was 95 characters of mechanism.
    expect(l.updateInstallYourself.length, lessThan(60),
        reason: 'as little text as possible');
  });

  testWidgets('the button carries the leaves-the-app icon', (t) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t);
    // Half the message, without a sentence on the button.
    expect(
        find.descendant(
            of: find.byType(FilledButton),
            matching: find.byIcon(Icons.open_in_new)),
        findsOneWidget);
  });

  testWidgets('every word of it is translated', (t) async {
    // The dialog was entirely hard-coded English until now, in an app that
    // ships seven languages. German stands in for the other six: the keys are
    // one set, so a missing translation is a missing translation everywhere.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t, locale: const Locale('de'));
    expect(find.text('Herunterladen'), findsOneWidget);
    expect(find.text('Jetzt nicht'), findsOneWidget);
    expect(find.text('Du musst sie selbst herunterladen und installieren.'),
        findsOneWidget);
    expect(find.textContaining('Openote 9.9.9 ist verfügbar'), findsOneWidget);
  });

  testWidgets('NEGATIVE CONTROL: the release notes are NOT translated',
      (t) async {
    // Deliberate — they are the maintainer's prose, written once, not UI.
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await pump(t, locale: const Locale('de'));
    expect(find.textContaining('Something new.'), findsOneWidget);
  });
}

/// The English strings, for asserting against what is on screen.
Future<L> _en() => L.delegate.load(const Locale('en'));
