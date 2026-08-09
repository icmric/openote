/// Noticing when another device's changes arrive.
///
/// The transport is a synced folder, so "someone else edited" shows up as
/// "a file changed under `.onotebook/ops/`". Watching that directory turns
/// the manual pull button into something that just happens.
library;

import 'dart:async';
import 'dart:io';

/// Watches a notebook's op directory and calls back when a *foreign* log
/// changes.
class OpFolderWatcher {
  OpFolderWatcher({
    required this.opsDir,
    required this.ownDevice,
    required this.onForeignChange,
    this.settle = const Duration(milliseconds: 900),
    this.pollEvery = const Duration(seconds: 5),
  });

  final Directory opsDir;
  final String ownDevice;
  final void Function() onForeignChange;

  /// A cloud client writes a file in several chunks and often renames a temp
  /// file over it, so a single edit produces a burst of events. Waiting for
  /// the burst to stop avoids pulling a half-written log — and a half-written
  /// log is exactly the torn-tail case the reader is built to tolerate, so
  /// this is belt-and-braces rather than the only defence.
  final Duration settle;

  /// How often the directory is listed as a backstop. See [_poll].
  final Duration pollEvery;

  StreamSubscription<FileSystemEvent>? _sub;
  Timer? _debounce;
  Timer? _pollTimer;

  /// Size and mtime of each foreign log at the last check.
  final Map<String, ({int size, int modified})> _seen = {};

  bool get isWatching => _sub != null || _pollTimer != null;

  void start() {
    if (_sub != null || _pollTimer != null) return;
    if (!opsDir.existsSync()) return;
    try {
      _sub = opsDir.watch(recursive: false).listen(_onEvent, onError: (_) {
        // Watching is a convenience: a filesystem that doesn't support it (a
        // network mount, a container) must degrade to the poll below, not
        // break the notebook.
        _sub?.cancel();
        _sub = null;
      });
    } catch (_) {
      _sub = null;
    }
    _snapshot(); // establish the baseline before the first tick
    _pollTimer = Timer.periodic(pollEvery, (_) => _poll());
  }

  /// List the directory and compare sizes and mtimes.
  ///
  /// **A floor under the watcher, not a replacement for it.** Filesystem
  /// notifications are the fast path and stay the fast path — but they are
  /// also the part that silently did not work: on a real OneDrive folder the
  /// receiving device never saw a single event it recognised, and the only
  /// symptom was that sync appeared to do nothing at all. A directory listing
  /// of a handful of files every few seconds cannot be defeated by a temp-file
  /// rename, a placeholder, a network mount or a platform that reports nothing
  /// — and it costs a `stat` per log.
  ///
  /// Compares size AND mtime because a cloud client can replace a file with
  /// one of the same length, and some filesystems have coarse timestamps.
  void _poll() {
    if (!opsDir.existsSync()) return;
    var changed = false;
    try {
      for (final f in opsDir.listSync(followLinks: false)) {
        if (f is! File || !_looksLikeLog(f.path)) continue;
        if (f.path.contains(ownDevice)) continue; // our own writes
        final st = f.statSync();
        final now = (size: st.size, modified: st.modified.millisecondsSinceEpoch);
        final was = _seen[f.path];
        _seen[f.path] = now;
        if (was == null || was.size != now.size || was.modified != now.modified) {
          changed = true;
        }
      }
    } catch (_) {
      return; // unreadable this tick; try again next
    }
    if (!changed) return;
    // Through the same debounce as an event, so a burst of writes and a poll
    // landing together still produce one pull.
    _debounce?.cancel();
    _debounce = Timer(settle, onForeignChange);
  }

  /// Record what is there now WITHOUT reporting it as a change — otherwise
  /// arming the watcher would fire a pull on every notebook open.
  void _snapshot() {
    try {
      for (final f in opsDir.listSync(followLinks: false)) {
        if (f is! File || !_looksLikeLog(f.path)) continue;
        final st = f.statSync();
        _seen[f.path] =
            (size: st.size, modified: st.modified.millisecondsSinceEpoch);
      }
    } catch (_) {}
  }

  void _onEvent(FileSystemEvent e) {
    // **Every path the event mentions, not just `path`.**
    //
    // This is why the receiving device never noticed anything. The comment on
    // [settle] already says a cloud client "often renames a temp file over it"
    // — and then this dropped precisely that, twice over. OneDrive and Drive
    // write `<device>.oplog~RF1a2b.TMP` and rename it into place, so:
    //
    //   * the CREATE and MODIFY events name the temp file, which does not end
    //     in `.oplog`; and
    //   * `FileSystemMoveEvent.path` is the SOURCE — the temp name again —
    //     with the real target hiding in `.destination`, which nothing read.
    //
    // So on the one transport this watcher exists for, every event was
    // discarded and the only way to see another machine's edits was the manual
    // button.
    final paths = <String>[
      e.path,
      if (e is FileSystemMoveEvent && e.destination != null) e.destination!,
    ];
    if (!paths.any(_looksLikeLog)) return;
    // Our own writes are the common case and must not trigger a pull — that
    // would be a feedback loop where every save schedules a re-read of what we
    // just wrote. Only skipped when EVERY path names us: a rename from our own
    // temp file to a foreign log is not our write.
    if (paths.every((p) => p.contains(ownDevice))) return;
    _debounce?.cancel();
    _debounce = Timer(settle, onForeignChange);
  }

  /// A log, or something on its way to becoming one.
  ///
  /// Deliberately generous. A false positive costs one `pendingForeignOps`
  /// check, which reads from a byte watermark and returns nothing; a false
  /// negative costs the user their sync.
  static bool _looksLikeLog(String path) =>
      path.contains('.oplog') || path.toLowerCase().endsWith('.tmp');

  /// Stop watching. **Await this before deleting the directory being watched.**
  ///
  /// `StreamSubscription.cancel()` is asynchronous, and on Windows the
  /// underlying `ReadDirectoryChangesW` handle is only released once it
  /// completes — so a fire-and-forget `stop()` followed by a delete of that
  /// same directory races the release and fails with "the process cannot
  /// access the file". `moveNotebookToFolder` does exactly that sequence.
  /// `Repository` already disposes the SQLite handle for this reason; the
  /// watcher was the handle it missed.
  Future<void> stop() async {
    _debounce?.cancel();
    _debounce = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _seen.clear();
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
  }
}
