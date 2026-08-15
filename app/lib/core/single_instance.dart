/// One Openote per workspace, and a way to hand it a notebook.
///
/// **Why single instance rather than a second window.** Windows' default,
/// once `.onote` is associated with the app, is to start a whole new
/// `openote.exe` for every double-click. Each of those opens the same
/// `workspace.json` registry and — the moment two of them land on one
/// notebook, which is exactly what happens when you double-click the notebook
/// you already have open — the same WAL SQLite container from two processes.
/// That is the corruption ADR-0006 §3 is written against ("cache.onote ←
/// local-only SQLite; never synced"), and this project has already shipped one
/// bug where two devices shared one container. The registry is no safer: it is
/// rewritten wholesale by whichever process saves last, so a notebook created
/// in one window disappears when the other writes.
///
/// The alternative — teach the app to be multi-process-safe — is a large piece
/// of work whose payoff is a second window nobody asked for. Openote has ONE
/// workspace and switching notebooks is already a first-class operation
/// (`AppState.selectNotebook`), so the running instance switching to the
/// notebook you double-clicked is both the cheap answer and the one that
/// matches what the app already is.
///
/// **The protocol**, deliberately files rather than a socket. The app already
/// treats a listening port as something to ask permission for (the MCP server
/// is off by default and token-guarded); "any local process can tell Openote
/// what to open" is not a surface worth opening for this, and a port also
/// invites a firewall prompt on the very first launch after an update.
///
/// 1. The first instance takes an exclusive lock on `.instance-lock` in the
///    workspace folder and holds it for the life of the process. Both Windows
///    and POSIX drop file locks when a process dies, including when it
///    crashes, so there is no stale-PID problem to solve.
/// 2. A later instance fails to take the lock, writes what it was asked to
///    open into `.open-request`, and waits for that file to disappear.
/// 3. The holder polls, takes the request (deleting it — the delete IS the
///    acknowledgement), comes to the front and switches notebooks.
/// 4. **If nobody acknowledges within [handOffTimeout], the new instance
///    starts normally anyway.** This is the important safety valve: the worst
///    case is two Openotes, which is precisely what happened before this file
///    existed. A wedged or half-dead lock holder must never be able to make
///    the app unlaunchable.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'window_focus.dart';

class SingleInstance {
  SingleInstance._(this._dir, this._lock);

  final Directory _dir;

  /// Null when we are running WITHOUT the lock — the fallback in step 4 above.
  /// Kept open for the life of the process; closing it releases the lock.
  final RandomAccessFile? _lock;

  Timer? _poll;

  /// How long a new instance waits for the running one to answer before
  /// deciding it is not going to.
  static const handOffTimeout = Duration(seconds: 5);

  /// How often the holder looks for a request. 600 ms is a `stat` of one path;
  /// the delay it adds to a double-click is under a frame of a person's
  /// patience and it costs nothing to run all day.
  static const pollInterval = Duration(milliseconds: 600);

  /// A request older than this is dropped rather than acted on. It can only
  /// come from an instance that died mid-hand-off, and opening a notebook
  /// somebody double-clicked before lunch is worse than doing nothing.
  static const requestMaxAge = Duration(minutes: 1);

  static File lockFile(Directory dir) =>
      File(p.join(dir.path, '.instance-lock'));

  static File requestFile(Directory dir) =>
      File(p.join(dir.path, '.open-request'));

  /// True when this instance holds the workspace lock.
  bool get holdsLock => _lock != null;

