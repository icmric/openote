import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/models.dart';

/// Syncing a notebook through a git remote.
///
/// **Why this fits, and what it is allowed to touch.** A notebook is two
/// things on disk: a `.onote` SQLite container and a `.onotebook` directory of
/// per-device op logs, blobs and media. Only the SECOND goes into git, and
/// that is not a preference — ADR-0006 §3 makes the container a local cache
/// that is never synced, because it is a WAL database rewritten on every save.
/// Committing one would put a large opaque binary into every commit, and two
/// machines pulling each other's copy is the corruption case the whole op-log
/// design exists to avoid.
///
/// The logs are the opposite, and this is the part that makes git a genuinely
/// good transport rather than a clever one: they are APPEND-ONLY and there is
/// ONE FILE PER DEVICE. Two machines therefore never write the same file, so a
/// merge is not a merge — both sides simply have files the other lacks. Blobs
/// are content-addressed, so the same is true of them. The conflict case that
/// makes git-as-sync miserable for ordinary documents does not arise.
///
/// **Credentials, and where they are not.** By default nothing here reads or
/// transmits a password: every remote operation runs the user's own `git`,
/// which uses whatever credential helper they already have. That covers people
/// with SSH keys or a working credential manager, and it was the whole story
/// until "no extra steps required outside the app" — creating a repository on
/// GitHub needs a token, and a token that can create a repository can also
/// push, so [token] carries it through to git as well.
///
/// When it is set, it is passed through the ENVIRONMENT to an inline
/// credential helper, never on the command line and never into `.git/config`.
/// Both of the obvious shortcuts leak: a token in the remote URL
/// (`https://<token>@github.com/…`) is written to a config file that gets
/// copied between machines and pasted into bug reports, and a token in an
/// `-c http.extraHeader=…` argument is visible to every other process on the
/// machine for as long as git runs. The environment is neither.
class GitSync {
  const GitSync(this.dir, {this.token});

  /// The `.onotebook` directory. The repository root is this directory itself,
  /// so a notebook is a repository and nothing outside it is ever staged.
  final String dir;

  /// A GitHub token to authenticate remote operations with, when the user has
  /// connected an account. Null means "use whatever git is already set up
  /// with", which is the right answer for SSH remotes and for anyone who has
  /// their own credential helper.
  final String? token;

  /// The environment variable the helper reads the token out of.
  static const _tokenVar = 'OPENOTE_GIT_TOKEN';

  /// Arguments that make git authenticate as [token], for one invocation.
  ///
  /// The empty `credential.helper=` first is load-bearing: config helpers are
  /// a LIST, and without clearing it a system-wide manager (Git Credential
  /// Manager on Windows, osxkeychain on a Mac) answers first with a stale
  /// credential for github.com and the push fails with a confusing 403.
  /// The auth arguments, for the test that checks they actually work.
  ///
  /// Exposed because the risky part of this is SHELL QUOTING inside a config
  /// value, evaluated by whatever `sh` git found — and that is not something
  /// to be confident about by reading. A test drives `git credential fill`
  /// with exactly these and asserts the token comes back out.
  List<String> get debugAuthArgs => _authArgs;

  /// The environment those arguments need, for the same test.
  Map<String, String> get debugEnv => _env;

  List<String> get _authArgs => token == null || token!.isEmpty
      ? const []
      : [
          '-c', 'credential.helper=',
          // `x-access-token` as the username is GitHub's convention for
          // token-as-password; any non-empty username works, but this one is
          // what shows up in their own docs and tooling.
          '-c',
          'credential.helper=!f() { test "\$1" = get && '
              'echo username=x-access-token && '
              'echo password=\$$_tokenVar; }; f',
        ];

  static String? _gitPath;
  static bool _looked = false;

  /// Where `git` is, or null when it is not installed.
  ///
  /// Resolved once. A machine without git is not an error — it is a machine
  /// where this feature is simply not offered.
  static Future<String?> gitExecutable() async {
    if (_looked) return _gitPath;
    _looked = true;
    for (final candidate in [
      'git',
      if (Platform.isWindows) r'C:\Program Files\Git\cmd\git.exe',
      if (Platform.isMacOS) '/usr/bin/git',
      if (Platform.isLinux) '/usr/bin/git',
    ]) {
      try {
        final r = await Process.run(candidate, ['--version']);
        if (r.exitCode == 0) return _gitPath = candidate;
      } catch (_) {
        // Not on PATH, or not executable. Try the next.
      }
    }
    return _gitPath = null;
  }

