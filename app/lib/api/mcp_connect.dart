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
  const _JsonClient(this.name, this.configParts, this.markerParts, this.entry);
  final String name;

  /// Config path, relative to the home directory. A FUNCTION because the
  /// desktop apps put theirs somewhere different on every platform, while the
  /// CLI tools use one dotfile everywhere.
  final List<String> Function() configParts;

  /// Directory whose presence means "this tool is installed here".
  final List<String> Function() markerParts;
  final Map<String, dynamic> Function(int port, String token) entry;
}

/// What every client that speaks Streamable HTTP wants: a URL and a bearer
/// header. `type` is stated explicitly because a client that also supports
/// stdio has to be told which this is.
Map<String, dynamic> _httpEntry(int port, String token) => {
      'type': 'http',
      'url': 'http://127.0.0.1:$port/mcp',
      'headers': {'Authorization': 'Bearer $token'},
    };

/// Where a desktop app keeps its config, relative to home.
///
/// Windows uses `%APPDATA%`, which is `AppData/Roaming` under the home
/// directory — spelled out rather than read from the environment so that a
/// test can point the whole thing at a temporary home.
List<String> _appSupportDir(String vendor) =>
    switch (Platform.operatingSystem) {
      'windows' => ['AppData', 'Roaming', vendor],
      'macos' => ['Library', 'Application Support', vendor],
      _ => ['.config', vendor],
    };

List<String> _appSupportParts(String vendor, String file) =>
    [..._appSupportDir(vendor), file];

final List<_JsonClient> _clients = [
  _JsonClient('Claude Code', () => ['.claude.json'], () => ['.claude'],
      _httpEntry),
  _JsonClient('Gemini CLI', () => ['.gemini', 'settings.json'],
      () => ['.gemini'],
      (port, token) => {
            'httpUrl': 'http://127.0.0.1:$port/mcp',
            'headers': {'Authorization': 'Bearer $token'},
          }),
  // **The Claude app, not Claude Code** — which is how most people use Claude,
  // and the thing that was missing. It reads the same kind of manifest and
  // takes a `url` with `headers`, so the server this app already runs needs no
  // changes: Streamable HTTP on loopback with a bearer token is exactly what
  // it wants.
  _JsonClient(
      'Claude app',
      () => _appSupportParts('Claude', 'claude_desktop_config.json'),
      () => _appSupportDir('Claude'),
      _httpEntry),
];

/// **ChatGPT's shared Codex config, which is TOML rather than JSON.**
///
/// Per OpenAI's own documentation the ChatGPT **desktop app**, the Codex CLI
/// and the IDE extension all read `~/.codex/config.toml` — the same path on
/// every platform — and it accepts a Streamable HTTP server with static
/// headers. That is exactly what this app already serves, so nothing on the
/// server side changes. The ChatGPT **website** does not read this file, which
/// is why the website can never reach a loopback server however its UI looks.
///
/// `http_headers` rather than `bearer_token_env_var`: the latter names an
/// environment variable, and Openote cannot set one inside ChatGPT's process.
/// So the token sits in the file in clear — as it already does in the JSON
/// configs written above — which is why the dialog calls it a password.
const String _codexServerTable = '[mcp_servers.openote]';
const String _codexHeaderTable = '[mcp_servers.openote.http_headers]';

/// **Edited by the line, not parsed and re-emitted.**
///
/// There is no TOML parser here, and adding one to write six lines would be
/// the wrong trade — but the better reason is that parse-and-reserialise would
/// reformat somebody's file and discard their comments. Replacing only our own
/// two tables leaves every other byte exactly as it was.
///
/// A TOML table runs from its `[header]` to the next line that opens one, so
/// removing ours is: drop the header and everything after it until the next
/// `[`.
String _withoutTable(String text, String header) {
  final out = <String>[];
  var skipping = false;
  for (final line in text.split('\n')) {
    final t = line.trim();
    if (skipping) {
      if (!t.startsWith('[')) continue;
      skipping = false;
    }
    if (t == header) {
      skipping = true;
      continue;
    }
    out.add(line);
  }
  return out.join('\n');
}

String _codexConfig(String existing, int port, String token) {
  var body = _withoutTable(existing, _codexServerTable);
  body = _withoutTable(body, _codexHeaderTable).trimRight();
  final ours = '$_codexServerTable\n'
      'url = "${mcpUrl(port)}"\n'
      '\n'
      '$_codexHeaderTable\n'
      '"Authorization" = "Bearer $token"\n';
  return body.isEmpty ? ours : '$body\n\n$ours';
}

/// Is this a file we dare edit by the line?
///
/// The JSON path refuses a file it cannot parse rather than overwriting it, and
/// this keeps the same promise with a cruder test. TOML that a line-based edit
/// can reason about is lines that are blank, comments, table headers, or
/// `key = value` whose value closes on the same line. Anything else — a
/// multi-line array, a triple-quoted string — means our edit could land inside
/// somebody's value, so we decline and leave it alone.
bool _looksLikeSimpleToml(String text) {
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('[')) {
      if (!line.endsWith(']')) return false;
      continue;
    }
    final eq = line.indexOf('=');
    if (eq < 0) return false;
    final value = line.substring(eq + 1).trim();
    final opens = value.startsWith('[') || value.startsWith('{');
    final closes = value.endsWith(']') || value.endsWith('}');
    if (opens && !closes) return false;
    if (value.startsWith('"""') || value.startsWith("'''")) return false;
  }
  return true;
}

