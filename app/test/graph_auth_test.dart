// Signing in to Microsoft.
//
// The whole flow runs here with no network and no account: the browser is
// replaced by a function that makes the redirect request itself, and the token
// endpoint by one that returns a canned answer. What is being pinned is the
// security-critical half — that the loopback listener cannot be talked into
// accepting a sign-in Openote did not start, and that PKCE is computed the way
// the specification says rather than the way it looked right.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openote/core/secret_store.dart';
import 'package:openote/onenote/graph_auth.dart';

/// Answer the loopback redirect the way a browser would.
Future<void> hitRedirect(String authorizeUrl,
    {String? code = 'THE-CODE', String? state, String? error}) async {
  final url = Uri.parse(authorizeUrl);
  final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
  final query = <String, String>{
    if (code != null) 'code': code,
    'state': state ?? url.queryParameters['state']!,
    if (error != null) 'error': error,
  };
  final client = HttpClient();
  try {
    final req = await client.getUrl(redirect.replace(queryParameters: query));
    final res = await req.close();
    await res.drain<void>();
  } finally {
    client.close(force: true);
  }
}

void main() {
  setUp(() {
    SecretStore.debugBackend = {};
  });

  tearDown(() {
    SecretStore.debugBackend = null;
    GraphAuth.debugOpenBrowser = null;
    GraphAuth.debugTokenEndpoint = null;
  });

  group('PKCE', () {
    test('the challenge matches RFC 7636 worked example', () {
      // From RFC 7636 Appendix B. Checked against the specification rather
      // than against this implementation, so a plausible-but-wrong hashing
      // (hex instead of base64url, padding left on) cannot pass.
      expect(
        GraphAuth.challengeFor(
            'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('the challenge is url-safe and unpadded', () {
      final c = GraphAuth.challengeFor('some-verifier-value');
      expect(c, isNot(contains('=')));
      expect(c, isNot(contains('+')));
      expect(c, isNot(contains('/')));
    });
  });

  group('the loopback listener', () {
    test('a sign-in Openote started is completed', () async {
      final auth = GraphAuth();
      GraphAuth.debugOpenBrowser = (url) async {
        unawaited(hitRedirect(url));
        return true;
      };
      GraphAuth.debugTokenEndpoint = (body) async {
        // The exchange must present the verifier, which is what proves this is
        // the same app that began the flow.
        expect(body['code'], 'THE-CODE');
        expect(body['code_verifier'], isNotEmpty);
        expect(body['grant_type'], 'authorization_code');
        return (200, {'access_token': 'AT', 'expires_in': 3600});
      };
      final session = await auth.signIn();
      expect(session.accessToken, 'AT');
      expect(session.isFresh, isTrue);
    });

    test('REFUSES a code whose state is not the one it issued', () async {
      // The attack this stops: anything else on the machine can reach a
      // loopback port, so a code arriving without the state Openote generated
      // must not be accepted.
      final auth = GraphAuth();
      GraphAuth.debugOpenBrowser = (url) async {
        unawaited(hitRedirect(url, state: 'not-the-state-we-issued'));
        return true;
      };
      GraphAuth.debugTokenEndpoint = (body) async {
        fail('the code must never be exchanged when the state does not match');
      };
      await expectLater(auth.signIn(), throwsA(isA<GraphAuthException>()));
    });

    test('a favicon request does not end the wait', () async {
      // Browsers fetch /favicon.ico unprompted. Treating the first request as
      // the redirect would abandon the sign-in before the user finished it.
      final auth = GraphAuth();
      GraphAuth.debugOpenBrowser = (url) async {
        unawaited(() async {
          final redirect =
              Uri.parse(Uri.parse(url).queryParameters['redirect_uri']!);
          final client = HttpClient();
          final req =
              await client.getUrl(redirect.replace(path: '/favicon.ico'));
          await (await req.close()).drain<void>();
          client.close(force: true);
          await hitRedirect(url);
        }());
        return true;
      };
      GraphAuth.debugTokenEndpoint = (body) async =>
          (200, {'access_token': 'AT', 'expires_in': 3600});
      final session = await auth.signIn();
      expect(session.accessToken, 'AT');
    });

    test('an error from Microsoft is surfaced, not swallowed', () async {
      final auth = GraphAuth();
      GraphAuth.debugOpenBrowser = (url) async {
        unawaited(hitRedirect(url, code: null, error: 'access_denied'));
        return true;
      };
      await expectLater(auth.signIn(), throwsA(isA<GraphAuthException>()));
    });

    test('a browser that will not open is reported', () async {
      final auth = GraphAuth();
      GraphAuth.debugOpenBrowser = (url) async => false;
      await expectLater(
          auth.signIn(),
          throwsA(isA<GraphAuthException>().having((e) => e.message, 'message',
              contains('could not open your browser'))));
    });

    test('the redirect is loopback, and asks which account', () async {
      String? seen;
      final auth = GraphAuth();
      GraphAuth.debugOpenBrowser = (url) async {
        seen = url;
        unawaited(hitRedirect(url));
        return true;
      };
      GraphAuth.debugTokenEndpoint = (body) async =>
          (200, {'access_token': 'AT', 'expires_in': 3600});
      await auth.signIn();
      final q = Uri.parse(seen!).queryParameters;
      expect(q['redirect_uri'], startsWith('http://127.0.0.1:'));
      expect(q['code_challenge_method'], 'S256');
      // Without this a machine already signed in to a work account imports
      // from the wrong one silently.
      expect(q['prompt'], 'select_account');
      expect(q['scope'], contains('Notes.Read'));
      // Data minimisation, pinned: Openote asks for the notebooks and a
      // refresh token, and learns nothing about the person. Adding an
      // identity scope back should have to be a deliberate act that breaks a
      // test, not something that drifts in.
      expect(q['scope'], isNot(contains('profile')));
      expect(q['scope'], isNot(contains('openid')));
      expect(q['scope'], isNot(contains('email')));
      expect(q['scope'], isNot(contains('User.Read')));
    });
  });

  group('the stored sign-in', () {
    test('a refresh token is kept in the credential store, not a file',
        () async {
      final auth = GraphAuth();
      GraphAuth.debugOpenBrowser = (url) async {
        unawaited(hitRedirect(url));
        return true;
      };
      GraphAuth.debugTokenEndpoint = (body) async => (
            200,
            {'access_token': 'AT', 'expires_in': 3600, 'refresh_token': 'RT'}
          );
      await auth.signIn();
      expect(auth.hasStoredSignIn, isTrue);
      expect(SecretStore.debugBackend!.values, contains('RT'));
    });

    test('signing out forgets it', () async {
      SecretStore.debugBackend!['onenote.graph.refresh'] = 'RT';
      final auth = GraphAuth();
      expect(auth.hasStoredSignIn, isTrue);
      auth.signOut();
      expect(auth.hasStoredSignIn, isFalse);
    });

    test('a refresh token that no longer works is dropped, not retried for '
        'ever', () async {
      SecretStore.debugBackend!['onenote.graph.refresh'] = 'STALE';
      final auth = GraphAuth();
      GraphAuth.debugTokenEndpoint = (body) async =>
          (400, {'error': 'invalid_grant'});
      await expectLater(auth.accessToken(), throwsA(isA<GraphAuthException>()));
      // Kept, it would fail identically every time with no way back.
      expect(auth.hasStoredSignIn, isFalse);
    });

    test('a live refresh token produces a token without a browser', () async {
      SecretStore.debugBackend!['onenote.graph.refresh'] = 'GOOD';
      final auth = GraphAuth();
      GraphAuth.debugOpenBrowser =
          (url) async => fail('must not need the browser');
      GraphAuth.debugTokenEndpoint = (body) async {
        expect(body['grant_type'], 'refresh_token');
        return (200, {'access_token': 'FRESH', 'expires_in': 3600});
      };
      expect(await auth.accessToken(), 'FRESH');
    });
  });

  group('expiry', () {
    test('a token about to lapse is not treated as fresh', () {
      // A minute of headroom, so a token cannot expire DURING the request it
      // was fetched for.
      final nearly = GraphSession(
          accessToken: 'x',
          expiresAt: DateTime.now().add(const Duration(seconds: 30)));
      expect(nearly.isFresh, isFalse);
      final fine = GraphSession(
          accessToken: 'x',
          expiresAt: DateTime.now().add(const Duration(minutes: 30)));
      expect(fine.isFresh, isTrue);
    });
  });

  group('what a person is told', () {
    test('the failures that matter each get their own sentence', () {
      expect(GraphAuth.friendlyTokenError('invalid_grant', null),
          contains('sign in again'));
      expect(GraphAuth.friendlyTokenError('access_denied', null),
          contains('not given permission'));
      expect(GraphAuth.friendlyTokenError('invalid_client', null),
          contains('problem with the app'));
    });

    test('a university tenant that has not approved the app says so', () {
      // AADSTS65001 is the one a student cannot fix alone, so it must not read
      // as "something went wrong".
      final msg = GraphAuth.friendlyTokenError(
          'invalid_grant', 'AADSTS65001: The user or administrator has not '
              'consented to use the application');
      expect(msg, contains('administrator'));
    });

    test('no message is a bare error code', () {
      for (final code in ['invalid_grant', 'access_denied', 'mystery_error']) {
        final msg = GraphAuth.friendlyTokenError(code, null);
        expect(msg, isNot(contains(code)));
        expect(msg.endsWith('.'), isTrue, reason: '"$msg" should be a sentence');
      }
    });
  });

}