  /// For tests, which must not depend on how the machine is set up.
  static void debugSetGit(String? path) {
    _looked = true;
    _gitPath = path;
  }

  /// The environment every git call runs in.
  ///
  /// `GIT_TERMINAL_PROMPT=0` matters more than it looks. Openote's git has no
  /// terminal, so a remote that wants a password would otherwise sit waiting
  /// for input at a prompt nobody can see — the app appears to hang, and the
  /// 90-second timeout is the only thing that ends it. Off, git fails
  /// immediately with something the user can read instead.
  ///
  /// **The commit identity is Openote's own, always.** A machine that has
  /// never had git configured — which is every computer belonging to the
  /// student this app is for — refuses to commit at all: "Author identity
  /// unknown … Please tell me who you are." That is how "create and push"
  /// on a fresh Linux install created the repository (the API needs no git)
  /// and then synced nothing, forever: every cycle died at the commit step.
  /// These commits are transport records of log files, not authorship, so a
  /// fixed identity is not just a fallback — it also makes the history read
  /// the same from every device. Environment rather than `-c`, because a
  /// `pull --no-rebase` writes MERGE commits and those need an identity too.
  Map<String, String> get _env => {
        'GIT_TERMINAL_PROMPT': '0',
        'GIT_AUTHOR_NAME': 'Openote',
        'GIT_AUTHOR_EMAIL': 'openote@localhost',
        'GIT_COMMITTER_NAME': 'Openote',
        'GIT_COMMITTER_EMAIL': 'openote@localhost',
        if (token != null && token!.isNotEmpty) _tokenVar: token!,
      };

  Future<GitResult> _run(List<String> args, {Duration? timeout}) async {
    final git = await gitExecutable();
    if (git == null) {
      return const GitResult(-1, '', 'git is not installed on this computer');
    }
    try {
      final r = await Process.run(git, [..._authArgs, ...args],
              workingDirectory: dir, environment: _env)
          .timeout(timeout ?? const Duration(seconds: 90));
      return GitResult(r.exitCode, '${r.stdout}'.trim(), '${r.stderr}'.trim());
    } on ProcessException catch (e) {
      return GitResult(-1, '', e.message);
    } catch (e) {
      // A timeout is the important one: a push that is waiting for a password
      // on a terminal nobody can see would otherwise hang the app forever.
      return GitResult(-1, '', '$e');
    }
  }

  bool get exists => Directory(dir).existsSync();

  /// Is this directory already a git repository?
  bool get isRepo => Directory(p.join(dir, '.git')).existsSync();

  /// Make it one, and write the ignore rules that keep the container out.
  ///
  /// Idempotent: re-running on an existing repository refreshes the ignore
  /// file and does nothing else.
  Future<GitResult> init() async {
    if (!exists) await Directory(dir).create(recursive: true);
    if (!isRepo) {
      final r = await _run(['init']);
      if (!r.ok) return r;
      // `main`, because that is what every remote now defaults to and a
      // mismatch is the most common first-push failure.
      await _run(['symbolic-ref', 'HEAD', 'refs/heads/main']);
    }
    await File(p.join(dir, '.gitignore')).writeAsString(_gitignore);
    // COMMITTED, not merely written. Left untracked, the first pull from a
    // remote that already has one fails with "untracked working tree files
    // would be overwritten by merge" — which is what a second device joining
    // an existing notebook hits, every time, on the one operation that has to
    // work for the feature to be worth anything.
    //
    // And the result is PROPAGATED, not discarded. This used to return
    // success unconditionally, which buried the fresh-machine identity
    // failure (see [_env]) under a green light — the first symptom anyone
    // saw was a repository on GitHub with nothing in it.
    final committed = await commitAll('Openote: track this notebook');
    if (!committed.ok) return committed;
    return const GitResult(0, '', '');
  }

