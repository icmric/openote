// Creating a repository on GitHub, and pushing to it, from inside the app.
//
// The ask: "I want to be able to create and push my notebook to github from
// within the app, no extra steps required outside the app."
//
// Two things here are worth testing and neither is testable by inspection.
//
// The FIRST is the credential helper. The token is handed to git as a shell
// snippet inside a config value, evaluated by whatever `sh` git found — on
// Windows that is the one bundled with Git for Windows, on a Mac it is the
// system one. Quoting that survives reading is not quoting that survives `sh`,
// so the test runs `git credential fill` for real and asserts the token comes
// back out the other end.
//
// The SECOND is the API. These run against a real local HttpServer rather than
// a mock, because the failures worth catching are in headers, status codes and
// JSON shapes — a mock would only agree with whatever this code already
// assumes about them.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/sync/git_sync.dart';
import 'package:openote/sync/github_api.dart';

void main() {
  group('naming a repository after a notebook', () {
    // GitHub silently rewrites a name it does not like, so a notebook called
    // "Year 12 — Physics" lands at a URL the app would otherwise be reporting
    // wrongly.
    test('spaces and punctuation become hyphens', () {
      expect(repoNameFor('Year 12 — Physics'), 'Year-12-Physics');
      expect(repoNameFor('Notes: term 1 (draft)'), 'Notes-term-1-draft');
    });

    test('runs of separators collapse, and edges are trimmed', () {
      expect(repoNameFor('  ...Maths!!!   Revision...  '), 'Maths-Revision');
    });

    test('a name made entirely of punctuation still produces something', () {
      // A notebook titled in a script this strips entirely would otherwise ask
      // GitHub to create a repository with an empty name.
      expect(repoNameFor('日本語のノート'), 'openote-notebook');
      expect(repoNameFor('***'), 'openote-notebook');
    });

    test('a name GitHub already accepts is left alone', () {
      expect(repoNameFor('my-notes'), 'my-notes');
      expect(repoNameFor('CS_101.notes'), 'CS_101.notes');
    });
  });

  group('talking to the API', () {
    late HttpServer server;
    late String base;
    final requests = <HttpRequest>[];
    final bodies = <String>[];

    /// A stand-in for GitHub that answers however a test needs it to.
    Future<void> serve(
        int status, Object? body, {Map<String, String>? headers}) async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://${server.address.host}:${server.port}';
      server.listen((req) async {
        requests.add(req);
        bodies.add(await utf8.decoder.bind(req).join());
        req.response.statusCode = status;
        headers?.forEach(req.response.headers.set);
        req.response.write(body is String ? body : jsonEncode(body));
        await req.response.close();
      });
    }

    setUp(() {
      requests.clear();
      bodies.clear();
    });

    tearDown(() async => server.close(force: true));

    test('the token is sent as a bearer, on the Authorization header',
        () async {
      // Not as a query parameter, which would put it in server logs.
      await serve(200, {'login': 'icmric'});
      final who = await GitHubApi('ghp_secret', baseUrl: base).login();
      expect(who, 'icmric');
      expect(requests.single.headers.value('authorization'),
          'Bearer ghp_secret');
      expect(requests.single.uri.query, isEmpty);
    });

    test('a bad token reports as "not connected", not as a crash', () async {
      await serve(401, {'message': 'Bad credentials'});
      expect(await GitHubApi('nope', baseUrl: base).login(), isNull);
    });

    test('creating a repository asks for a PRIVATE one by default', () async {
      // These are somebody's notes. A public repository of a student's
      // coursework, created by a default nobody read, is not a mistake to make
      // on their behalf.
      await serve(201, {
        'clone_url': 'https://github.com/icmric/Notes.git',
        'full_name': 'icmric/Notes',
      });
      final made = await GitHubApi('t', baseUrl: base).createRepo('Notes');
      expect(made.ok, isTrue);
      expect(made.cloneUrl, 'https://github.com/icmric/Notes.git');
      expect(made.fullName, 'icmric/Notes');

      final sent = jsonDecode(bodies.single) as Map;
      expect(sent['private'], isTrue, reason: 'private unless asked otherwise');
      expect(sent['name'], 'Notes');
      // auto_init would put a README commit on the remote, giving the first
      // push a second root to merge for a file nobody asked for.
      expect(sent['auto_init'], isFalse);
    });

    test('a public repository is only created when explicitly asked', () async {
      await serve(201, {'clone_url': 'u', 'full_name': 'f'});
      await GitHubApi('t', baseUrl: base).createRepo('N', private: false);
      expect((jsonDecode(bodies.single) as Map)['private'], isFalse);
    });

    test('a name that is already taken says so in words', () async {
      // GitHub's own body is `{"message":"Repository creation failed.",
      // "errors":[{"message":"name already exists on this account"}]}`, which
      // tells the user nothing about what to do next.
      await serve(422, {
        'message': 'Repository creation failed.',
        'errors': [
          {'message': 'name already exists on this account'}
        ]
      });
      final made = await GitHubApi('t', baseUrl: base).createRepo('Notes');
      expect(made.ok, isFalse);
      expect(made.error, contains('already have a repository'));
    });

    test('a token without the repo scope explains which permission', () async {
      await serve(403, {'message': 'Resource not accessible'});
      final made = await GitHubApi('t', baseUrl: base).createRepo('N');
      expect(made.error, contains('repo'));
    });

    test('an expired token blames the token, not the notebook', () async {
      await serve(401, {'message': 'Bad credentials'});
      final made = await GitHubApi('t', baseUrl: base).createRepo('N');
      expect(made.error, contains('token'));
    });

    test('a reply that is not JSON at all is survived', () async {
      // A captive portal or a proxy returning an HTML error page. This must
      // read as a failure, not throw out of the button handler.
      await serve(200, '<html>Sign in to the hotel wifi</html>');
      expect(await GitHubApi('t', baseUrl: base).login(), isNull);
    });

    test('no network is a message rather than an exception', () async {
      await serve(200, {});
      await server.close(force: true);
      final made =
          await GitHubApi('t', baseUrl: base).createRepo('N');
      expect(made.ok, isFalse);
      expect(made.error, contains('Could not reach GitHub'));
      // Re-bind so tearDown has something to close.
      await serve(200, {});
    });
  });

  group('handing the token to git', () {
    late Directory root;
    var haveGit = false;

    setUpAll(() async => haveGit = await GitSync.gitExecutable() != null);
    setUp(() => root = Directory.systemTemp.createTempSync('onote_ghpush_'));
    tearDown(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('THE CREDENTIAL HELPER ACTUALLY WORKS', () async {
      // The one that cannot be verified by reading. `git credential fill` runs
      // the configured helper and prints what it answered, so this drives the
      // exact arguments and environment a push would use and checks the token
      // comes out — on whichever shell this machine's git uses.
      if (!haveGit) return markTestSkipped('git not installed');
      final g = GitSync(root.path, token: 'ghp_the_secret_value');
      final git = (await GitSync.gitExecutable())!;

      final proc = await Process.start(
          git, [...g.debugAuthArgs, 'credential', 'fill'],
          workingDirectory: root.path, environment: g.debugEnv);
      proc.stdin.write('protocol=https\nhost=github.com\n\n');
      await proc.stdin.close();
      final out = await proc.stdout.transform(utf8.decoder).join();
      await proc.exitCode;

      expect(out, contains('username=x-access-token'));
      expect(out, contains('password=ghp_the_secret_value'),
          reason: 'the shell snippet must survive this platform\'s sh');
    });

    test('the token is NOT on the command line', () {
      // An argument is visible to every other process on the machine for as
      // long as git runs — `ps` on Linux and macOS, Task Manager on Windows.
      // The environment is not.
      const g = GitSync('/anywhere', token: 'ghp_the_secret_value');
      expect(g.debugAuthArgs.join(' '), isNot(contains('ghp_the_secret_value')));
      expect(g.debugEnv.values, contains('ghp_the_secret_value'));
    });

    test('a system credential manager cannot answer first', () async {
      // Config helpers are a LIST. Without clearing it, Git Credential Manager
      // on Windows or osxkeychain on a Mac answers with a stale github.com
      // credential and the push fails with a confusing 403.
      const g = GitSync('/anywhere', token: 't');
      expect(g.debugAuthArgs.take(2), ['-c', 'credential.helper=']);
    });

    test('with no token nothing is added at all', () {
      // Anyone with SSH keys or a working credential manager must be left
      // exactly as they were.
      expect(const GitSync('/anywhere').debugAuthArgs, isEmpty);
      expect(const GitSync('/anywhere', token: '').debugAuthArgs, isEmpty);
    });

    test('git never waits at a prompt nobody can see', () {
      // Openote's git has no terminal. A remote asking for a password would
      // otherwise block until the 90-second timeout, and the app looks hung.
      expect(const GitSync('/anywhere').debugEnv['GIT_TERMINAL_PROMPT'], '0');
    });

    test('a token does not break an ordinary sync', () async {
      // The auth arguments are prepended to EVERY git call, including the ones
      // that never touch a network. If they were malformed, `git add` would
      // start failing and the notebook would stop committing locally.
      if (!haveGit) return markTestSkipped('git not installed');
      final bare = Directory('${root.path}/remote.git')..createSync();
      final git = (await GitSync.gitExecutable())!;
      await Process.run(git, ['init', '--bare', '--initial-branch=main'],
          workingDirectory: bare.path);

      final dir = Directory('${root.path}/a.onotebook')
        ..createSync(recursive: true);
      final g = GitSync(dir.path, token: 'ghp_irrelevant_here');
      await g.init();
      await Process.run(git, ['config', 'user.email', 't@openote.invalid'],
          workingDirectory: dir.path);
      await Process.run(git, ['config', 'user.name', 'Openote Test'],
          workingDirectory: dir.path);
      await g.setRemote(bare.path);
      File('${dir.path}/ops/a.oplog').createSync(recursive: true);
      File('${dir.path}/ops/a.oplog').writeAsStringSync('notes');

      final r = await g.syncOnce(message: 'with a token set');
      expect(r.ok, isTrue, reason: r.message);
    });
  });
}