  /// Become the Openote for [dir], or hand [openPath] to the one that already
  /// is.
  ///
  /// Returns null when the work was handed over — the caller should exit
  /// **without painting a window**, which is why this runs before `runApp` and
  /// not inside the boot widget. A second window that appears and vanishes is
  /// worse than either outcome on its own.
  static Future<SingleInstance?> claim(Directory dir, {String? openPath}) async {
    RandomAccessFile? lock;
    try {
      // `append`, not `write`: `write` truncates on open, and it would do so
      // before the lock attempt — on the file the running instance is holding.
      lock = await lockFile(dir).open(mode: FileMode.append);
      // `FileLock.exclusive` is the non-blocking form and fails when the lock
      // is held. The timeout is belt-and-braces: a lock call that never
      // returned would hang the launch before there is any window to explain
      // itself in, which is the one failure this whole file must not cause.
      await lock.lock(FileLock.exclusive).timeout(const Duration(seconds: 2));
      // Who has it, for anyone debugging a workspace that will not open.
      await lock.truncate(0);
      await lock.setPosition(0);
      await lock.writeString('$pid\n');
      await lock.flush();
    } catch (_) {
      try {
        await lock?.close();
      } catch (_) {/* already gone */}
      lock = null;
    }
    if (lock != null) return SingleInstance._(dir, lock);

    if (await handOff(dir, openPath)) return null;
    // Held, but nothing answered. Start anyway — see step 4.
    return SingleInstance._(dir, null);
  }

  /// Ask the running instance to come forward and open [path] (null or empty
  /// = just come forward). True when it acknowledged.
  static Future<bool> handOff(Directory dir, String? path,
      {Duration timeout = handOffTimeout}) async {
    final request = requestFile(dir);
    try {
      // Written to a temp file and renamed, so the holder can never read a
      // half-written request. Its poll runs on a timer, not on a file event,
      // so it WILL see the file mid-write otherwise.
      final tmp = File('${request.path}.tmp');
      await tmp.writeAsString(
          jsonEncode({
            'path': path ?? '',
            'at': DateTime.now().millisecondsSinceEpoch,
          }),
          flush: true);
      await tmp.rename(request.path);
    } catch (_) {
      return false; // read-only workspace, full disk — start our own instance
    }
    // Grant the foreground right BEFORE waiting: this process has it now,
    // because the user just launched it, and it loses it the moment it exits.
    WindowFocus.allowForegroundHandover();

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!request.existsSync()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    // Nobody is listening. Take our request back rather than leave it for a
    // future Openote to act on minutes or days later.
    try {
      if (request.existsSync()) await request.delete();
    } catch (_) {/* best effort */}
    return false;
  }

  /// Holder side: take the pending request, if there is one.
  ///
  /// Returns the requested path, `''` for "just come forward", or null when
  /// there is nothing to do. **Deleting the file is the acknowledgement**, so
  /// this both reads and consumes.
  static String? takeRequest(Directory dir,
      {Duration maxAge = requestMaxAge}) {
    final request = requestFile(dir);
    if (!request.existsSync()) return null;
    String raw;
    try {
      raw = request.readAsStringSync();
    } catch (_) {
      // Being renamed over right now (Windows will refuse the read while the
      // rename is in flight). Leave it: the next tick gets it.
      return null;
    }
    try {
      request.deleteSync();
    } catch (_) {/* the sender times out and starts its own instance */}
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final at = (decoded['at'] as num?)?.toInt() ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - at > maxAge.inMilliseconds) {
        return null; // acknowledged above, but too old to act on
      }
      final path = decoded['path'];
      return path is String ? path : '';
    } catch (_) {
      return null; // acknowledged; nothing intelligible to do
    }
  }

  /// Start watching for later double-clicks. [onOpen] gets an absolute path.
  ///
  /// [raise] exists so a test can pass a no-op, and it is not a nicety:
  /// [WindowFocus.raiseSelf] finds a window by class and title, and a test run
  /// on the developer's own machine would find the developer's own running
  /// Openote and un-minimise it. A test suite that rearranges your desktop is
  /// a test suite you stop running.
  void listen(void Function(String path) onOpen, {bool Function()? raise}) {
    _poll?.cancel();
    final bringToFront = raise ?? WindowFocus.raiseSelf;
    _poll = Timer.periodic(pollInterval, (_) {
      final path = takeRequest(_dir);
      if (path == null) return;
      // Front first, then switch. The notebook change is instant and the
      // window raise is the part the user sees, so doing it first makes the
      // app feel like it responded to the double-click rather than to
      // whatever happens next.
      bringToFront();
      if (path.isNotEmpty) onOpen(path);
    });
  }

  Future<void> dispose() async {
    _poll?.cancel();
    _poll = null;
    try {
      await _lock?.unlock();
    } catch (_) {/* the process is going away anyway */}
    try {
      await _lock?.close();
    } catch (_) {/* ditto */}
  }
}
