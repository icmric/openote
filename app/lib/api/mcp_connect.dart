/// One-click AI-tool connections (spec 14 §8).
///
/// The audience for the AI-access dialog is a year-10 student who does not
/// know what MCP is and has never opened a terminal — so Openote writes the
/// connection itself, into each tool's own settings file:
///
///   Claude Code   ~/.claude.json            mcpServers.openote
///   Gemini CLI    ~/.gemini/settings.json   mcpServers.openote (httpUrl)
///
/// ChatGPT and the Gemini app get NO button, deliberately: their connectors
/// run on the vendor's servers, which cannot reach 127.0.0.1 on the user's
/// machine — there is nothing to write that would make them work. The
/// dialog says so in plain words instead of pretending.
///
/// Rules this file lives by:
/// - **Never destroy someone else's config.** The file is read, decoded and
///   merged; if it does not parse, we refuse to touch it and say so. The
///   first write of a pre-existing file leaves a one-time backup beside it.
/// - **Honest status.** "Connected" only when the tool shows signs of being
///   installed; otherwise the config is written and the message says what
///   to install.
library;

import 'dart:convert';
import 'dart:io';

enum ClaudeConnect {
  /// Entry written and the tool looks installed.
  connected,

  /// Entry written, but no trace of the tool on this machine.
  wroteConfigOnly,

  /// Nothing written; [ClaudeConnectResult.message] says why.
  failed,
}

class ClaudeConnectResult {
  const ClaudeConnectResult(this.status, this.message);
  final ClaudeConnect status;
  final String message;
}

/// The user's home directory, cross-platform.
String userHomeDir() =>
    Platform.environment['USERPROFILE'] ??
    Platform.environment['HOME'] ??
    Directory.current.path;

String _p(String home, List<String> parts) =>
    ([home, ...parts]).join(Platform.pathSeparator);

/// A tool whose MCP connections live in a JSON settings file it owns.
class _JsonClient {
  const _JsonClient(this.name, this.configParts, this.markerDir, this.entry);
  final String name;
  final List<String> configParts;

  /// Directory whose presence means "this tool is installed here".
  final String markerDir;
  final Map<String, dynamic> Function(int port, String token) entry;
}

final List<_JsonClient> _clients = [
  _JsonClient('Claude Code', ['.claude.json'], '.claude',
      (port, token) => {
            'type': 'http',
            'url': 'http://127.0.0.1:$port/mcp',
            'headers': {'Authorization': 'Bearer $token'},
          }),
  _JsonClient('Gemini CLI', ['.gemini', 'settings.json'], '.gemini',
      (port, token) => {
            'httpUrl': 'http://127.0.0.1:$port/mcp',
            'headers': {'Authorization': 'Bearer $token'},
          }),
];

ClaudeConnectResult _connect(_JsonClient client,
    {required int port, required String token, String? home}) {
  final h = home ?? userHomeDir();
  final cfg = File(_p(h, client.configParts));

  // Installed-ness is judged BEFORE we write anything, so our own file
  // can't vouch for a tool that isn't there.
  final existedBefore = cfg.existsSync();
  var installed = Directory(_p(h, [client.markerDir])).existsSync();

  Map<String, dynamic> root = {};
  if (existedBefore) {
    try {
      final parsed = jsonDecode(cfg.readAsStringSync());
      if (parsed is! Map) throw const FormatException('not an object');
      root = Map<String, dynamic>.from(parsed);
    } catch (_) {
      return ClaudeConnectResult(
          ClaudeConnect.failed,
          "${client.name}'s settings file couldn't be read, so Openote "
          'left it alone. The connection details under Advanced still '
          'work in any MCP-capable tool.');
    }
    // A config with anything beyond mcpServers was written by the tool
    // itself — that counts as installed even without its directory.
    installed = installed || root.keys.any((k) => k != 'mcpServers');
    // One-time backup, only of a file we did not create ourselves.
    final bak = File('${cfg.path}.openote-backup');
    if (!bak.existsSync()) {
      try {
        cfg.copySync(bak.path);
      } catch (_) {
        // A missing backup is not worth failing the connection for.
      }
    }
  }

  final servers = root['mcpServers'];
  root['mcpServers'] = {
    if (servers is Map) ...Map<String, dynamic>.from(servers),
    'openote': client.entry(port, token),
  };

  try {
    cfg.parent.createSync(recursive: true);
    cfg.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(root));
  } catch (e) {
    return ClaudeConnectResult(
        ClaudeConnect.failed, "Couldn't save the connection: $e");
  }

  return installed
      ? ClaudeConnectResult(
          ClaudeConnect.connected,
          'Connected. Open ${client.name} and ask it about your notes — '
          'try "quiz me on what I wrote this week".')
      : ClaudeConnectResult(
          ClaudeConnect.wroteConfigOnly,
          "Openote is ready, but ${client.name} doesn't look installed on "
          'this computer yet. Once it is, the connection will just work.');
}

ClaudeConnectResult connectClaudeCode(
        {required int port, required String token, String? home}) =>
    _connect(_clients[0], port: port, token: token, home: home);

ClaudeConnectResult connectGeminiCli(
        {required int port, required String token, String? home}) =>
    _connect(_clients[1], port: port, token: token, home: home);

/// Keep EXISTING connections current (the port can move if another app
/// held it). Called whenever the server starts; deliberately does nothing
/// for a tool the user never connected — Openote doesn't write into other
/// apps' config uninvited.
void refreshConnectedClients(
    {required int port, required String token, String? home}) {
  final h = home ?? userHomeDir();
  for (final client in _clients) {
    try {
      final cfg = File(_p(h, client.configParts));
      if (!cfg.existsSync()) continue;
      final parsed = jsonDecode(cfg.readAsStringSync());
      if (parsed is! Map) continue;
      final root = Map<String, dynamic>.from(parsed);
      final servers = root['mcpServers'];
      if (servers is! Map || !servers.containsKey('openote')) continue;
      final fresh = client.entry(port, token);
      if (jsonEncode(servers['openote']) == jsonEncode(fresh)) continue;
      root['mcpServers'] = {
        ...Map<String, dynamic>.from(servers),
        'openote': fresh,
      };
      cfg.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(root));
    } catch (_) {
      // Best-effort by design: a failed refresh must never break app start.
    }
  }
}
