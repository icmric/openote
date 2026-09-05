/// **Signing in to Microsoft, without ever seeing the password.**
///
/// The flow, in the order it happens:
///
///  1. Openote makes a random secret (the *verifier*) and sends only its
///     SHA-256 hash (the *challenge*) to Microsoft.
///  2. It starts a web server on this machine, on a port nothing else is
///     using, and opens the student's **real browser** at Microsoft's sign-in
///     page.
///  3. They sign in there. Openote never sees the password, cannot see it, and
///     is not in a position to — which is the whole reason the system browser
///     is used rather than a window inside the app.
///  4. Microsoft redirects the browser back to `http://localhost:<port>` with
///     a one-time code. The little server catches it and shuts down.
///  5. Openote swaps the code for a token, proving it is the same app that
///     started the flow by presenting the verifier whose hash it sent in
///     step 1.
///
/// ## Why PKCE, and why there is no client secret
///
/// Anything shipped inside a downloadable binary can be read out of it by
/// anyone who downloads it, so a desktop app cannot keep a secret and must not
/// pretend to. Entra calls this a *public client*. PKCE (RFC 7636) replaces
/// the secret: the code Microsoft hands back is worthless to anybody who did
/// not generate the verifier, so intercepting it achieves nothing.
///
/// ## Why loopback
///
/// RFC 8252 (OAuth for native apps). A desktop app has no server on the
/// internet to be redirected to, so it listens on `127.0.0.1` for the few
/// seconds the sign-in takes. Entra allows plain HTTP for loopback only, which
/// is safe because the traffic never reaches a network. It also matches **any
/// port** on a registered `http://localhost`, which is what lets the app take
/// whichever one happens to be free instead of demanding one be reserved.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../core/platform_open.dart';
import '../core/secret_store.dart';

/// The Openote app registration in Microsoft Entra.
///
/// **Public by design, and safe to have in the open.** A client id is an
/// identifier, not a credential — it says which app is asking, never that the
/// asker is allowed. The GitHub CLI and VS Code both ship theirs the same way.
/// Sign-in is protected by PKCE and by the redirect being loopback-only.
/// Overridable with `--dart-define=OPENOTE_GRAPH_CLIENT_ID=…` so somebody
/// building their own copy, or a fork, can point it at their own registration
/// without patching source.
const String kGraphClientId = String.fromEnvironment(
  'OPENOTE_GRAPH_CLIENT_ID',
  defaultValue: 'b63c56e3-9438-4917-9bc1-76ceda9fc23f',
);

/// True once a real registration has been compiled in.
bool get graphSignInConfigured =>
    kGraphClientId != '00000000-0000-0000-0000-000000000000' &&
    kGraphClientId.isNotEmpty;

/// `common` — both work-or-school and personal accounts.
///
/// A student's notebook is very often on a **university** account, which is a
/// work account, and just as often on a personal one. Anything narrower here
/// locks out half the audience, which is why the registration is
/// "Any Entra ID Tenant + Personal Microsoft accounts".
const String kGraphAuthority = 'https://login.microsoftonline.com/common';

/// What Openote asks to be allowed to do.
///
/// **The least it can possibly ask for, and nothing whatsoever about the
/// person.**
///
/// `Notes.Read` reads the notebooks and does nothing else: no writing back, no
/// mail, no files, no calendar, no contacts. `offline_access` grants no data at
/// all — it only allows a refresh token, so a long import can outlive the
/// one-hour access token instead of stopping halfway to ask for a password
/// again.
///
/// **`openid` and `profile` were here and have been removed.** They were added
/// so the app could show *"signed in as …"*, on the reasoning that the
/// commonest setup mistake is having two Microsoft accounts and importing from
/// the wrong one. The owner's objection was the right one: *"I dont personally
/// see why we need to collect that data if we are just reading a notebook."*
///
/// Nothing is lost, because the identity was never the thing that answered the
/// question. Microsoft's own account picker shows which account is being
/// chosen (`prompt=select_account`, always), and the notebook list that comes
/// back names the notebooks — which is a far better signal than an email
/// address, since it is the notebooks the student is actually looking for. For
/// a remembered sign-in the picker offers "use a different account", which
/// solves the same problem without knowing who anybody is.
///
/// So Openote never learns the student's name, username, email or user id, and
/// the consent screen has two lines on it instead of four.
const List<String> kGraphScopes = ['Notes.Read', 'offline_access'];

