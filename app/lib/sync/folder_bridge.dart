/// **Keeping a notebook in step with a folder that is not an ordinary folder**
/// (Google Drive, reached through Android's folder picker).
///
/// The notebook's sync files are kept in an ordinary local directory, exactly as
/// for a notebook with a local sync folder, so every part of the app that reads
/// them is untouched. This class only moves files between that directory and the
/// chosen folder:
///
///  * **Pull** copies the other devices' logs (`ops/*.oplog`) and the manifest
///    down. The logs are the notebook's whole text and outline and are small;
///    the pictures are not, so they are **not** pulled with them.
///  * **Pictures arrive on demand.** [want] is asked for a picture the page
///    needs and fetches it in the background; the app is told when it lands
///    (`AppState._bytesMayHaveArrived`), and the picture, which showed a
///    placeholder, redraws. Each is checked against its hash before it is kept.
///
/// **Never writes to the chosen folder from here** (there is no
/// push yet): a notebook opened this way is viewed, not changed, until pushing
/// is built and tested on a copy. Nothing here deletes anything anywhere.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../store/notebook_writer.dart' show sha256Hex;
import 'op_log.dart';
import 'saf_folder.dart';

/// What one pull did, for the person who is waiting and for the timings we are
/// still learning.
class PullReport {
  PullReport({
    this.logs = 0,
    this.logBytes = 0,
    this.blobsListed = 0,
    this.milliseconds = 0,
  });
  int logs;
  int logBytes;
  int blobsListed;
  int milliseconds;
  @override
  String toString() =>
      '$logs log(s), ${(logBytes / 1024).round()} KB, $blobsListed pictures '
      'listed, $milliseconds ms';
}

class FolderBridge {
  FolderBridge({required this.folder, required String logDirPath, this.ownDevice})
      : logDir = Directory(logDirPath);

  final FolderApi folder;
  final Directory logDir;

  /// This device's own log is never taken from the folder: the local one is the
  /// truth and nothing remote may replace it.
  final String? ownDevice;

  OpLogStore get store => OpLogStore(logDir);

  Map<String, String>? _blobIndex;
  String? _blobsDoc;

  // ── Pulling the logs ─────────────────────────────────────────────────────

  static bool _isDir(SafEntry e, String name) => e.dir && e.name == name;

  Future<PullReport> pull() async {
    final sw = Stopwatch()..start();
    final report = PullReport();
    final root = await folder.list();

    final manifest = root.where((e) => !e.dir && e.name == 'manifest.json').firstOrNull;
    if (manifest != null) {
      final bytes = await folder.read(manifest.id);
      _replace(File(p.join(logDir.path, 'manifest.json')), bytes);
    }

    final ops = root.where((e) => _isDir(e, 'ops')).firstOrNull;
    if (ops != null) {
      for (final e in await folder.list(doc: ops.id)) {
        if (e.dir || !e.name.endsWith('.oplog')) continue;
        final device = e.name.substring(0, e.name.length - '.oplog'.length);
        if (device == ownDevice) continue;
        final local = File(p.join(logDir.path, 'ops', e.name));
        // Append-only: a longer file is the newer one, and a local file that is
        // already as long is already everything. Never swap a long one for a
        // short one.
        if (local.existsSync() && e.size >= 0 && local.lengthSync() >= e.size) {
          continue;
        }
        final bytes = await folder.read(e.id);
        _replace(local, bytes);
        report.logs++;
        report.logBytes += bytes.length;
      }
    }

    final blobs = root.where((e) => _isDir(e, 'blobs')).firstOrNull;
    _blobsDoc = blobs?.id;
    if (blobs != null) {
      _blobIndex = await _indexBlobs(blobs.id);
      report.blobsListed = _blobIndex!.length;
    }
    report.milliseconds = sw.elapsedMilliseconds;
    return report;
  }

  /// One listing of `blobs/`, keyed by hash. Names the cloud client has changed
  /// (`<hash>.pdf`, `<hash> (1).blob`) still begin with the hash, so they are
  /// found; the bytes are checked against the hash either way.
  Future<Map<String, String>> _indexBlobs(String blobsDoc) async {
    final out = <String, String>{};
    for (final e in await folder.list(doc: blobsDoc)) {
      if (e.dir || e.name.length < 64) continue;
      final head = e.name.substring(0, 64);
      if (!_hex64.hasMatch(head)) continue;
      out.putIfAbsent(head, () => e.id);
    }
    return out;
  }

  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

  /// Write [bytes] to [target] without ever leaving half a file there.
  void _replace(File target, Uint8List bytes) {
    target.parent.createSync(recursive: true);
    final tmp = File('${target.path}.tmp');
    tmp.writeAsBytesSync(bytes, flush: true);
    tmp.renameSync(target.path);
  }

  // ── Pictures, on demand ──────────────────────────────────────────────────

  final Set<String> _queued = {};
  final List<String> _queue = [];
  final Map<String, DateTime> _retryAfter = {};
  int _active = 0;

  /// How many pictures are being fetched at once. A few, so a page of pictures
  /// does not wait for them one at a time, and not so many that the provider
  /// is hammered.
  static const int concurrency = 3;

  /// Pictures asked for and not yet here. For the "loading" state.
  int get pending => _queue.length + _active;

  /// Fetch [hash] in the background if it is not here, and call [arrived] when
  /// it lands. Cheap to call again and again from a build: it asks once.
  void want(String hash, void Function() arrived) {
    final bare = hash.replaceFirst('sha256:', '');
    if (!_hex64.hasMatch(bare)) return;
    if (_queued.contains(bare) || store.hasBlob(bare)) return;
    final wait = _retryAfter[bare];
    if (wait != null && DateTime.now().isBefore(wait)) return;
    _queued.add(bare);
    _queue.add(bare);
    _pump(arrived);
  }

  void _pump(void Function() arrived) {
    while (_active < concurrency && _queue.isNotEmpty) {
      final h = _queue.removeAt(0);
      _active++;
      () async {
        try {
          if (await _fetch(h)) arrived();
        } catch (_) {
          // Try again later, not in a loop: a failing provider is not made
          // better by being asked again at once.
          _retryAfter[h] = DateTime.now().add(const Duration(seconds: 30));
        } finally {
          _queued.remove(h);
          _active--;
          _pump(arrived);
        }
      }();
    }
  }

  Future<bool> _fetch(String hash) async {
    var index = _blobIndex;
    if (index == null) {
      final doc = _blobsDoc;
      if (doc == null) return false;
      index = _blobIndex = await _indexBlobs(doc);
    }
    final doc = index[hash];
    if (doc == null) return false; // not in the folder (yet)
    final bytes = await folder.read(doc);
    // **Only bytes that are what their name says are kept.** A half download or
    // a changed file is thrown away, and the picture stays a placeholder.
    if (sha256Hex(bytes) != hash) {
      throw StateError('picture $hash did not match its name');
    }
    store.writeBlob(hash, bytes);
    return true;
  }
}
