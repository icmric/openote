// One-click Claude Code connection (spec 14 §8). The claims that matter:
// Openote NEVER destroys another app's config (merge, backup, refuse on
// corrupt), the status is honest about whether Claude Code exists, and the
// silent refresh only touches a connection the user actually made.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/api/mcp_connect.dart';

void main() {
  late Directory home;
  File cfg() => File('${home.path}${Platform.pathSeparator}.claude.json');

  setUp(() => home = Directory.systemTemp.createTempSync('onote_connect_'));
  tearDown(() {
    try {
      home.deleteSync(recursive: true);
    } catch (_) {}
  });

  Map<String, dynamic> read() =>
      jsonDecode(cfg().readAsStringSync()) as Map<String, dynamic>;

  test('no config, no Claude Code: writes the file, says what to install',
      () {
    final r = connectClaudeCode(port: 27191, token: 'tok', home: home.path);
    expect(r.status, ClaudeConnect.wroteConfigOnly);
    expect(r.message, contains("doesn't look installed"));
    final entry = read()['mcpServers']['openote'] as Map;
    expect(entry['url'], 'http://127.0.0.1:27191/mcp');
    expect(entry['headers']['Authorization'], 'Bearer tok');
  });

  test('existing Claude Code config: merged, preserved, backed up, connected',
      () {
    cfg().writeAsStringSync(jsonEncode({
      'installMethod': 'native',
      'projects': {'C:/somewhere': {}},
      'mcpServers': {
        'other-tool': {'type': 'stdio', 'command': 'other'},
      },
    }));
    final r = connectClaudeCode(port: 27201, token: 'tok', home: home.path);
    expect(r.status, ClaudeConnect.connected);

    final root = read();
    expect(root['installMethod'], 'native',
        reason: 'unrelated keys survive the merge');
    expect(root['projects'], isA<Map>());
    expect(root['mcpServers']['other-tool']['command'], 'other',
        reason: 'other MCP servers survive');
    expect(root['mcpServers']['openote']['url'],
        'http://127.0.0.1:27201/mcp');
    expect(File('${cfg().path}.openote-backup').existsSync(), isTrue,
        reason: 'a file we did not create gets a one-time backup');
  });

  test('connecting again updates the entry and keeps the FIRST backup', () {
    cfg().writeAsStringSync(jsonEncode({'installMethod': 'native'}));
    connectClaudeCode(port: 27191, token: 'old', home: home.path);
    final backupBefore =
        File('${cfg().path}.openote-backup').readAsStringSync();
    connectClaudeCode(port: 27195, token: 'new', home: home.path);

    expect(read()['mcpServers']['openote']['url'],
        'http://127.0.0.1:27195/mcp');
    expect(File('${cfg().path}.openote-backup').readAsStringSync(),
        backupBefore,
        reason: 'the backup is the pre-Openote state, never overwritten');
  });

  test('corrupt config: refuses to write, file untouched', () {
    cfg().writeAsStringSync('{not json');
    final r = connectClaudeCode(port: 27191, token: 'tok', home: home.path);
    expect(r.status, ClaudeConnect.failed);
    expect(cfg().readAsStringSync(), '{not json',
        reason: 'never destroy what we could not read');
  });

  test('~/.claude directory counts as installed', () {
    Directory('${home.path}${Platform.pathSeparator}.claude').createSync();
    final r = connectClaudeCode(port: 27191, token: 'tok', home: home.path);
    expect(r.status, ClaudeConnect.connected);
  });

  group('refreshClaudeCodeEntry', () {
    test('updates a stale entry the user made', () {
      connectClaudeCode(port: 27191, token: 'tok', home: home.path);
      refreshClaudeCodeEntry(port: 27300, token: 'tok2', home: home.path);
      final entry = read()['mcpServers']['openote'] as Map;
      expect(entry['url'], 'http://127.0.0.1:27300/mcp');
      expect(entry['headers']['Authorization'], 'Bearer tok2');
    });

    test('does NOTHING when the user never connected', () {
      refreshClaudeCodeEntry(port: 27191, token: 'tok', home: home.path);
      expect(cfg().existsSync(), isFalse,
          reason: "Openote doesn't write into other apps' config uninvited");

      cfg().writeAsStringSync(jsonEncode({'mcpServers': {}}));
      final before = cfg().readAsStringSync();
      refreshClaudeCodeEntry(port: 27191, token: 'tok', home: home.path);
      expect(cfg().readAsStringSync(), before);
    });
  });
}
