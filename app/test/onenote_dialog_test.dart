// The door into OneNote: two ways in, and neither hidden behind the other.
//
// The owner's requirement, which is what most of these pin: "i know many users
// wouldnt be comfortable with signing into their microsoft account either to
// transfer it, so i want to make it clear there is another option."
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/core/secret_store.dart';
import 'package:openote/model/models.dart';
import 'package:openote/onenote/graph_auth.dart';
import 'package:openote/onenote/graph_client.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/ui/onenote_cloud_dialog.dart';

import 'support/app.dart';
import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  setUp(() {
    SecretStore.debugBackend = {};
  });

  Future<AppState> newApp(WidgetTester tester) async {
    late AppState app;
    late Repository repo;
    final tmp = Directory.systemTemp.createTempSync('onote_onenote_dlg_');
    addTearDown(() {
      repo.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.runAsync(() async {
      repo = await Repository.openAt(tmp);
      final nb = await repo.createNotebook('Welcome');
      app = AppState(repo)..notebookId = nb.id;
      app.reloadNodes();
      await app.selectPage(
          app.nodes.where((n) => n.kind == NodeKind.page).first.id);
    });
    return app;
  }

  tearDown(() {
    SecretStore.debugBackend = null;
    GraphAuth.debugOpenBrowser = null;
    GraphAuth.debugTokenEndpoint = null;
    GraphClient.debugFetch = null;
  });

  Future<void> open(WidgetTester tester) async {
    final app = await newApp(tester);
    await tester.pumpWidget(testApp(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showOneNoteCloudDialog(context, app),
            child: const Text('open'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('both ways in are offered on the first screen', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await open(tester);

    // Neither is behind a fold, a menu, or the word "advanced". Somebody who
    // will not sign in must be able to see, without hunting, that they do not
    // have to.
    expect(find.text('Sign in to Microsoft'), findsOneWidget);
    expect(find.text('Use a file you exported'), findsOneWidget);
  });

  testWidgets('each route says what it costs, not how it works',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    await open(tester);

    // The sign-in route admits it cannot carry handwriting; the file route
    // admits it needs Windows. A choice where each option genuinely wins at
    // something can only be made honestly if both caveats are on screen.
    expect(
        find.textContaining('Handwriting cannot come over this way'),
        findsOneWidget);
    expect(find.textContaining('OneNote on Windows'), findsOneWidget);
    // And the reassurance that matters most to a hesitant person is on the
    // card they are deciding about.
    expect(find.textContaining('cannot change them'), findsOneWidget);
  });

  testWidgets('signing in leads to a list of notebooks and nothing else',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    SecretStore.debugBackend!['onenote.graph.refresh'] = 'GOOD';
    GraphAuth.debugTokenEndpoint =
        (body) async => (200, {'access_token': 'AT', 'expires_in': 3600});
    GraphClient.debugFetch = (url) async => (
          200,
          '{"value":[{"id":"nb1","displayName":"Physics"},'
              '{"id":"nb2","displayName":"History"}]}',
          <String, String>{}
        );

    await open(tester);
    await tester.pumpAndSettle();

    expect(find.text('Physics'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    // The second screen replaces the first rather than stacking under it —
    // the whole of "I dont want it cluttered".
    expect(find.text('Use a file you exported'), findsNothing);
    expect(find.text('Sign in to Microsoft'), findsNothing);
  });

  testWidgets('a wrong account is fixed by changing it, not by reading it',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    SecretStore.debugBackend!['onenote.graph.refresh'] = 'GOOD';
    GraphAuth.debugTokenEndpoint =
        (body) async => (200, {'access_token': 'AT', 'expires_in': 3600});
    GraphClient.debugFetch = (url) async =>
        (200, '{"value":[{"id":"nb1","displayName":"Physics"}]}',
            <String, String>{});

    await open(tester);
    await tester.pumpAndSettle();

    // Openote never learns who is signed in — it asks for no identity scope
    // at all — so this button is what stands in for showing an email address.
    expect(find.text('Use a different account'), findsOneWidget);
  });

  testWidgets('an account with no notebooks says so plainly', (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    SecretStore.debugBackend!['onenote.graph.refresh'] = 'GOOD';
    GraphAuth.debugTokenEndpoint =
        (body) async => (200, {'access_token': 'AT', 'expires_in': 3600});
    GraphClient.debugFetch =
        (url) async => (200, '{"value":[]}', <String, String>{});

    await open(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('No notebooks were found'), findsOneWidget);
  });

  testWidgets('a failure is a sentence, with the technical half underneath',
      (tester) async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    SecretStore.debugBackend!['onenote.graph.refresh'] = 'GOOD';
    GraphAuth.debugTokenEndpoint =
        (body) async => (200, {'access_token': 'AT', 'expires_in': 3600});
    GraphClient.debugFetch = (url) async => (403, '', <String, String>{});

    await open(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('would not allow Openote'), findsOneWidget);
    // The status code is present but subordinate — never the headline.
    expect(find.textContaining('403'), findsOneWidget);
  });
}
