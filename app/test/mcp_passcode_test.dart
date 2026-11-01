// AI helpers and passcodes: anything a passcode covers is closed to them.
//
// v1.0.2 bug 15. No MCP tool asked about passcodes at all, so an AI helper set
// up on this computer could list, read, search, edit and delete a locked page
// — and the write tools added in v1.0.2 turned "read it" into "change it". The
// owner: *"they should just not be able to access locked pages"* — and no tool
// takes a passcode, so there is nothing for an agent to guess at.
//
// **Even while it is unlocked in the app.** An unlock is for the person at the
// keyboard; an agent running beside them for the rest of the session is not
// who it was opened for.
//
// Over real HTTP against a real repository, like mcp_server_test.dart, because
// the promise is about the door, not about a function somewhere behind it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/api/mcp_server.dart';
import 'package:openote/canvas/portal_view.dart' show PortalRef;
import 'package:openote/model/models.dart';
import 'package:openote/state/app_state.dart';
import 'package:openote/state/page_protection.dart';
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
  late String nb;
  late TreeNode biology, lectures, private, diary;
  var nextId = 0;

  Block text(String words, {double y = 120}) => Block(
      type: BlockType.text, x: 40, y: y, w: 300, content: {'text': words});

  TreeNode page(String notebook, TreeNode section, String title,
          {required String position, int level = 0}) =>
      app.importNode(
          notebook,
          TreeNode(
              kind: NodeKind.page,
              parentId: section.id,
              title: title,
              position: position,
              level: level));

  setUp(() async {
    if (!haveSqlite) return;
    AppState.syncLogEnabled = false;
    tmp = Directory.systemTemp.createTempSync('onote_mcp_lock_');
    repo = await Repository.openAt(tmp);
    nb = (await repo.createNotebook('Study')).id;
    app = AppState(repo)
      ..notebookId = nb
      ..spellCheckEnabled = false;
    app.reloadNodes();
    biology = app.importNode(
        nb, TreeNode(kind: NodeKind.section, title: 'Biology', position: 'b0'));
    lectures = page(nb, biology, 'Lectures', position: 'b1');
    private = app.importNode(
        nb, TreeNode(kind: NodeKind.section, title: 'Private', position: 'c0'));
    diary = page(nb, private, 'Diary', position: 'c1');
    app.importPage(nb, lectures.id, [text('mitochondria make energy')],
        PageProps());
    app.importPage(nb, diary.id, [text('the thing worth locking')],
        PageProps());
    app.reloadNodes();
    app.reloadProtection();
    app.protectNode(private.id, '2468', UnlockPolicy.session);
    await app.selectPage(lectures.id);
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
      {String? origin}) async {
    final client = HttpClient();
    try {
      final req =
          await client.postUrl(Uri.parse('http://127.0.0.1:$port/mcp'));
      req.headers.contentType = ContentType.json;
      req.headers.set('authorization', 'Bearer tok-test');
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

  Future<dynamic> call(String tool, [Map<String, Object?> args = const {}]) async {
    final (status, body) = await post({
      'jsonrpc': '2.0',
      'id': ++nextId,
      'method': 'tools/call',
      'params': {'name': tool, 'arguments': args},
    });
    expect(status, 200, reason: tool);
    final result = body!['result'] as Map<String, dynamic>;
    final text = (result['content'] as List).first['text'] as String;
    if (result['isError'] == true) return _Refused(text);
    try {
      return jsonDecode(text);
    } catch (_) {
      return text;
    }
  }

  List<String> idsIn(dynamic listing) =>
      [for (final i in listing['items'] as List) i['id'] as String];

  String pageJson(String notebook, String pageId) => jsonEncode(
      [for (final b in app.readPageOf(notebook, pageId).blocks) b.toJson()]);

  group('what an AI helper can see', () {
    test('a section with a passcode is not listed, nor anything in it',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final all = await call('list_pages');
      expect(idsIn(all), containsAll([biology.id, lectures.id]),
          reason: 'NEGATIVE CONTROL: the rest of the notebook is listed');
      expect(idsIn(all), isNot(contains(private.id)));
      expect(idsIn(all), isNot(contains(diary.id)));
      // Told why, so the model does not tell the owner the section is gone.
      expect(all['withheld'], contains('passcode'));

      final sections = await call('list_pages', {'kind': 'section'});
      expect(idsIn(sections), isNot(contains(private.id)));
      expect(await call('list_pages', {'sectionId': private.id}),
          isA<_Refused>());
    });

    test('a title search cannot be used to find out what is behind one',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The filter runs before the query, and the note says the same thing
      // whatever was asked — so a query that would have matched the locked
      // page and one that matches nothing get identical answers.
      final probe = await call('list_pages', {'query': 'diary'});
      final miss = await call('list_pages', {'query': 'zzz-nothing-here'});
      expect(probe['items'], isEmpty);
      expect(probe['total'], 0);
      expect(jsonEncode(probe), jsonEncode(miss));
    });

    test('nothing behind a passcode is read or searched, EVEN WHILE UNLOCKED '
        'in the app', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      expect(app.unlockNode(diary.id, '2468'), isTrue);
      expect(app.isLocked(diary.id), isFalse, reason: 'open in the app');

      for (final format in ['json', 'markdown', 'layout']) {
        final r = await call('read_page', {'pageId': diary.id, 'format': format});
        expect(r, isA<_Refused>(), reason: format);
        expect((r as _Refused).message, contains('passcode'));
        expect(r.message, isNot(contains('worth locking')));
      }
      expect(idsIn(await call('list_pages')), isNot(contains(diary.id)));
      expect(await call('search', {'query': 'worth locking'}), isEmpty);

      // NEGATIVE CONTROL: search does find what it is allowed to …
      final control = await call('search', {'query': 'mitochondria'});
      expect([for (final h in control) h['pageId']], [lectures.id]);
      // … and would find the diary but for its passcode.
      expect(app.unprotectNode(private.id, '2468'), isTrue);
      final unguarded = await call('search', {'query': 'worth locking'});
      expect([for (final h in unguarded) h['pageId']], [diary.id]);
    });

    test('there is no tool that takes a passcode', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Nothing to brute-force: no tool's name or arguments mention one.
      final (_, body) = await post(
          {'jsonrpc': '2.0', 'id': ++nextId, 'method': 'tools/list'});
      final tools = (body!['result'] as Map)['tools'] as List;
      for (final t in tools) {
        expect(jsonEncode(t['inputSchema']), isNot(contains('passcode')),
            reason: t['name']);
        expect(t['name'], isNot(contains('unlock')));
      }
    });
  });

  group('what an AI helper can change', () {
    test('every tool that changes a page refuses one behind a passcode, and '
        'leaves it exactly as it was', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final before = pageJson(nb, diary.id);
      final blockId = app.readPageOf(nb, diary.id).blocks.single.id;
      final attempts = <String, Map<String, Object?>>{
        'append_blocks': {
          'pageId': diary.id,
          'blocks': [
            {
              'type': 'text',
              'content': {'text': 'x'}
            }
          ]
        },
        'append_markdown': {'pageId': diary.id, 'markdown': 'x'},
        'insert_blocks': {'pageId': diary.id, 'y': 300, 'markdown': 'x'},
        'update_block': {
          'pageId': diary.id,
          'blockId': blockId,
          'content': {'text': 'overwritten'}
        },
        'delete_blocks': {
          'pageId': diary.id,
          'blockIds': [blockId]
        },
        'move_blocks': {
          'pageId': diary.id,
          'blockIds': [blockId],
          'dx': 10
        },
        'create_flashcards': {
          'pageId': diary.id,
          'cards': [
            {'front': 'a', 'back': 'b'}
          ]
        },
        'rename_page': {'pageId': diary.id, 'title': 'Not a diary'},
        'move_page': {'pageId': diary.id, 'sectionId': biology.id},
        'delete_page': {'pageId': diary.id},
        // The section itself.
        'create_page': {'title': 'Sneaky', 'sectionId': private.id},
        'create_pages': {
          'sectionId': private.id,
          'pages': [
            {'title': 'Sneaky'}
          ]
        },
      };
      for (final e in attempts.entries) {
        final r = await call(e.key, e.value);
        expect(r, isA<_Refused>(), reason: e.key);
        expect((r as _Refused).message, contains('passcode'), reason: e.key);
      }
      expect(await call('rename_page', {'pageId': private.id, 'title': 'Open'}),
          isA<_Refused>());

      app.reloadNodes();
      expect(pageJson(nb, diary.id), before);
      expect(app.node(diary.id)?.title, 'Diary');
      expect(app.node(diary.id)?.parentId, private.id);
      expect(app.node(private.id)?.title, 'Private');
      expect([for (final p in app.pagesOf(private.id)) p.title], ['Diary']);
    });

    test('NEGATIVE CONTROL: the same calls work on a page without one',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final added = await call(
          'append_markdown', {'pageId': lectures.id, 'markdown': 'ATP'});
      expect(added, isNot(isA<_Refused>()));
      expect(await call('rename_page', {'pageId': lectures.id, 'title': 'L1'}),
          isNot(isA<_Refused>()));
      expect(await call('read_page', {'pageId': lectures.id}),
          isNot(isA<_Refused>()));
    });

    test('a new page goes to a section an AI helper may use', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // With no section named, a new page goes to the notebook's first one.
      // When that one has a passcode, refusing would be a refusal of a call
      // that never named it — so it goes to the first that has none.
      final first = app.nodes.firstWhere((n) => n.kind == NodeKind.section);
      expect(first.id, isNot(biology.id), reason: 'the notebook\'s own one');
      app.protectNode(first.id, '1111', UnlockPolicy.session);
      final made = await call('create_page', {'title': 'Week 4'});
      app.reloadNodes();
      expect(app.node(made['pageId'] as String)?.parentId, biology.id);
    });
  });

  group('the tree cannot be rearranged round a passcode', () {
    // A passcode on a page covers the subpages indented under it — and
    // indenting is only `level` plus order (state/page_protection.dart). So
    // these are the moves that could take a page out from under one, or slip
    // one in, without ever naming anything locked.

    test('a subpage cannot be appended under a page with a passcode',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.protectNode(lectures.id, '1357', UnlockPolicy.session);
      final r = await call('create_page',
          {'title': 'Sub', 'sectionId': biology.id, 'level': 1});
      expect(r, isA<_Refused>());
      expect((r as _Refused).message, contains('passcode'));
      app.reloadNodes();
      expect(app.pagesOf(biology.id), hasLength(1), reason: 'nothing made');

      // NEGATIVE CONTROL: at the top level it is nobody's subpage.
      expect(await call('create_page', {'title': 'Top', 'sectionId': biology.id}),
          isNot(isA<_Refused>()));
    });

    test('nor placed after one', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      app.protectNode(lectures.id, '1357', UnlockPolicy.session);
      expect(
          await call('create_page',
              {'title': 'Next', 'sectionId': biology.id, 'afterPageId': lectures.id}),
          isA<_Refused>());
      expect(
          await call('move_page', {
            'pageId': (await call('create_page',
                {'title': 'Elsewhere', 'sectionId': biology.id}))['pageId'],
            'afterPageId': lectures.id
          }),
          isA<_Refused>());
    });

    test('re-indenting cannot flatten a subpage out from under its passcode',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Topic (0) › Locked (1, passcode) › Under it (2). Indenting Topic by
      // one would clamp Locked and Under it both to level 2 — and Under it
      // would then hang off Topic, with no passcode over it at all.
      final topic = page(nb, biology, 'Topic', position: 'b2');
      final locked = page(nb, biology, 'Locked', position: 'b3', level: 1);
      final under = page(nb, biology, 'Under it', position: 'b4', level: 2);
      app.reloadNodes();
      app.protectNode(locked.id, '9753', UnlockPolicy.session);
      expect(app.governingNode(under.id), locked.id, reason: 'covered');

      for (final args in [
        {'pageId': topic.id, 'level': 1},
        {'pageId': topic.id, 'sectionId': private.id},
        {'pageId': topic.id, 'afterPageId': lectures.id},
      ]) {
        final r = await call('move_page', args);
        expect(r, isA<_Refused>(), reason: '$args');
      }
      expect(await call('move_page', {'pageId': under.id, 'level': 0}),
          isA<_Refused>(), reason: 'named directly');

      app.reloadNodes();
      expect([for (final p in app.pagesOf(biology.id)) (p.title, p.level)], [
        ('Lectures', 0),
        ('Topic', 0),
        ('Locked', 1),
        ('Under it', 2),
      ]);
      expect(app.governingNode(under.id), locked.id, reason: 'still covered');
    });

    test('deleting a page cannot slide its subpages under a passcode',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // Locked (0, passcode), Open (0) › Its sub (1). A deleted page's
      // subpages are kept, and slide up to the page above — here, Locked.
      final lockedTop = page(nb, biology, 'Locked', position: 'b2');
      final open = page(nb, biology, 'Open', position: 'b3');
      final sub = page(nb, biology, 'Its sub', position: 'b4', level: 1);
      app.reloadNodes();
      app.protectNode(lockedTop.id, '8642', UnlockPolicy.session);
      expect(app.governingNode(sub.id), isNull);

      expect(await call('delete_page', {'pageId': open.id}), isA<_Refused>());
      app.reloadNodes();
      expect(app.node(open.id), isNotNull);
      expect(app.governingNode(sub.id), isNull);

      // NEGATIVE CONTROL: deleting the subpage itself changes nobody else.
      expect(await call('delete_page', {'pageId': sub.id}),
          isNot(isA<_Refused>()));
    });
  });

  group('every notebook, not only the open one', () {
    test('a passcode in a notebook that is not open still counts', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The app's own gate loads one notebook's passcodes at a time, because
      // it only ever shows one. This door reaches all of them.
      final other = (await repo.createNotebook('Personal')).id;
      final journal = app.importNode(other,
          TreeNode(kind: NodeKind.section, title: 'Journal', position: 'b0'));
      final entry = page(other, journal, 'Entry', position: 'b1');
      app.importPage(other, entry.id, [text('private thoughts')], PageProps());
      repo.setSetting('protect:$other:${journal.id}',
          newProtection('1357', UnlockPolicy.session).toJson());
      expect(app.isLocked(entry.id), isFalse,
          reason: 'why this needed its own check: the app asks the OPEN '
              'notebook, and this is not it');

      final listing = await call('list_pages', {'notebookId': other});
      expect(idsIn(listing), isNot(contains(journal.id)));
      expect(idsIn(listing), isNot(contains(entry.id)));
      expect(listing['withheld'], contains('passcode'));
      expect(await call('read_page', {'pageId': entry.id}), isA<_Refused>());
      expect(
          await call(
              'search', {'query': 'private thoughts', 'notebookId': other}),
          isEmpty);
      expect(
          await call('append_markdown', {'pageId': entry.id, 'markdown': 'x'}),
          isA<_Refused>());
      expect(pageJson(other, entry.id), contains('private thoughts'));
    });
  });

  group('page windows', () {
    Map<String, Object?> window(String onto) =>
        {'type': 'embed', 'w': 300, 'h': 200, 'content': PortalRef.contentFor(onto)};

    test('an AI helper cannot put a window onto a page with a passcode',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // A window shows its source live: writing one would put the locked page
      // on a page that has no passcode.
      final r = await call('append_blocks', {
        'pageId': lectures.id,
        'blocks': [window(diary.id)]
      });
      expect(r, isA<_Refused>());
      expect((r as _Refused).message, contains('passcode'));

      // NEGATIVE CONTROL: a window onto a page without one is fine.
      final other = page(nb, biology, 'Other', position: 'b2');
      app.reloadNodes();
      expect(
          await call('append_blocks', {
            'pageId': lectures.id,
            'blocks': [window(other.id)]
          }),
          isNot(isA<_Refused>()));
    });

    test('nor repoint an existing one there', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final other = page(nb, biology, 'Other', position: 'b2');
      app.reloadNodes();
      final added = await call('append_blocks', {
        'pageId': lectures.id,
        'blocks': [window(other.id)]
      });
      final id = (added['blocks'] as List).single['id'];
      expect(
          await call('update_block', {
            'pageId': lectures.id,
            'blockId': id,
            'content': PortalRef.contentFor(diary.id),
          }),
          isA<_Refused>());
    });

    test('a window someone else made does not give the locked page away',
        () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      // The owner can make one themselves. Reading the page it sits on must
      // not name the page behind the passcode.
      // On a page that is not open, so what is read is what was stored.
      final host = page(nb, biology, 'Host', position: 'b2');
      app.reloadNodes();
      app.importPage(
          nb,
          host.id,
          [
            text('see below'),
            Block(
                type: BlockType.embed,
                x: 40,
                y: 300,
                w: 300,
                h: 200,
                content: PortalRef.contentFor(diary.id)),
          ],
          PageProps());
      final md =
          await call('read_page', {'pageId': host.id, 'format': 'markdown'});
      expect(md, contains('a page with a passcode'));
      expect(md, isNot(contains('Diary')));
    });
  });

  group('the Origin check', () {
    test('compares the host, not the start of the string', () {
      // The old test was `startsWith('http://localhost')`, which
      // `http://localhost.evil.com` passes — a name anyone can register.
      for (final ok in [
        'http://localhost',
        'http://localhost:6274',
        'http://127.0.0.1',
        'http://127.0.0.1:3000',
      ]) {
        expect(McpServer.isLoopbackOrigin(ok), isTrue, reason: ok);
      }
      for (final bad in [
        'http://localhost.evil.com',
        'http://127.0.0.1.evil.com',
        'http://localhost@evil.com',
        'http://evil.com@localhost',
        'http://localhost:6274/path',
        'http://localhost?x=1',
        'https://evil.example',
        'https://localhost',
        'null',
        '',
      ]) {
        expect(McpServer.isLoopbackOrigin(bad), isFalse, reason: bad);
      }
    });

    test('over the wire too', () async {
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      final list = {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'};
      final (evil, _) = await post(list, origin: 'http://localhost.evil.com');
      expect(evil, 403);
      final (local, _) = await post(list, origin: 'http://localhost:6274');
      expect(local, 200, reason: 'NEGATIVE CONTROL: a real local page passes');
    });
  });
}

class _Refused {
  _Refused(this.message);
  final String message;
  @override
  String toString() => 'refused: $message';
}