/// Where the refresh token lives: the OS credential store, never a file.
const String _kRefreshKey = 'onenote.graph.refresh';

/// A signed-in session.
class GraphSession {
  GraphSession({
    required this.accessToken,
    required this.expiresAt,
    this.refreshToken,
  });

  final String accessToken;
  final DateTime expiresAt;
  final String? refreshToken;

  /// Treated as expired a minute early, so a token cannot lapse *during* the
  /// request it was fetched for.
  bool get isFresh =>
      DateTime.now().isBefore(expiresAt.subtract(const Duration(minutes: 1)));
}

/// Why a sign-in did not finish. Every one of these is shown to a person, so
/// every one is a sentence rather than a code.
class GraphAuthException implements Exception {
  GraphAuthException(this.message, {this.details});
  final String message;
  final String? details;
  @override
  String toString() => details == null ? message : '$message ($details)';
}

/// Drives the sign-in and keeps the token fresh.
class GraphAuth {
  GraphAuth({HttpClient? client, this.clientId = kGraphClientId})
      : _client = client ?? HttpClient();

  final HttpClient _client;
  final String clientId;

  GraphSession? _session;
  GraphSession? get session => _session;

  /// Test seam: the browser is not opened during a test, and the loopback
  /// server is driven by the test itself.
  @visibleForTesting
  static Future<bool> Function(String url)? debugOpenBrowser;

  /// Test seam for the token endpoint, so the whole sign-in — loopback server,
  /// state check, code exchange — can run with no network and no account.
  /// Returns `(statusCode, jsonBody)`.
  @visibleForTesting
  static Future<(int, Map<String, dynamic>)> Function(
      Map<String, String> body)? debugTokenEndpoint;

  /// The PKCE challenge for a verifier, exposed so the hashing itself is
  /// checked against RFC 7636's own worked example rather than assumed.
  @visibleForTesting
  static String challengeFor(String verifier) => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');

  @visibleForTesting
  static String friendlyTokenError(String? code, String? description) =>
      _friendlyTokenError(code, description);

  /// A token that is good right now, signing in or refreshing as needed.
  Future<String> accessToken() async {
    final s = _session;
    if (s != null && s.isFresh) return s.accessToken;
    final refreshed = await _refreshFromStore();
    if (refreshed != null) return refreshed.accessToken;
    throw GraphAuthException(
        'You are not signed in to Microsoft any more. Sign in again to keep '
        'importing.');
  }

  /// Is there a stored sign-in to resume?
  bool get hasStoredSignIn => SecretStore.read(_kRefreshKey) != null;

  /// Forget the sign-in entirely.
  void signOut() {
    _session = null;
    SecretStore.delete(_kRefreshKey);
  }

