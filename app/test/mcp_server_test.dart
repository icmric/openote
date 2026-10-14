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
          // v1.1: edit, insert, the tree, and self-description.
          'describe_block_types', 'create_pages', 'insert_blocks',
          'update_block', 'delete_blocks', 'move_blocks', 'rename_page',
          'move_page', 'delete_page',
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

  // ── v1.1: native Markdown, layout, validation, edit, tree ──────────────

  Future<String> newPage(String title) async =>
      (await call('create_page', {'title': title}))['pageId'] as String;

  test('append_markdown makes code blocks and real tables, stacked clear',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final pageId = await newPage('Native');
    final code = List.generate(30, (i) => 'x$i = $i').join('\n');
    final r = await call('append_markdown', {
      'pageId': pageId,
      'markdown': '## Setup\nSome prose.\n\n```py\n$code\n```\n\n'
          '| a | b |\n|---|---|\n| 1 | 2 |\n',
    });
    final placed = (r['blocks'] as List).cast<Map<String, dynamic>>();
    expect([for (final b in placed) b['type']], ['text', 'code', 'text']);
    expect(r.containsKey('warnings'), isFalse, reason: '${r['warnings']}');
    // Each block starts below the one before it ends.
    for (var i = 1; i < placed.length; i++) {
      final prev = placed[i - 1];
      expect(placed[i]['y'],
          greaterThanOrEqualTo((prev['y'] as num) + (prev['h'] as num)));
    }
    expect(placed[1]['h'], greaterThanOrEqualTo(30 * 19 + 60),
        reason: 'a 30-line code block is not 60px tall');

    final page = await call('read_page', {'pageId': pageId});
    final blocks = (page['blocks'] as List).cast<Map<String, dynamic>>();
    expect(blocks[1]['content']['language'], 'python');
    expect(blocks[1]['content']['source'], code);
    expect(blocks[2]['content']['text'], contains('onote://atom/'));
    expect(blocks[2]['content']['atoms'], isNotEmpty);
  });

  test('a second append lands below a tall code block, not on it', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final pageId = await newPage('Stack');
    final first = await call('append_blocks', {
      'pageId': pageId,
      'blocks': [
        {
          'type': 'code',
          'w': 600,
          'content': {
            'source': List.generate(40, (i) => 'line $i').join('\n'),
            'language': 'python'
          }
        }
      ],
    });
    final second = await call('append_markdown',
        {'pageId': pageId, 'markdown': 'after the code'});
    final a = (first['blocks'] as List).single;
    final b = (second['blocks'] as List).single;
    expect(b['y'], greaterThanOrEqualTo(a['y'] + 40 * 19 + 60));
    expect(second.containsKey('warnings'), isFalse);
  });

  test('a misspelt content key is refused with the right key named',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final pageId = await newPage('Keys');
    final bad = await call('append_blocks', {
      'pageId': pageId,
      'blocks': [
        {
          'type': 'code',
          'content': {'code': 'print(1)'}
        }
      ],
    });
    expect(bad, isA<McpToolFailure>());
    expect((bad as McpToolFailure).message, contains('content.source'));
    final page = await call('read_page', {'pageId': pageId});
    expect(page['blocks'], isEmpty, reason: 'nothing half-written');

    final warned = await call('append_blocks', {
      'pageId': pageId,
      'blocks': [
        {
          'type': 'code',
          'content': {'source': 'x', 'language': 'klingon', 'extra': 1}
        }
      ],
    });
    final w = (warned['warnings'] as List).join('\n');
    expect(w, contains('klingon'));
    expect(w, contains('extra'));
  });

  test('a written block always gets a fresh id (Data Model §2 rule 3)',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final from = await newPage('From');
    final to = await newPage('To');
    final made = await call('append_markdown',
        {'pageId': from, 'markdown': 'copy me'});
    final original = (made['blocks'] as List).single['id'];
    // A client copying a block out of read_page into another page.
    final block = ((await call('read_page', {'pageId': from}))['blocks']
            as List)
        .single;
    final copied = await call('append_blocks', {
      'pageId': to,
      'blocks': [block],
    });
    expect((copied['blocks'] as List).single['id'], isNot(original),
        reason: 'ids are unique across the notebook, not just the page');
  });

  test('literal markdown stays one text block, exactly as written', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final pageId = await newPage('Literal');
    const md = '```py\nx = 1\n```\n\n| a |\n|---|\n| 1 |';
    final r = await call('append_markdown',
        {'pageId': pageId, 'markdown': md, 'literal': true});
    expect((r['blocks'] as List).single['type'], 'text');
    final page = await call('read_page', {'pageId': pageId});
    expect((page['blocks'] as List).single['content']['text'], md);
  });

  test('append_blocks names the block types an agent can write', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final r = await rpc('tools/list');
    final append = ((r['result'] as Map)['tools'] as List)
        .firstWhere((t) => t['name'] == 'append_blocks');
    final d = append['description'] as String;
    for (final t in ['text (', 'code (', 'table (', 'math (', 'flashcard (']) {
      expect(d, contains(t), reason: 'v1.0.2 plan §20, fix 1');
    }
  });

  test('a table block is written as the app\'s inline table', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final pageId = await newPage('Tbl');
    final r = await call('append_blocks', {
      'pageId': pageId,
      'blocks': [
        {
          'type': 'table',
          'content': {
            'cells': [
              ['h1', 'h2'],
              ['a', 'b']
            ]
          }
        }
      ],
    });
    expect((r['blocks'] as List).single['type'], 'text');
  });

  test('describe_block_types names the keys, languages and layout', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final d = await call('describe_block_types');
    final code = (d['blockTypes'] as List)
        .firstWhere((t) => t['type'] == 'code') as Map;
    expect([for (final k in code['content'] as List) k['key']],
        contains('source'));
    expect([for (final l in d['codeLanguages'] as List) l['id']],
        containsAll(['python', 'js', 'sql']));
    expect(d['layout']['pageLeftMargin'], AppState.pageLeftMargin);
    expect(d['layout']['contentTop'], AppState.contentTop);
  });

  test('update, move, delete — and one Ctrl+Z each on the open page',
      () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final pageId = app.pageId!;
    final added = await call('append_blocks', {
      'pageId': pageId,
      'blocks': [
        {
          'type': 'code',
          'content': {'source': 'a = 1'}
        }
      ],
    });
    final id = (added['blocks'] as List).single['id'] as String;
    Block live() => app.blocks.firstWhere((b) => b.id == id);

    await call('update_block', {
      'pageId': pageId,
      'blockId': id,
      'content': {'source': 'a = 2', 'language': 'python'},
    });
    expect(live().content['source'], 'a = 2');
    expect(live().content['language'], 'python');
    app.undo();
    expect(live().content['source'], 'a = 1', reason: 'undoable');

    final refused = await call('update_block', {
      'pageId': pageId,
      'blockId': id,
      'content': {'source': null},
    });
    expect(refused, isA<McpToolFailure>(),
        reason: 'removing a required key would leave an empty box');
    expect(live().content['source'], 'a = 1');

    final y0 = live().y;
    await call('move_blocks', {
      'pageId': pageId,
      'blockIds': [id],
      'dy': 48,
    });
    expect(live().y, y0 + 48);

    await call('delete_blocks', {
      'pageId': pageId,
      'blockIds': [id],
    });
    expect(app.blocks.any((b) => b.id == id), isFalse);
    app.undo();
    expect(app.blocks.any((b) => b.id == id), isTrue);
    app.cancelPendingSave();
  });

  test('edits on a page that is not open go to storage', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final pageId = await newPage('Closed');
    final r = await call('append_markdown',
        {'pageId': pageId, 'markdown': 'one'});
    final id = (r['blocks'] as List).single['id'];
    await call('update_block', {
      'pageId': pageId,
      'blockId': id,
      'content': {'text': 'two'},
      'w': 300,
    });
    final b = ((await call('read_page', {'pageId': pageId}))['blocks'] as List)
        .single;
    expect(b['content']['text'], 'two');
    expect(b['w'], 300);
    final missing = await call('delete_blocks', {
      'pageId': pageId,
      'blockIds': ['nope'],
    });
    expect(missing, isA<McpToolFailure>());
  });

  test('insert_blocks makes room: what was below moves down', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final pageId = await newPage('Insert');
    final r = await call('append_markdown', {
      'pageId': pageId,
      'markdown': 'first\n\n```js\na\n```\n\nlast',
    });
    final ids = [for (final b in r['blocks'] as List) b['id'] as String];
    final lastBefore = (r['blocks'] as List).last['y'] as num;
    final ins = await call('insert_blocks', {
      'pageId': pageId,
      'afterBlockId': ids.first,
      'markdown': List.generate(10, (i) => 'inserted $i').join('\n'),
    });
    expect(ins['shifted'], 2);
    final placed = (ins['blocks'] as List).single;
    expect(ins.containsKey('warnings'), isFalse, reason: '${ins['warnings']}');
    final layout = await call(
        'read_page', {'pageId': pageId, 'format': 'layout'});
    final byId = {for (final b in layout['blocks'] as List) b['id']: b};
    expect(byId[ids.last]['y'], greaterThan(lastBefore));
    expect(byId[ids[1]]['y'],
        greaterThanOrEqualTo(placed['y'] + placed['h']));
    expect(layout['overlaps'], isEmpty);
  });

  test('read_page layout reports overlapping boxes', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final pageId = await newPage('Overlap');
    final r = await call('append_blocks', {
      'pageId': pageId,
      'blocks': [
        {
          'type': 'text',
          'x': 44,
          'y': 200,
          'w': 300,
          'content': {'text': 'a'}
        },
        {
          'type': 'text',
          'x': 60,
          'y': 210,
          'w': 300,
          'content': {'text': 'b'}
        },
      ],
    });
    expect((r['warnings'] as List).single, contains('overlaps'));
    final layout =
        await call('read_page', {'pageId': pageId, 'format': 'layout'});
    expect(layout['overlaps'], hasLength(1));
  });

  test('create_page fills itself; create_pages is all or nothing', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final made = await call('create_page', {
      'title': 'Filled',
      'markdown': '# Hi\n\n```sql\nselect 1\n```',
    });
    expect(made['added'], 2);
    final page = await call('read_page', {'pageId': made['pageId']});
    expect((page['blocks'] as List).map((b) => b['type']), ['text', 'code']);

    final before = app.nodes.length;
    final bad = await call('create_pages', {
      'pages': [
        {'title': 'ok', 'markdown': 'fine'},
        {
          'title': 'broken',
          'blocks': [
            {
              'type': 'math',
              'content': {'tex': 'x'}
            }
          ]
        },
      ],
    });
    expect(bad, isA<McpToolFailure>());
    expect((bad as McpToolFailure).message, contains('pages[1]'));
    expect(app.nodes.length, before, reason: 'no half-made batch');

    final good = await call('create_pages', {
      'pages': [
        {'title': 'P1', 'markdown': 'one'},
        {'title': 'P2', 'level': 1},
        {'title': 'P3'},
      ],
    });
    final ids = [for (final p in good['pages'] as List) p['pageId']];
    final order = [
      for (final n in app.nodes)
        if (ids.contains(n.id)) n.title
    ];
    expect(order, ['P1', 'P2', 'P3'], reason: 'batch keeps its order');
    expect(app.nodes.firstWhere((n) => n.id == ids[1]).level, 1);
  });

  test('list_pages filters and pages its results', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    for (var i = 0; i < 5; i++) {
      await call('create_page', {'title': 'Lecture $i'});
    }
    final sections = await call('list_pages', {'kind': 'section'});
    final sectionId = (sections['items'] as List).first['id'];
    expect((sections['items'] as List).every((n) => n['kind'] == 'section'),
        isTrue);

    final first = await call('list_pages',
        {'sectionId': sectionId, 'query': 'lecture', 'limit': 2});
    expect(first['total'], 5);
    expect(first['items'], hasLength(2));
    expect(first['nextOffset'], 2);
    final rest = await call('list_pages', {
      'sectionId': sectionId,
      'query': 'lecture',
      'offset': first['nextOffset'],
      'limit': 10,
    });
    expect(rest['items'], hasLength(3));
    expect(rest.containsKey('nextOffset'), isFalse);
  });

  test('rename, move and delete a page', () async {
    if (!haveSqlite) return markTestSkipped('sqlite unavailable');
    final a = await newPage('A');
    final b = await newPage('B');
    await call('rename_page', {'pageId': a, 'title': 'Alpha'});
    expect(app.nodes.firstWhere((n) => n.id == a).title, 'Alpha');

    // A goes after B.
    await call('move_page', {'pageId': a, 'afterPageId': b});
    final order = [
      for (final n in app.nodes)
        if (n.id == a || n.id == b) n.id
    ];
    expect(order, [b, a]);

    final gone = await call('delete_page', {'pageId': b});
    expect(gone['deleted'], b);
    expect(app.nodes.any((n) => n.id == b), isFalse,
        reason: 'in the recycle bin, not the tree');
    final again = await call('read_page', {'pageId': b});
    expect(again, isA<McpToolFailure>());
  });
}

class McpToolFailure {
  McpToolFailure(this.message);
  final String message;
}
