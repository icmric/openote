// What the AI dialog can honestly say.
//
// v1.0.2 #13: *"'Connected' in the AI dialog means 'I wrote the config
// file.'"* It re-read each client's config, found the `openote` entry, and
// called that connected — and it could not have known more, because the
// transport is stateless JSON-RPC and there is no connection to observe.
//
// What CAN be known: whether the server bound, and when a request last
// arrived. So the buttons say "set up", and the status says when an AI
// helper last reached Openote.
//
// None of this goes through `setMcpEnabled`, which rewrites the `openote`
// entry in every AI client config on the machine running the test.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openote/api/mcp_server.dart';
import 'package:openote/l10n/l10n.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/theme/onote_theme.dart';
import 'package:openote/ui/mcp_dialog.dart';

import 'support/sqlite.dart';

void main() {
  group('the words for "when"', () {
    final now = DateTime(2026, 10, 14, 15, 0);
    String at(Duration ago) => mcpLastUsedLabel(now.subtract(ago), now);

    test('nothing yet says so, rather than implying a failure', () {
      expect(mcpLastUsedLabel(null, now),
          'No AI helper has used it since Openote opened.');
    });

    test('and then coarse, because the question is "is it working"', () {
      expect(at(const Duration(seconds: 20)),
          'Last used by an AI helper just now.');
      expect(at(const Duration(minutes: 1)),
          'Last used by an AI helper 1 minute ago.');
      expect(at(const Duration(minutes: 7)),
          'Last used by an AI helper 7 minutes ago.');
      expect(at(const Duration(hours: 1)),
          'Last used by an AI helper 1 hour ago.');
      expect(at(const Duration(hours: 5)),
          'Last used by an AI helper 5 hours ago.');
      expect(at(const Duration(days: 2)),
          'Last used by an AI helper more than a day ago.');
    });
  });

  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Directory tmp;
  late Repository repo;
  late AppState app;
  late McpServer server;
  late int port;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_mcpstatus_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('T');
    app = AppState(repo)..notebookId = nb.id;
    app.reloadNodes();
    server = McpServer(app);
    port = await server.start(token: 'tok-test', preferredPort: 0);
  });

  tearDown(() async {
    AppState.syncLogEnabled = true;
    if (!haveSqlite) return;
    await server.stop();
    app.cancelPendingSave();
    repo.dispose();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<int> send(String token) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse('http://127.0.0.1:$port/mcp'));
      req.headers.contentType = ContentType.json;
      req.headers.set('authorization', 'Bearer $token');
      req.write(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'ping'}));
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode;
    } finally {
      client.close();
    }
  }

  /// One real request. **Real** is the point: a file with any `testWidgets`
  /// in it runs under the widgets test binding, which swaps `HttpClient` for
  /// a mock that answers every request 400 so widget tests cannot reach the
  /// network. A plain [HttpOverrides] restores the real one for this call.
  Future<int> ping({String token = 'tok-test'}) =>
      HttpOverrides.runWithHttpOverrides(() => send(token), _RealHttp());

  group('the server keeps the one piece of evidence', () {
    test('nothing has reached it yet', () {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      expect(server.lastRequest.value, isNull);
    });

    test('A WRONG TOKEN IS NOT AN AI HELPER USING YOUR NOTES', () async {
      // A port scan, or a web page probing loopback, must not show up as
      // "last used just now".
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      expect(await ping(token: 'guessed'), HttpStatus.unauthorized);
      expect(server.lastRequest.value, isNull);
    });

    test('a request with the right token is stamped', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final before = DateTime.now();
      expect(await ping(), HttpStatus.ok);
      final at = server.lastRequest.value;
      expect(at, isNotNull);
      expect(at!.isBefore(before), isFalse);
    });
  });

  group('the dialog', () {
    Future<void> openDialog(WidgetTester t) async {
      app.debugUseMcpServer(server);
      t.view.physicalSize = const Size(1200, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        localizationsDelegates: kOnoteLocalizations,
        supportedLocales: kOnoteLocales,
        theme: onoteTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showMcpDialog(context, app),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    /// Close it, which also stops its "N minutes ago" ticker — the framework
    /// checks for pending timers before any tear-down runs.
    Future<void> closeDialog(WidgetTester t) async {
      await t.tap(find.text('Close'));
      await t.pumpAndSettle();
      app.cancelPendingSave();
    }

    testWidgets('no button claims a connection it cannot see', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await openDialog(t);
      expect(find.textContaining('— connected'), findsNothing,
          reason: 'a config entry is "set up", never "connected"');
      // Which ones read "set up" depends on this machine's own configs, which
      // the dialog reads; the vocabulary does not.
      for (final name in ['Claude app', 'ChatGPT app', 'Claude Code',
          'Gemini CLI']) {
        final either = find.text('Set up $name').evaluate().length +
            find.text('$name — set up').evaluate().length;
        expect(either, 1, reason: name);
      }
      await closeDialog(t);
    });

    testWidgets('ready, and honest that nothing has used it yet', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await openDialog(t);
      expect(
          find.text('Ready. No AI helper has used it since Openote opened.'),
          findsOneWidget);
      // The thing that is otherwise unexplainable from inside the app: a
      // client looks for its servers once, at start-up, and never retries.
      expect(find.textContaining('If yours was already open, restart it'),
          findsOneWidget);
      await closeDialog(t);
    });

    testWidgets('and says so the moment something does', (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await openDialog(t);
      server.lastRequest.value = DateTime.now();
      await t.pump();
      expect(find.text('Ready. Last used by an AI helper just now.'),
          findsOneWidget);
      expect(find.textContaining('restart it'), findsNothing,
          reason: 'the restart hint is only for while nothing has called');
      await closeDialog(t);
    });

    testWidgets('the port is under Advanced, where the jargon lives',
        (t) async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      await openDialog(t);
      final line = 'Listening on port $port, on this computer only.';
      expect(find.text(line), findsNothing, reason: 'folded away at first');
      await t.tap(find.text('Other AI tools (advanced)'));
      await t.pumpAndSettle();
      expect(find.text(line), findsOneWidget);
      await closeDialog(t);
    });
  });
}

/// The default overrides — which create the real client.
class _RealHttp extends HttpOverrides {}
