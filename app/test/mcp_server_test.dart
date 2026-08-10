// The MCP server, over real HTTP against a real repository — External API
// Spec (docs/specs/14). The two claims that matter most:
//
//   * THE FILE FORMAT IS THE API (§2): a board block — a type this test
//     file never mentions by schema — round-trips through append_blocks and
//     read_page because both speak Block.toJson/fromJson.
//   * The security posture (§4): no token → 401, foreign Origin → 403,
//     before any tool code runs.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/api/mcp_server.dart';
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';

import 'support/sqlite.dart';

void main() {
  var haveSqlite = false;
  setUpAll(() => haveSqlite = initSqliteForTests());

  late Repository repo;
  late Directory tmp;
  late AppState app;
  late McpServer server;
  late int port;
  var nextId = 0;

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_mcp_');
    repo = await Repository.openAt(tmp);
    final nb = await repo.createNotebook('Study');
    app = AppState(repo)
      ..notebookId = nb.id
      ..spellCheckEnabled = false;
    app.reloadNodes();
    await app.selectPage(
        app.nodes.firstWhere((n) => n.kind == NodeKind.page).id);
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

  Future<(int, Map<String, dynamic>?)> post(Object body,
      {String? token = 'tok-test', String? origin}) async {
    final client = HttpClient();
    try {
      final req =
          await client.postUrl(Uri.parse('http://127.0.0.1:$port/mcp'));
      req.headers.contentType = ContentType.json;
      if (token != null) req.headers.set('authorization', 'Bearer $token');
      if (origin != null) req.headers.set('origin', origin);
      req.write(jsonEncode(body));
      final res = await req.close();
      final text = await utf8.decodeStream(res);
      return (
        res.statusCode,
        text.isEmpty ? null : jsonDecode(text) as Map<String, dynamic>
      );
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> rpc(String method,
      [Map<String, Object?> params = const {}]) async {
    final (status, body) = await post({
      'jsonrpc': '2.0',
      'id': ++nextId,
      'method': method,
      'params': params,
    });
    expect(status, 200, reason: '$method should answer 200');
    return body!;
  }

  Future<dynamic> call(String tool, [Map<String, Object?> args = const {}]) async {
    final r = await rpc('tools/call', {'name': tool, 'arguments': args});
    final result = r['result'] as Map<String, dynamic>;
    final text = (result['content'] as List).first['text'] as String;
    if (result['isError'] == true) return McpToolFailure(text);
    try {
      return jsonDecode(text);
    } catch (_) {
      return text; // markdown and other plain-text results
    }
  }

  test('initialize negotiates, unknown revisions fall back', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final ok = await rpc('initialize', {'protocolVersion': '2025-06-18'});
    expect((ok['result'] as Map)['protocolVersion'], '2025-06-18');
    final odd = await rpc('initialize', {'protocolVersion': '2099-01-01'});
    expect((odd['result'] as Map)['protocolVersion'], '2025-03-26');
  });

  test('NO TOKEN → 401, FOREIGN ORIGIN → 403, before any tool runs', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final (noAuth, _) = await post({
      'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'
    }, token: null);
    expect(noAuth, 401);
    final (badTok, _) = await post({
      'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'
    }, token: 'wrong');
    expect(badTok, 401);
    final (badOrigin, _) = await post({
      'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'
    }, origin: 'https://evil.example');
    expect(badOrigin, 403, reason: 'DNS-rebinding defence, spec §4.3');
  });

  test('tools/list names the whole v1 surface', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final r = await rpc('tools/list');
    final names = [
      for (final t in ((r['result'] as Map)['tools'] as List)) t['name']
    ];
    expect(
        names,
        containsAll([
          'list_notebooks', 'list_pages', 'read_page', 'search',
          'create_page', 'append_blocks', 'append_markdown',
          'create_flashcards',
        ]));
  });

  test('create → append markdown → read back, json and markdown', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final made = await call('create_page', {'title': 'Week 3'});
    final pageId = made['pageId'] as String;

    await call('append_markdown',
        {'pageId': pageId, 'markdown': '# Notes\n- osmosis is diffusion'});

    final asJson = await call('read_page', {'pageId': pageId});
    final blocks = asJson['blocks'] as List;
    expect(blocks, hasLength(1));
    expect(blocks.first['type'], 'text');
    expect(blocks.first['content']['text'], contains('osmosis'));

    final asMd =
        await call('read_page', {'pageId': pageId, 'format': 'markdown'});
    expect(asMd, contains('# Week 3'));
    expect(asMd, contains('osmosis'));
  });

  test('THE FORMAT IS THE API: a board round-trips untaught', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final made = await call('create_page', {'title': 'Sprint'});
    final pageId = made['pageId'] as String;
    final added = await call('append_blocks', {
      'pageId': pageId,
      'blocks': [
        {
          'type': 'board',
          'w': 700,
          'content': {
            'columns': [
              {'title': 'To do', 'cards': ['write the api']},
              {'title': 'Done', 'cards': <String>[]},
            ]
          }
        }
      ],
    });
    expect(added['added'], 1);
    final back = await call('read_page', {'pageId': pageId});
    final b = (back['blocks'] as List).single;
    expect(b['type'], 'board',
        reason: 'no board-specific code exists in the API layer');
    expect(b['content']['columns'][0]['cards'], ['write the api']);
  });

  test('create_flashcards writes the page\'s own card form', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final made = await call('create_page', {'title': 'Bio deck'});
    final pageId = made['pageId'] as String;
    final r = await call('create_flashcards', {
      'pageId': pageId,
      'cards': [
        {'front': 'What is osmosis', 'back': 'Diffusion of water'},
        {'front': 'Define ATP', 'back': 'The cell\'s energy currency'},
      ],
    });
    expect(r['added'], 2);
    final back = await call('read_page', {'pageId': pageId});
    final text =
        (back['blocks'] as List).single['content']['text'] as String;
    expect(text, contains('?[What is osmosis](Diffusion of water)'),
        reason: 'the study system reads exactly this form off the page');
  });

  test('search finds what the API wrote', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final made = await call('create_page', {'title': 'Chem'});
    await call('append_markdown', {
      'pageId': made['pageId'],
      'markdown': 'the mole is avogadro in a trench coat'
    });
    final hits = await call('search', {'query': 'avogadro'});
    expect(hits, isNotEmpty);
    expect(hits.first['pageId'], made['pageId']);
    expect(hits.first['snippet'], contains('avogadro'));
  });

  test('appending to the OPEN page goes through the live editor', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final before = app.blocks.length;
    await call('append_markdown',
        {'pageId': app.pageId!, 'markdown': 'dropped in live'});
    expect(app.blocks.length, before + 1,
        reason: 'the open page must change ON SCREEN, undoably — not '
            'behind the editor\'s back');
    app.cancelPendingSave();
  });

  test('failures are readable results, not transport errors', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final missing = await call('read_page', {'pageId': 'no-such'});
    expect(missing, isA<McpToolFailure>());
    expect((missing as McpToolFailure).message, contains('list_pages'),
        reason: 'the error tells the model what to do next');
    final unknown = await call('definitely_not_a_tool');
    expect(unknown, isA<McpToolFailure>());
  });
}

class McpToolFailure {
  McpToolFailure(this.message);
  final String message;
}