  /// Run the whole browser sign-in.
  ///
  /// [onPrompt] is handed the URL actually opened, so the UI can offer it as
  /// something to copy when a browser does not appear — a headless or
  /// locked-down machine should not be a dead end.
  Future<GraphSession> signIn({
    void Function(String url)? onPrompt,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (!graphSignInConfigured) {
      throw GraphAuthException(
          'This build of Openote has no Microsoft sign-in set up.',
          details: 'OPENOTE_GRAPH_CLIENT_ID was not compiled in');
    }
    final verifier = _randomUrlSafe(64);
    final challenge = challengeFor(verifier);
    final state = _randomUrlSafe(24);

    // Port 0 asks the OS for any free port, which is what makes a registered
    // `http://localhost` work without reserving one.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    // **`localhost`, not `127.0.0.1`, and they are not interchangeable here.**
    //
    // Entra wildcards the PORT of a registered loopback redirect but matches
    // the host string exactly. The registration says `http://localhost`, so
    // sending the numeric form is rejected outright:
    //
    //     invalid_request: The provided value for the input parameter
    //     'redirect_uri' is not valid.
    //
    // Binding stays on the numeric loopback address, because that is an
    // address rather than a name and needs no resolver. The browser resolves
    // `localhost` to it — every desktop platform maps the name to the IPv4
    // loopback, and a browser that tries `::1` first falls back.
    final redirect = 'http://localhost:${server.port}';
    try {
      final url = Uri.parse('$kGraphAuthority/oauth2/v2.0/authorize').replace(
        queryParameters: {
          'client_id': clientId,
          'response_type': 'code',
          'redirect_uri': redirect,
          'response_mode': 'query',
          'scope': kGraphScopes.join(' '),
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'state': state,
          // Always show the picker. A machine with a signed-in work account
          // would otherwise silently import from the wrong one, which is
          // exactly the confusion this app's owner hit setting the app up.
          'prompt': 'select_account',
        },
      ).toString();

      onPrompt?.call(url);
      final opener = debugOpenBrowser ?? PlatformOpen.url;
      final opened = await opener(url);
      if (!opened) {
        throw GraphAuthException(
            'Openote could not open your browser to sign you in.',
            details: redirect);
      }

      final code = await _awaitCode(server, state).timeout(
        timeout,
        onTimeout: () => throw GraphAuthException(
            'The sign-in was not finished, so nothing was imported.'),
      );
      // **Before the exchange, and this is worth thirty seconds.**
      //
      // Leaving `await for` by returning cancels its subscription, and
      // cancelling an `HttpServer` subscription closes the server *gracefully*
      // — which waits for open connections to finish. The browser holds the
      // redirect connection open with keep-alive, so the close blocked until
      // the browser's own idle timeout, roughly half a minute, and it blocked
      // BEFORE the token request could be made. That was the whole of "it
      // takes about another 30s to auth after doing the sign in".
      //
      // Forcing it here rather than relying on the `finally` below, because
      // the `finally` runs after the exchange and the point is to get the
      // exchange started.
      await server.close(force: true);
      final session = await _exchange(
        body: {
          'client_id': clientId,
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': redirect,
          'code_verifier': verifier,
          'scope': kGraphScopes.join(' '),
        },
      );
      _session = session;
      final refresh = session.refreshToken;
      if (refresh != null) await SecretStore.write(_kRefreshKey, refresh);
      return session;
    } finally {
      // Always, on every path: a web server left listening after a failed
      // sign-in is a port held open for the life of the process.
      await server.close(force: true);
    }
  }

  /// Wait for the browser to come back, and answer it with a page a person can
  /// read rather than a blank screen.
  Future<String> _awaitCode(HttpServer server, String state) async {
    await for (final request in server) {
      final q = request.uri.queryParameters;
      final error = q['error_description'] ?? q['error'];
      final code = q['code'];
      final gotState = q['state'];

      String body;
      if (error != null) {
        body = _page('Openote could not sign you in',
            'Microsoft said: $error\n\nYou can close this tab.');
      } else if (code == null) {
        // Browsers ask for /favicon.ico off their own bat; that is not the
        // redirect and must not end the wait.
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        continue;
      } else if (gotState != state) {
        // The one check that makes the loopback safe against another program
        // on this machine firing a request at the port mid-flow.
        body = _page('Openote could not sign you in',
            'That sign-in did not match the one Openote started.');
      } else {
        body = _page('You are signed in',
            'You can close this tab and go back to Openote.');
      }

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        // Tell the browser not to keep the connection alive. Half of the fix
        // above: a connection the browser is entitled to reuse is one the
        // server has to wait on.
        ..headers.set(HttpHeaders.connectionHeader, 'close')
        ..persistentConnection = false
        ..write(body);
      await request.response.close();

      if (error != null) throw GraphAuthException(error);
      // The state is checked TWICE — here and in the branch above — and both
      // are deliberate. Neutralising either one alone leaves the other holding
      // the property, which is exactly what belt and braces means; a mutation
      // run confirmed it takes removing both to let a foreign code through.
      // Do not delete one as redundant.
      if (code != null && gotState == state) return code;
      throw GraphAuthException('That sign-in did not match the one Openote '
          'started, so it was refused.');
    }
    throw GraphAuthException('The sign-in window closed before it finished.');
  }

  /// Swap a stored refresh token for a live one.
  Future<GraphSession?> _refreshFromStore() async {
    final refresh = SecretStore.read(_kRefreshKey);
    if (refresh == null) return null;
    try {
      final s = await _exchange(body: {
        'client_id': clientId,
        'grant_type': 'refresh_token',
        'refresh_token': refresh,
        'scope': kGraphScopes.join(' '),
      });
      _session = s;
      final next = s.refreshToken;
      if (next != null) await SecretStore.write(_kRefreshKey, next);
      return s;
    } on GraphAuthException {
      // A refresh token that no longer works is not an error to report, it is
      // a sign-in that has ended: drop it so the next attempt asks properly
      // rather than failing the same way for ever.
      SecretStore.delete(_kRefreshKey);
      return null;
    }
  }

  Future<GraphSession> _exchange({required Map<String, String> body}) async {
    final fake = debugTokenEndpoint;
    if (fake != null) {
      final (status, json) = await fake(body);
      return _sessionFrom(status, json);
    }
    final uri = Uri.parse('$kGraphAuthority/oauth2/v2.0/token');
    late HttpClientResponse response;
    late String text;
    try {
      final req = await _client.postUrl(uri);
      req.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      req.write(body.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&'));
      response = await req.close();
      text = await response.transform(utf8.decoder).join();
    } on SocketException catch (e) {
      throw GraphAuthException(
          'Openote could not reach Microsoft. Check your internet connection '
          'and try again.',
          details: '$e');
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw GraphAuthException('Microsoft sent something Openote could not read.',
          details: 'HTTP ${response.statusCode}');
    }
    return _sessionFrom(response.statusCode, json);
  }

  GraphSession _sessionFrom(int status, Map<String, dynamic> json) {
    if (status != 200) {
      throw GraphAuthException(
          _friendlyTokenError(
              json['error'] as String?, json['error_description'] as String?),
          details: '${json['error']}: ${json['error_description']}');
    }
    final expires = (json['expires_in'] as num?)?.toInt() ?? 3600;
    return GraphSession(
      accessToken: json['access_token'] as String? ?? '',
      expiresAt: DateTime.now().add(Duration(seconds: expires)),
      refreshToken: json['refresh_token'] as String?,
    );
  }

  /// The failures a student can actually do something about, in words.
  static String _friendlyTokenError(String? code, String? description) {
    // Checked BEFORE the code, because Microsoft returns this one under
    // several different codes and it is the only failure here a student
    // cannot fix alone. Read from the code alone it arrives as
    // `invalid_grant`, which would tell them their sign-in had expired and
    // send them round the loop again for ever.
    if (description != null && description.contains('AADSTS65001')) {
      return 'Your organisation has not approved Openote yet. A university or '
          'workplace account may need an administrator to allow it.';
    }
    switch (code) {
      case 'invalid_grant':
        return 'That sign-in has expired. Please sign in again.';
      case 'invalid_client':
      case 'unauthorized_client':
        return 'Microsoft would not accept this copy of Openote. This is a '
            'problem with the app rather than with your account — please '
            'report it.';
      case 'consent_required':
      case 'interaction_required':
        return 'Microsoft needs you to approve access before Openote can read '
            'your notebooks.';
      case 'access_denied':
        // The commonest "failure" of all, and not a failure: they said no.
        return 'Openote was not given permission to read your notebooks.';
      default:
        return 'Microsoft would not complete the sign-in.';
    }
  }

  static String _randomUrlSafe(int bytes) {
    final rnd = Random.secure();
    final out = List<int>.generate(bytes, (_) => rnd.nextInt(256));
    return base64Url.encode(out).replaceAll('=', '');
  }

  static String _page(String heading, String body) => '<!doctype html>'
      '<html><head><meta charset="utf-8"><title>Openote</title></head>'
      '<body style="font-family:system-ui,sans-serif;max-width:32rem;'
      'margin:4rem auto;padding:0 1rem;line-height:1.5">'
      '<h1 style="font-size:1.4rem">${_escape(heading)}</h1>'
      '<p style="white-space:pre-wrap">${_escape(body)}</p></body></html>';

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
