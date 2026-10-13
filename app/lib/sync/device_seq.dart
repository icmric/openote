/// How far this installation has written into one notebook's log, remembered
/// somewhere that survives a crash.
///
/// `DeviceIdentity.resolve` forks the device id when the log holds ops beyond
/// the last seq this installation remembers writing, because that is the only
/// honest signal that a second installation is appending under our id — the
/// one thing that breaks one-writer-per-file. The signal is only as good as the
/// memory behind it, and that is what this file is for.
///
/// **It used to live in `workspace.json`**, written through `setSetting`, which
/// coalesces behind a 400 ms debounce and is forced only by a clean `shutdown()`.
/// Ops, meanwhile, are appended and flushed immediately. So any exit that skips
/// shutdown — a crash, a kill, a power cut — left the log ahead of the remembered
/// seq, which is indistinguishable from a second writer, and the device forked.
/// Every fork orphans a log that nothing ever deletes.
///
/// Measured on a real notebook: two ids minted 79 minutes apart on one day,
/// both labelled "Windows computer", one machine.
///
/// **Local, and deliberately not in the `.onotebook`.** The value is a claim
/// about *this installation*, and the whole detection works by comparing a
/// local record against the shared log. A copy of it inside the notebook would
/// travel to the second installation and agree with it, which is exactly the
/// disagreement we need.
library;

import 'package:path/path.dart' as p;

import '../store/fs.dart';

/// A per-notebook record of the last seq this installation wrote.
class DeviceSeqStore {
  DeviceSeqStore(this.dir);

  /// A local, never-synced directory this installation owns. In the app this is
  /// `Repository.cacheDirFor(notebookId)`.
  final Directory dir;

  File get _file => File(p.join(dir.path, 'devseq'));

  /// The remembered seq, or null when there is no record at all.
  ///
  /// **Null is not zero.** No record means this installation has never written
  /// one — a fresh notebook, or a build from before this file existed — and the
  /// caller must adopt what the log says rather than read the absence as "we
  /// have written nothing", which would fork every existing install exactly
  /// once on upgrade.
  int? read() {
    try {
      final f = _file;
      if (!f.existsSync()) return null;
      return int.tryParse(f.readAsStringSync().trim());
    } catch (_) {
      // Unreadable is the same as absent: adopt the log.
      return null;
    }
  }

  /// Record [seq], durably, before the ops it covers are appended.
  ///
  /// Best-effort by design: a read-only volume or a full disk must not stop a
  /// save. A write that fails leaves the previous value, which can only make
  /// the next open *more* suspicious, never less — the safe direction.
  void write(int seq) {
    try {
      dir.createSync(recursive: true);
      _file.writeAsStringSync('$seq', flush: true);
    } catch (_) {}
  }
}
