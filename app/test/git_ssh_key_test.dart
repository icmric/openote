// Signing in to a git server with a key of your own choosing.
//
// Issue #10: *"It would be great if it was possible to explicitly use other
// ssh keys for git, so for example if you have a separate git user (eg on self
// hosted Forgejo) for your notes."* For somebody whose default key belongs to
// a different account this is not a convenience — without it, sync does not
// work at all.
//
// The risky part is not the feature, it is the QUOTING. `core.sshCommand` is a
// string git hands to a shell, so a Windows path full of backslashes is a
// string full of escape characters, and a home directory named after a person
// has a space in it. Both are the common case, not the exotic one.
//
// Those two are about WORD-SPLITTING, and double quotes answer them — which
// is what this file originally tested, and why it missed the third thing.
// Double quotes do not stop EXPANSION. `$(…)`, backticks and `$VAR` are all
// evaluated inside them, so a key path containing `$(…)` was run as a command
// by the shell git spawned (GitHub #24). The path is chosen from a file
// picker, so the payload has to be a FILENAME somebody selects — narrow, and
// still a shell injection.
//
// The fix is POSIX single quotes, inside which nothing is expanded. The last
// group below drives real git and real ssh and reads back the path ssh
// actually tried to open, which is precisely the step the old test said in
// its own comment that it could not reach: *"It does not prove what ssh
// finally receives; that would need a server to connect to."* It does not —
// ssh names the identity file before it fails to connect, so a closed port on
// loopback is enough.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:openote/state/app_state.dart';
import 'package:openote/store/repository.dart';
import 'package:openote/sync/git_sync.dart';

import 'support/sqlite.dart';