  /// The ignore file, written rather than assumed.
  ///
  /// `*.onote` is the load-bearing line: the container must never be committed
  /// (ADR-0006 §3). The rest are the transient files a running Openote leaves
  /// beside the logs.
  static const _gitignore = '''
# Openote — what belongs in git and what does not.
#
# The `.onote` container is a LOCAL CACHE (ADR-0006 §3): a WAL SQLite database
# rewritten on every save. Committing it would put a large opaque binary in
# every commit, and two machines pulling each other's copy is the exact
# corruption the op logs exist to prevent. The logs and blobs are append-only
# and content-addressed, so they merge without conflicts.
*.onote
*.onote-wal
*.onote-shm
*.part
.DS_Store
Thumbs.db

# Videos stay on the computer they were added to.
#
# GitHub rejects any single file over 100 MB outright, and one lecture
# recording is routinely larger than that — so a notebook that committed its
# videos would push fine until the day someone dropped a recording in, and
# then never push again. Worse, the rejection is permanent: the file is in the
# history by then, and deleting it later does not remove it from what every
# future clone downloads.
#
# The op log still records that the video is THERE, so the other device shows
# the block and says the file is missing rather than losing the reference.
# Delete this line for a notebook whose videos are small and worth syncing.
media/
''';

  /// Everything staged, committed. Returns a result whose [GitResult.noop] is
  /// true when there was nothing to commit — the common case on a timer.
  Future<GitResult> commitAll(String message) async {
    final add = await _run(['add', '-A']);
    if (!add.ok) return add;
    final status = await _run(['status', '--porcelain']);
    if (status.ok && status.stdout.isEmpty) {
      return const GitResult(0, '', '', noop: true);
    }
    return _run(['commit', '-m', message]);
  }

  /// Bring the other devices' logs in.
  ///
  /// `--no-rebase` deliberately. A rebase rewrites local commits, and these
  /// commits are append-only log data rather than a story anyone will read —
  /// a merge commit costs nothing and cannot lose a device's writes.
  ///
  /// `origin` is named rather than relying on an upstream, so the FIRST sync
  /// works: a repository that has just been created has no tracking branch and
  /// a bare `git pull` refuses.
  ///
  /// `--allow-unrelated-histories` is normally a footgun and here is exactly
  /// right. Point a second device at a notebook's remote and it starts from
  /// its own `git init`, so the two histories genuinely have no common
  /// ancestor — and their CONTENT genuinely does not overlap, because each
  /// device writes only its own append-only log and blobs are
  /// content-addressed. Without this, the second device's first push is
  /// rejected as non-fast-forward and the user is told to run git commands
  /// they should never have to know about. (Cloning avoids it too, and
  /// [clone] exists for people who join that way; this makes the other route
  /// work rather than fail.)
  Future<GitResult> pull() async => _run([
        'pull',
        '--no-rebase',
        '--no-edit',
        '--allow-unrelated-histories',
        'origin',
        // The BRANCH has to be named too, or git refuses with "you asked to
        // pull from the remote 'origin', but did not specify a branch".
        // The local branch name is the right one to send: a repository cloned
        // from a `master` remote is on `master`, and one this created is on
        // `main`. A remote that does not have it yet answers "couldn't find
        // remote ref", which reads as nothing-to-pull below.
        await currentBranch(),
      ]);

  /// The branch this working tree is on. `main` when git cannot say — a fresh
  /// repository with no commits reports nothing, and `main` is what [init]
  /// pointed HEAD at.
  Future<String> currentBranch() async {
    final r = await _run(['rev-parse', '--abbrev-ref', 'HEAD']);
    final name = r.stdout.trim();
    return (r.ok && name.isNotEmpty && name != 'HEAD') ? name : 'main';
  }

  Future<GitResult> push() => _run(['push', '-u', 'origin', 'HEAD']);

  Future<String?> remoteUrl() async {
    final r = await _run(['remote', 'get-url', 'origin']);
    return r.ok && r.stdout.isNotEmpty ? r.stdout : null;
  }

  Future<GitResult> setRemote(String url) async {
    final existing = await remoteUrl();
    return _run(
        existing == null ? ['remote', 'add', 'origin', url] : ['remote', 'set-url', 'origin', url]);
  }

  /// How many commits are waiting to go out. -1 when it cannot be determined
  /// (no remote, or never pushed).
  Future<int> unpushedCount() async {
    final r = await _run(['rev-list', '--count', '@{u}..HEAD']);
    if (!r.ok) return -1;
    return int.tryParse(r.stdout) ?? -1;
  }

