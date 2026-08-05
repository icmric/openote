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

  StreamSubscription<FileSystemEvent>? _sub;
  Timer? _debounce;

  bool get isWatching => _sub != null;

  void start() {
    if (_sub != null) return;
    if (!opsDir.existsSync()) return;
    try {
      _sub = opsDir.watch(recursive: false).listen(_onEvent, onError: (_) {
        // Watching is a convenience: a filesystem that doesn't support it (a
        // network mount, a container) must degrade to the manual pull button,
        // not break the notebook.
        stop();
      });
    } catch (_) {
      _sub = null;
    }
  }

  void _onEvent(FileSystemEvent e) {
    if (!e.path.endsWith('.oplog')) return;
    // Our own writes are the common case and must not trigger a pull — that
    // would be a feedback loop where every save schedules a re-read of what we
    // just wrote.
    if (e.path.contains(ownDevice)) return;
    _debounce?.cancel();
    _debounce = Timer(settle, onForeignChange);
  }

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
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
  }
}