void main() {
  group('the path handed to git', () {
    test('backslashes become forward slashes', () {
      // git splits this value with shell rules, where a backslash ESCAPES the
      // next character. A Windows path arrives mangled unless it is converted,
      // and ssh on Windows accepts forward slashes perfectly well.
      expect(GitSync.sshKeyArg(r'C:\Users\Eric\.ssh\id_ed25519'),
          "'C:/Users/Eric/.ssh/id_ed25519'");
    });

    test('a path is trimmed, because a pasted one often is not', () {
      expect(GitSync.sshKeyArg('  /home/me/.ssh/id_ed25519  '),
          "'/home/me/.ssh/id_ed25519'");
    });

    test('a double quote needs no escaping inside single quotes', () {
      // Legal on Linux and pathological anywhere. It used to be escaped
      // because the wrapper was a double quote; inside single quotes it is an
      // ordinary character and escaping it would CORRUPT the path.
      expect(GitSync.sshKeyArg('/home/me/we"ird/id'), '\'/home/me/we"ird/id\'');
    });

    test('a single quote is closed, escaped and reopened', () {
      // The one character single quotes cannot contain. `'` becomes `'\''`:
      // end the quoted run, an escaped quote, start a new run.
      expect(GitSync.sshKeyArg("/home/o'brien/.ssh/id"),
          r"'/home/o'\''brien/.ssh/id'");
    });

    test('and NOTHING in the path is expanded', () {
      // GitHub #24. Each of these is evaluated inside double quotes and inert
      // inside single ones, which is the whole of the fix.
      for (final hostile in [
        r'/tmp/$(touch pwned).key',
        '/tmp/`id`.key',
        r'/tmp/$HOME.key',
        r'/tmp/${HOME}.key',
      ]) {
        expect(GitSync.sshKeyArg(hostile), "'$hostile'",
            reason: 'carried through verbatim: $hostile');
      }
    });
  });

  group('the arguments', () {
    test('are absent entirely when no key is chosen', () {
      // Whoever already has a working agent or `~/.ssh/config` must be left
      // exactly as they were.
      expect(const GitSync('/anywhere').debugSshArgs, isEmpty);
      expect(const GitSync('/anywhere', sshKey: '').debugSshArgs, isEmpty);
      expect(const GitSync('/anywhere', sshKey: '   ').debugSshArgs, isEmpty);
    });

    test('carry IdentitiesOnly, without which the key may never be tried', () {
      // `-i` only ADDS a key to the set ssh offers. An agent holding several
      // offers its own first, and a server that cuts off after too many
      // attempts never reaches this one — "too many authentication failures"
      // from a key that is provably correct, which is the exact hole the
      // person asking for this is already in.
      final args = const GitSync('/anywhere', sshKey: '/home/me/k').debugSshArgs;
      expect(args.first, '-c');
      expect(args.last, contains('IdentitiesOnly=yes'));
    });

    test('quote the path, because a home directory usually has a space', () {
      final args = const GitSync('/anywhere',
              sshKey: r'C:\Users\Eric McClelland\.ssh\notes_key')
          .debugSshArgs;
      expect(
          args.last,
          "core.sshCommand=ssh -i 'C:/Users/Eric McClelland/.ssh/notes_key' "
          '-o IdentitiesOnly=yes');
    });

    test('and the caller does not add quotes of its own', () {
      // [GitSync.sshKeyArg] returns a complete shell word. Wrapping it again
      // would nest the quoting and hand ssh a path with quotes in it.
      final args =
          const GitSync('/anywhere', sshKey: '/home/me/k').debugSshArgs;
      expect(args.last, isNot(contains('"')));
      expect(args.last, contains("-i '/home/me/k'"));
    });
  });

  group('git itself', () {
    late Directory root;
    var haveGit = false;

    setUpAll(() async => haveGit = await GitSync.gitExecutable() != null);
    setUp(() => root = Directory.systemTemp.createTempSync('onote_sshkey_'));
    tearDown(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('accepts the value intact, space and all', () async {
      // **What this proves, and what it does not.**
      //
      // It drives the real argument list through the real git and asks git
      // what it ended up holding, so it covers the layers where a quoting
      // mistake corrupts things: `Process.run`'s argument encoding — which on
      // Windows is a single command STRING the child re-splits — and git's own
      // config parsing.
      //
      // It does not prove what ssh finally receives; that would need a server
      // to connect to. The step left is ordinary POSIX word-splitting of a
      // double-quoted argument, and the value asserted above is its textbook
      // form.
      if (!haveGit) return markTestSkipped('git not installed');
      const key = r'C:\Users\Eric McClelland\.ssh\notes_key';
      const g = GitSync('/anywhere', sshKey: key);
      final git = (await GitSync.gitExecutable())!;

      final r = await Process.run(
          git, [...g.debugSshArgs, 'config', '--get', 'core.sshCommand'],
          workingDirectory: root.path);

      expect(r.exitCode, 0, reason: 'git accepted the override');
      expect(
          '${r.stdout}'.trim(),
          "ssh -i 'C:/Users/Eric McClelland/.ssh/notes_key' "
          '-o IdentitiesOnly=yes');
    });

    /// **What ssh finally opened**, which is the step the test above cannot
    /// reach on its own.
    ///
    /// No server is needed after all: ssh names the identity file in a
    /// warning BEFORE it fails to connect, so a closed port on loopback gets
    /// the whole chain — Process.run's argument encoding, git's config
    /// parsing, the shell git spawns, and ssh's own command line — to report
    /// what it ended up with. Null when git or ssh is missing, or when the
    /// attempt did not get far enough to say.
    Future<String?> identityFileSshOpened(String key) async {
      final g = GitSync('/anywhere', sshKey: key);
      final git = (await GitSync.gitExecutable())!;
      final r = await Process.run(
        git,
        [...g.debugSshArgs, 'ls-remote', 'ssh://git@127.0.0.1:1/x'],
        workingDirectory: root.path,
      ).timeout(const Duration(seconds: 30),
          onTimeout: () => ProcessResult(0, -1, '', ''));
      final line = '${r.stderr}'
          .split('\n')
          .where((l) => l.contains('Identity file'))
          .firstOrNull;
      if (line == null) return null;
      // `Warning: Identity file <path> not accessible: …`
      final from = line.indexOf('Identity file ') + 'Identity file '.length;
      final to = line.indexOf(' not accessible');
      return to > from ? line.substring(from, to) : null;
    }

    test('ssh receives a path with a space whole', () async {
      if (!haveGit) return markTestSkipped('git not installed');
      const key = '/nonexistent/Eric McClelland/.ssh/notes_key';
      final got = await identityFileSshOpened(key);
      if (got == null) return markTestSkipped('ssh did not report a path');
      expect(got, key, reason: 'the space did not split it into two words');
    });

    test('ssh receives a hostile path LITERALLY, and nothing runs', () async {
      // GitHub #24, end to end. Before the fix this created the marker file
      // and ssh reported `/nonexistent/key` — the substitution had already
      // happened. `touch` is the whole payload: harmless, and its effect is
      // observable, which is what makes the claim checkable rather than
      // arguable.
      if (!haveGit) return markTestSkipped('git not installed');
      final marker =
          '${root.path}${Platform.pathSeparator}INJECTED'.replaceAll(r'\', '/');
      final key = '/nonexistent/\$(touch $marker)key';

      final got = await identityFileSshOpened(key);
      expect(File(marker).existsSync(), isFalse,
          reason: 'the shell ran the command substitution in the key path');
      if (got == null) return markTestSkipped('ssh did not report a path');
      expect(got, key, reason: 'ssh got the path as written');
    });

    test('and nothing is put in .git/config, which is replicated', () async {
      // The notebook directory syncs. A key path that is right on this machine
      // is wrong on every other one — the same reason the token is kept out.
      if (!haveGit) return markTestSkipped('git not installed');
      final git = (await GitSync.gitExecutable())!;
      await Process.run(git, ['init'], workingDirectory: root.path);
      final g = GitSync(root.path, sshKey: '/home/me/.ssh/notes_key');
      await g.commitAll('anything');

      final cfg = File('${root.path}/.git/config');
      expect(cfg.existsSync(), isTrue);
      expect(cfg.readAsStringSync(), isNot(contains('sshCommand')));
      expect(cfg.readAsStringSync(), isNot(contains('notes_key')));
    });
  });

  group('which addresses offer the control', () {
    test('the two shapes git accepts for ssh', () {
      expect(isSshRemote('ssh://git@notes.example.com/eric/notes.git'), isTrue);
      expect(isSshRemote('git@notes.example.com:eric/notes.git'), isTrue);
    });

    test('but not https, where a key file means nothing', () {
      expect(isSshRemote('https://github.com/eric/notes.git'), isFalse);
      expect(isSshRemote('http://example.com/notes.git'), isFalse);
      expect(isSshRemote(''), isFalse);
    });

    test('and not a Windows path handed in as a local remote', () {
      // `C:/Users/me/notes` has a colon in it. Requiring the colon to come
      // AFTER an `@` is what stops a drive letter reading as a hostname.
      expect(isSshRemote(r'C:\Users\me\notes'), isFalse);
      expect(isSshRemote('C:/Users/me/notes'), isFalse);
      expect(isSshRemote('/home/me/notes'), isFalse);
    });
  });

  group('the setting', () {
    var haveSqlite = false;
    setUpAll(() => haveSqlite = initSqliteForTests());

    test('survives closing and reopening the notebook, and does NOT sync',
        () async {
      // Setting a key used to run through `setGitEnabled`, which inits the
      // repo, rewrites .gitignore, commits and pushes. Choosing which key
      // you sign in with is not a reason to do any of that.
      if (!haveSqlite) return markTestSkipped('sqlite unavailable');
      AppState.syncLogEnabled = false;
      final tmp = Directory.systemTemp.createTempSync('onote_sshset_');
      final repo = await Repository.openAt(tmp);
      try {
        final nb = await repo.createNotebook('Notes');
        final app = AppState(repo)..notebookId = nb.id;
        app.setGitSshKey('/home/me/.ssh/notes_key');
        expect(app.gitSshKey, '/home/me/.ssh/notes_key');
        expect(app.gitEnabled, isFalse,
            reason: 'choosing which key to sign in with is not choosing to '
                'sync — routing this back through setGitEnabled would init '
                'the repo, commit and push on the spot');

        // Reopened: `reloadGit` is what every notebook-open path calls.
        app.reloadGit();
        expect(app.gitSshKey, '/home/me/.ssh/notes_key',
            reason: 'a setting that evaporates on reopen is not a setting');

        app.setGitSshKey(null);
        app.reloadGit();
        expect(app.gitSshKey, isNull, reason: 'and it can be taken back off');
        app.cancelPendingSave();
      } finally {
        AppState.syncLogEnabled = true;
        repo.dispose();
        try {
          tmp.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  });
}
