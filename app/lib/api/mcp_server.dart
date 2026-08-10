/// The app-hosted MCP server — External API Spec (docs/specs/14) made real.
///
/// A deliberately MINIMAL, hand-rolled implementation of MCP's streamable
/// HTTP transport: JSON-RPC 2.0 over POST, stateless, five methods
/// (`initialize`, `notifications/initialized`, `ping`, `tools/list`,
/// `tools/call`). Hand-rolled because the protocol subset is ~200 lines and
/// full control over the security posture (spec §4) matters more here than
/// a dependency's conveniences: loopback bind only, bearer token on every
/// request, Origin validation against DNS rebinding, a 1 MB body cap.
///
/// The server holds NO state of its own — every tool executes against the
/// live [AppState] — so it cannot drift from the app and dies with it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../state/app_state.dart';
import 'mcp_tools.dart';

/// The protocol revision answered when the client's is unknown to us.
const _protocolFallback = '2025-03-26';
const _knownProtocols = {'2024-11-05', '2025-03-26', '2025-06-18'};

class McpServer {
  McpServer(this.app);

  final AppState app;
  HttpServer? _http;
  String? _token;

  bool get running => _http != null;
  int? get port => _http?.port;

  /// Bind and serve. [preferredPort] first, walking up a few neighbours if
  /// taken (the chosen port is persisted by the caller so client configs
  /// stay valid); port 0 asks the OS for any free port — tests use that.
  Future<int> start({required String token, int preferredPort = 27191}) async {
    await stop();
    _token = token;
    HttpServer? server;
    if (preferredPort == 0) {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } else {
      for (var p = preferredPort; p < preferredPort + 10; p++) {
        try {
          server = await HttpServer.bind(InternetAddress.loopbackIPv4, p);
          break;
        } on SocketException {
          continue; // taken — try the neighbour
        }
      }
      server ??= await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    }
    _http = server;
    server.listen(_handle, onError: (Object e) {
      debugPrint('[openote/mcp] $e');
    });
    return server.port;
  }

  Future<void> stop() async {
    final s = _http;
    _http = null;
    await s?.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      // Origin validation (spec §4.3): browsers always send Origin on
      // cross-origin requests; anything non-local is a rebinding attempt.
      // Ordinary MCP clients send none and pass.
      final origin = req.headers.value('origin');
      if (origin != null &&
          !origin.startsWith('http://localhost') &&
          !origin.startsWith('http://127.0.0.1')) {
        await _respond(req, HttpStatus.forbidden, {'error': 'bad origin'});
        return;
      }
      if (req.uri.path != '/mcp') {
        await _respond(req, HttpStatus.notFound, {'error': 'not found'});
        return;
      }
      if (req.method != 'POST') {
        // No SSE stream: this server is stateless JSON-response mode.
        await _respond(
            req, HttpStatus.methodNotAllowed, {'error': 'POST only'});
        return;
      }
      final auth = req.headers.value('authorization');
      if (_token == null || auth != 'Bearer $_token') {
        await _respond(req, HttpStatus.unauthorized, {'error': 'bad token'});
        return;
      }

      final bytes = <int>[];
      await for (final chunk in req) {
        bytes.addAll(chunk);
        if (bytes.length > 1 << 20) {
          await _respond(req, HttpStatus.requestEntityTooLarge,
              {'error': 'body over 1 MB'});
          return;
        }
      }
      final Object? body;
      try {
        body = jsonDecode(utf8.decode(bytes));
      } catch (_) {
        await _respond(req, HttpStatus.badRequest,
            _rpcError(null, -32700, 'parse error'));
        return;
      }

      if (body is List) {
        final replies = [
          for (final m in body)
            if (m is Map && m['id'] != null) await _dispatch(m.cast())
        ];
        await _respond(
            req, replies.isEmpty ? HttpStatus.accepted : HttpStatus.ok,
            replies.isEmpty ? null : replies);
        return;
      }
      if (body is! Map) {
        await _respond(req, HttpStatus.badRequest,
            _rpcError(null, -32600, 'invalid request'));
        return;
      }
      final msg = body.cast<String, Object?>();
      if (msg['id'] == null) {
        // A notification: acknowledge and move on.
        await _respond(req, HttpStatus.accepted, null);
        return;
      }
      await _respond(req, HttpStatus.ok, await _dispatch(msg));
    } catch (e) {
      debugPrint('[openote/mcp] $e');
      try {
        await _respond(req, HttpStatus.internalServerError,
            _rpcError(null, -32603, 'internal error'));
      } catch (_) {}
    }
  }

  Future<Map<String, Object?>> _dispatch(Map<String, Object?> msg) async {
    final id = msg['id'];
    final params = (msg['params'] as Map?)?.cast<String, Object?>() ?? const {};
    switch (msg['method']) {
      case 'initialize':
        final asked = params['protocolVersion'];
        return _rpcResult(id, {
          'protocolVersion':
              _knownProtocols.contains(asked) ? asked : _protocolFallback,
          'capabilities': {
            'tools': {'listChanged': false}
          },
          'serverInfo': {'name': 'openote', 'version': '1'},
        });
      case 'ping':
        return _rpcResult(id, {});
      case 'tools/list':
        return _rpcResult(id, {'tools': mcpToolDefinitions});
      case 'tools/call':
        final name = params['name'];
        final args =
            (params['arguments'] as Map?)?.cast<String, Object?>() ?? const {};
        if (name is! String) {
          return _rpcError(id, -32602, 'tool name missing');
        }
        try {
          final result = await callMcpTool(app, name, args);
          return _rpcResult(id, {
            'content': [
              {'type': 'text', 'text': result}
            ],
            'isError': false,
          });
        } on McpToolError catch (e) {
          // Tool-level failure: a RESULT with isError, per MCP — the model
          // gets to read the message and try again.
          return _rpcResult(id, {
            'content': [
              {'type': 'text', 'text': e.message}
            ],
            'isError': true,
          });
        }
      default:
        return _rpcError(id, -32601, 'method not found: ${msg['method']}');
    }
  }

  Map<String, Object?> _rpcResult(Object? id, Object result) =>
      {'jsonrpc': '2.0', 'id': id, 'result': result};

  Map<String, Object?> _rpcError(Object? id, int code, String message) => {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      };

  Future<void> _respond(HttpRequest req, int status, Object? body) async {
    req.response.statusCode = status;
    if (body != null) {
      req.response.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      req.response.write(jsonEncode(body));
    }
    await req.response.close();
  }
}