  /// Pull, commit, push — the whole automated cycle, in the order that makes
  /// it safe.
  ///
  /// Pull FIRST so a remote change is merged before anything local is sent;
  /// pushing first and merging afterwards is what produces the rejected-push
  /// loop people associate with git sync. A failure at any step stops the
  /// cycle and is reported — a push that silently did not happen is worse
  /// than one that says so, because the user believes their notes are safe.
  Future<GitResult> syncOnce({required String message}) async {
    if (!isRepo) return const GitResult(-1, '', 'not a git repository');
    final hasRemote = await remoteUrl() != null;
    if (hasRemote) {
      final pulled = await pull();
      // A first sync has nothing to pull — no commits on the remote, or no
      // upstream because nothing has been pushed. Neither is a failure, and
      // neither must stop the commit below.
      if (!pulled.ok && !pulled.looksLikeNothingToPull) return pulled;
    }
    final committed = await commitAll(message);
    if (!committed.ok) return committed;
    if (!hasRemote) return committed;
    return push();
  }

  /// Clone a notebook someone shared — "would be good to be able to import
  /// directly using that one link".
  ///
  /// Clones into `<parent>/<name>.onotebook`, which is the layout
  /// `NotebookRef.logDirPath` expects, so the result is a notebook Openote can
  /// open by pointing at it. The container is rebuilt locally by replaying the
  /// logs; it is not in the repository and must not be.
  /// [token] authenticates a PRIVATE repository — which is what this feature
  /// creates by default, so it is the normal case rather than the exotic one.
  /// Passed through the environment exactly as [push] and [pull] pass it.
  static Future<GitResult> clone(String url, String intoDir,
      {String? token}) async {
    final git = await gitExecutable();
    if (git == null) {
      return const GitResult(-1, '', 'git is not installed on this computer');
    }
    if (Directory(intoDir).existsSync() &&
        Directory(intoDir).listSync().isNotEmpty) {
      return GitResult(-1, '', 'There is already something at $intoDir');
    }
    // A GitSync over the target, purely to borrow the credential-helper
    // arguments and environment. Static because there is no working tree to
    // run in yet — the clone is what creates one.
    final auth = GitSync(intoDir, token: token);
    try {
      final r = await Process.run(
              git, [...auth._authArgs, 'clone', url, intoDir],
              environment: auth._env)
          .timeout(const Duration(minutes: 10));
      return GitResult(r.exitCode, '${r.stdout}'.trim(), '${r.stderr}'.trim());
    } catch (e) {
      return GitResult(-1, '', '$e');
    }
  }
}

class GitResult {
  const GitResult(this.exitCode, this.stdout, this.stderr, {this.noop = false});
  final int exitCode;
  final String stdout;
  final String stderr;

  /// Succeeded, and there was nothing to do.
  final bool noop;

  bool get ok => exitCode == 0;

  /// A pull that failed because there is nothing to pull YET, rather than
  /// because something is wrong.
  ///
  /// Two ordinary first-sync states produce a non-zero exit: the remote has no
  /// commits, and the local branch has no upstream because nothing has been
  /// pushed. Both are what "I have just set this up" looks like, and treating
  /// either as a failure would make the very first sync impossible.
  ///
  /// Matched on the phrases git prints, which vary by version — and
  /// deliberately NOT on "repository not found" or "permission denied". Those
  /// are real failures, and waving one through as "nothing to pull yet" would
  /// tell the user their notes were safe somewhere they had never reached.
  bool get looksLikeNothingToPull {
    final t = '$stdout $stderr'.toLowerCase();
    return t.contains("couldn't find remote ref") ||
        t.contains('no such ref') ||
        t.contains('no tracking information') ||
        t.contains('you are not currently on a branch') ||
        t.contains('no commits yet');
  }

  /// What to show the user. Git puts most of what matters on stderr.
  String get message =>
      stderr.isNotEmpty ? stderr : (stdout.isNotEmpty ? stdout : 'failed');
}

/// The `.onotebook` directory of a notebook, as a git working tree.
GitSync gitFor(NotebookRef ref) => GitSync(ref.logDirPath);
