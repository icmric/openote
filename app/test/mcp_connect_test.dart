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

  group('refreshConnectedClients', () {
    test('updates stale entries the user made — in every connected tool',
        () {
      Directory('${home.path}${Platform.pathSeparator}.gemini').createSync();
      connectClaudeCode(port: 27191, token: 'tok', home: home.path);
      connectGeminiCli(port: 27191, token: 'tok', home: home.path);
      refreshConnectedClients(port: 27300, token: 'tok2', home: home.path);

      final claude = read()['mcpServers']['openote'] as Map;
      expect(claude['url'], 'http://127.0.0.1:27300/mcp');
      expect(claude['headers']['Authorization'], 'Bearer tok2');
      final gemini = jsonDecode(File(
              '${home.path}${Platform.pathSeparator}.gemini${Platform.pathSeparator}settings.json')
          .readAsStringSync())['mcpServers']['openote'] as Map;
      expect(gemini['httpUrl'], 'http://127.0.0.1:27300/mcp');
    });

    test('does NOTHING when the user never connected', () {
      refreshConnectedClients(port: 27191, token: 'tok', home: home.path);
      expect(cfg().existsSync(), isFalse,
          reason: "Openote doesn't write into other apps' config uninvited");

      cfg().writeAsStringSync(jsonEncode({'mcpServers': {}}));
      final before = cfg().readAsStringSync();
      refreshConnectedClients(port: 27191, token: 'tok', home: home.path);
      expect(cfg().readAsStringSync(), before);
    });
  });

  group('Gemini CLI', () {
    File gcfg() => File(
        '${home.path}${Platform.pathSeparator}.gemini${Platform.pathSeparator}settings.json');

    test('with ~/.gemini present: connected, httpUrl form, keys preserved',
        () {
      Directory(gcfg().parent.path).createSync();
      gcfg().writeAsStringSync(jsonEncode({'theme': 'Default'}));
      final r = connectGeminiCli(port: 27191, token: 'tok', home: home.path);
      expect(r.status, ClaudeConnect.connected);
      expect(r.message, contains('Gemini CLI'));

      final root =
          jsonDecode(gcfg().readAsStringSync()) as Map<String, dynamic>;
      expect(root['theme'], 'Default', reason: 'existing settings survive');
      expect(root['mcpServers']['openote']['httpUrl'],
          'http://127.0.0.1:27191/mcp');
      expect(File('${gcfg().path}.openote-backup').existsSync(), isTrue);
    });

    test('without ~/.gemini: writes config, honest about not installed', () {
      final r = connectGeminiCli(port: 27191, token: 'tok', home: home.path);
      expect(r.status, ClaudeConnect.wroteConfigOnly);
      expect(r.message, contains("doesn't look installed"));
      expect(gcfg().existsSync(), isTrue,
          reason: 'ready the moment Gemini CLI is installed');
    });

    test('corrupt settings: refuses to write, file untouched', () {
      Directory(gcfg().parent.path).createSync();
      gcfg().writeAsStringSync('[broken');
      final r = connectGeminiCli(port: 27191, token: 'tok', home: home.path);
      expect(r.status, ClaudeConnect.failed);
      expect(gcfg().readAsStringSync(), '[broken');
    });
  });

  group('the Claude APP — chat, not Claude Code', () {
    // The spec's client table said ChatGPT and the Gemini app were impossible
    // because their connectors run on the vendor's servers and cannot reach
    // 127.0.0.1. The Claude app was never in that table at all, and it is how
    // most people use Claude: *"it says it integrates with claude code, but is
    // this true? … can it also integrate with chat/cowork?"*. It reads a
    // manifest of the same shape and takes a URL with headers, so the server
    // already running needs nothing new.

    /// Where the app's config goes, which is a different place per platform.
    List<String> cfgParts() => switch (Platform.operatingSystem) {
          'windows' => ['AppData', 'Roaming', 'Claude',
              'claude_desktop_config.json'],
          'macos' => ['Library', 'Application Support', 'Claude',
              'claude_desktop_config.json'],
          _ => ['.config', 'Claude', 'claude_desktop_config.json'],
        };
    String cfgPath() =>
        [home.path, ...cfgParts()].join(Platform.pathSeparator);

    test('writes a loopback URL and a bearer header where the app reads it',
        () {
      final r = connectClaudeApp(port: 27311, token: 'tok', home: home.path);
      expect(r.status, isNot(ClaudeConnect.failed));

      final cfg = File(cfgPath());
      expect(cfg.existsSync(), isTrue,
          reason: 'at the platform path the app actually reads');
      final root = jsonDecode(cfg.readAsStringSync()) as Map<String, dynamic>;
      final entry = (root['mcpServers'] as Map)['openote'] as Map;
      expect(entry['type'], 'http');
      expect(entry['url'], 'http://127.0.0.1:27311/mcp');
      expect((entry['headers'] as Map)['Authorization'], 'Bearer tok');
    });

    test('an existing config is merged, not replaced', () {
      // Somebody else's servers are somebody else's. The whole reason this
      // writes a merge rather than a file is that these manifests are shared.
      final cfg = File(cfgPath())
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({
          'mcpServers': {
            'someone-else': {'command': 'their-tool'}
          },
          'theirSetting': true,
        }));

      connectClaudeApp(port: 27312, token: 'tok', home: home.path);

      final root = jsonDecode(cfg.readAsStringSync()) as Map<String, dynamic>;
      final servers = root['mcpServers'] as Map;
      expect(servers.containsKey('someone-else'), isTrue,
          reason: 'their server survives');
      expect(servers.containsKey('openote'), isTrue);
      expect(root['theirSetting'], isTrue, reason: 'and the rest of the file');
    });

    test('a moved port is refreshed, like the other connected clients', () {
      // The port can change between runs if something else held it, so a
      // connection made once has to keep working.
      connectClaudeApp(port: 27313, token: 'old', home: home.path);
      refreshConnectedClients(port: 27999, token: 'new', home: home.path);

      final root =
          jsonDecode(File(cfgPath()).readAsStringSync()) as Map<String, dynamic>;
      final entry = (root['mcpServers'] as Map)['openote'] as Map;
      expect(entry['url'], 'http://127.0.0.1:27999/mcp');
      expect((entry['headers'] as Map)['Authorization'], 'Bearer new');
    });
  });

  group('a client with no button', () {
    test('the manual block is the same connection, pasteable', () {
      // Every remaining MCP-capable client wants some spelling of "this URL
      // with this header". One correct example does not go stale when a vendor
      // renames a menu, which a button per vendor does.
      final json = manualConfigJson(27401, 'tok');
      final root = jsonDecode(json) as Map<String, dynamic>;
      final entry = (root['mcpServers'] as Map)['openote'] as Map;
      expect(entry['url'], mcpUrl(27401));
      expect((entry['headers'] as Map)['Authorization'], 'Bearer tok');
      expect(json, contains('  "openote"'),
          reason: 'indented, so a human can read it');
    });
  });
}
