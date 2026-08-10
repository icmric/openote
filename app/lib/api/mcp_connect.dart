/// One-click Claude Code connection (spec 14 §8).
///
/// The audience for the AI-access dialog is a year-10 student who does not
/// know what MCP is and has never opened a terminal — so Openote writes the
/// connection itself. Claude Code keeps its user-scope MCP servers in
/// `~/.claude.json` under `mcpServers`; adding our entry there is exactly
/// what `claude mcp add --scope user` does, minus the terminal.
///
/// Rules this file lives by:
/// - **Never destroy someone else's config.** The file is read, decoded and
///   merged; if it does not parse, we refuse to touch it and say so. The
///   first write of an existing file leaves a one-time backup beside it.
/// - **Honest status.** "Connected" only when Claude Code shows signs of
///   being installed; otherwise the config is written and the message says
///   what to install.
library;

import 'dart:convert';
import 'dart:io';

enum ClaudeConnect {
  /// Entry written and Claude Code looks installed.
  connected,

  /// Entry written, but no trace of Claude Code on this machine.
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

Map<String, dynamic> _entry(int port, String token) => {
      'type': 'http',
      'url': 'http://127.0.0.1:$port/mcp',
      'headers': {'Authorization': 'Bearer $token'},
    };

/// Write (or update) the `openote` server entry in Claude Code's user
/// config. Creates the file if Claude Code hasn't made one yet — the entry
/// starts working the moment Claude Code is installed.
ClaudeConnectResult connectClaudeCode(
    {required int port, required String token, String? home}) {
  final h = home ?? userHomeDir();
  final cfg = File('$h${Platform.pathSeparator}.claude.json');

  Map<String, dynamic> root = {};
  if (cfg.existsSync()) {
    try {
      final parsed = jsonDecode(cfg.readAsStringSync());
      if (parsed is! Map) throw const FormatException('not an object');
      root = Map<String, dynamic>.from(parsed);
    } catch (_) {
      return const ClaudeConnectResult(
          ClaudeConnect.failed,
          "Claude Code's settings file couldn't be read, so Openote left "
          'it alone. Ask Claude Code itself to add the connection — the '
          'details are under Advanced below.');
    }
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
    'openote': _entry(port, token),
  };

  try {
    cfg.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(root));
  } catch (e) {
    return ClaudeConnectResult(ClaudeConnect.failed,
        "Couldn't save the connection: $e");
  }

  final installed = cfg.existsSync() &&
      (Directory('$h${Platform.pathSeparator}.claude').existsSync() ||
          root.keys.any((k) => k != 'mcpServers'));
  return installed
      ? const ClaudeConnectResult(ClaudeConnect.connected,
          'Connected. Open Claude Code and ask it about your notes — try '
          '"quiz me on what I wrote this week".')
      : const ClaudeConnectResult(ClaudeConnect.wroteConfigOnly,
          "Openote is ready, but Claude Code doesn't look installed on "
          'this computer yet. Once it is, the connection will just work.');
}

/// Keep an EXISTING connection current (the port can move if another app
/// held it). Called whenever the server starts; deliberately does nothing
/// when the user never pressed Connect — Openote doesn't write into other
/// apps' config uninvited.
void refreshClaudeCodeEntry(
    {required int port, required String token, String? home}) {
  try {
    final h = home ?? userHomeDir();
    final cfg = File('$h${Platform.pathSeparator}.claude.json');
    if (!cfg.existsSync()) return;
    final parsed = jsonDecode(cfg.readAsStringSync());
    if (parsed is! Map) return;
    final root = Map<String, dynamic>.from(parsed);
    final servers = root['mcpServers'];
    if (servers is! Map || !servers.containsKey('openote')) return;
    final fresh = _entry(port, token);
    if (jsonEncode(servers['openote']) == jsonEncode(fresh)) return;
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