/// Connect the ChatGPT desktop app — and the Codex CLI, which shares the file.
ClaudeConnectResult connectChatGpt(
    {required int port, required String token, String? home}) {
  final h = home ?? userHomeDir();
  final cfg = File(_p(h, ['.codex', 'config.toml']));
  final existedBefore = cfg.existsSync();
  var installed = Directory(_p(h, ['.codex'])).existsSync();

  var existing = '';
  if (existedBefore) {
    try {
      existing = cfg.readAsStringSync();
    } catch (_) {
      return const ClaudeConnectResult(
          ClaudeConnect.failed,
          "ChatGPT's settings file couldn't be read, so Openote left it "
          'alone. The connection details under Advanced still work.');
    }
    if (!_looksLikeSimpleToml(existing)) {
      return const ClaudeConnectResult(
          ClaudeConnect.failed,
          "ChatGPT's settings file has something in it Openote doesn't "
          'understand, so it was left alone. Copy the configuration under '
          'Advanced and add it by hand.');
    }
    // Anything already in the file was put there by the tool itself.
    installed = true;
    final bak = File('${cfg.path}.openote-backup');
    if (!bak.existsSync()) {
      try {
        cfg.copySync(bak.path);
      } catch (_) {
        // A missing backup is not worth failing the connection for.
      }
    }
  }

  try {
    cfg.parent.createSync(recursive: true);
    cfg.writeAsStringSync(_codexConfig(existing, port, token));
  } catch (e) {
    return ClaudeConnectResult(
        ClaudeConnect.failed, "Couldn't save the connection: $e");
  }

  return installed
      ? const ClaudeConnectResult(
          ClaudeConnect.connected,
          'Connected. Restart the ChatGPT desktop app and Openote will be '
          'there under its MCP servers. The website cannot use this — only '
          'an app on this computer can see Openote.')
      : const ClaudeConnectResult(
          ClaudeConnect.wroteConfigOnly,
          'Saved. Openote will appear once the ChatGPT desktop app or the '
          'Codex CLI is installed on this computer.');
}

/// Keep ChatGPT's entry current when the port moves, as the JSON clients do.
void _refreshChatGpt(int port, String token, String home) {
  final cfg = File(_p(home, ['.codex', 'config.toml']));
  if (!cfg.existsSync()) return;
  try {
    final existing = cfg.readAsStringSync();
    // Only a file we are already in: Openote does not write into another
    // tool's config uninvited.
    if (!existing.contains(_codexServerTable)) return;
    if (!_looksLikeSimpleToml(existing)) return;
    final fresh = _codexConfig(existing, port, token);
    if (fresh != existing) cfg.writeAsStringSync(fresh);
  } catch (_) {
    // Best-effort by design: a failed refresh must never break app start.
  }
}

ClaudeConnectResult _connect(_JsonClient client,
    {required int port, required String token, String? home}) {
  final h = home ?? userHomeDir();
  final cfg = File(_p(h, client.configParts()));

  // Installed-ness is judged BEFORE we write anything, so our own file
  // can't vouch for a tool that isn't there.
  final existedBefore = cfg.existsSync();
  var installed = Directory(_p(h, client.markerParts())).existsSync();

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

/// The Claude desktop app — chat, not Claude Code.
ClaudeConnectResult connectClaudeApp(
        {required int port, required String token, String? home}) =>
    _connect(_clients[2], port: port, token: token, home: home);

/// What to show somebody whose client has no button: the exact block to paste.
///
/// Every remaining MCP-capable client takes some spelling of "this URL with
/// this header", so one correct example plus the two values is more use than a
/// button per vendor — and it does not go stale when a vendor renames a menu.
String manualConfigJson(int port, String token) =>
    const JsonEncoder.withIndent('  ').convert({
      'mcpServers': {'openote': _httpEntry(port, token)}
    });

String mcpUrl(int port) => 'http://127.0.0.1:$port/mcp';

/// Which tools already have Openote in their configuration.
///
/// **Read from the files, not remembered.** A flag stored in Openote would go
/// stale the moment somebody edits or removes the entry in the other tool —
/// and then the button would claim a connection that is not there, which is
/// worse than not showing the state at all.
({bool claudeCode, bool claudeApp, bool geminiCli, bool chatGpt})
    connectedClients({String? home}) {
  final h = home ?? userHomeDir();
  return (
    claudeCode: _jsonHasOpenote(_p(h, _clients[0].configParts())),
    geminiCli: _jsonHasOpenote(_p(h, _clients[1].configParts())),
    claudeApp: _jsonHasOpenote(_p(h, _clients[2].configParts())),
    chatGpt: _tomlHasOpenote(_p(h, ['.codex', 'config.toml'])),
  );
}

bool _jsonHasOpenote(String path) {
  try {
    final f = File(path);
    if (!f.existsSync()) return false;
    final parsed = jsonDecode(f.readAsStringSync());
    if (parsed is! Map) return false;
    final servers = parsed['mcpServers'];
    return servers is Map && servers.containsKey('openote');
  } catch (_) {
    // Unreadable or malformed answers "no": the question is whether a working
    // connection exists, and one we cannot read is not one.
    return false;
  }
}

bool _tomlHasOpenote(String path) {
  try {
    final f = File(path);
    return f.existsSync() &&
        f.readAsStringSync().contains(_codexServerTable);
  } catch (_) {
    return false;
  }
}

/// Keep EXISTING connections current (the port can move if another app
/// held it). Called whenever the server starts; deliberately does nothing
/// for a tool the user never connected — Openote doesn't write into other
/// apps' config uninvited.
void refreshConnectedClients(
    {required int port, required String token, String? home}) {
  final h = home ?? userHomeDir();
  for (final client in _clients) {
    try {
      final cfg = File(_p(h, client.configParts()));
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
  _refreshChatGpt(port, token, h);
}
