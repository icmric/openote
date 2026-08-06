/// Device identity, and the check that protects it (ADR-0006 §6a.2).
///
/// One-writer-per-file is the entire correctness argument of the sync design:
/// because a device only ever appends to *its own* log, two devices cannot
/// produce conflicting versions of one file, and merging degenerates to reading
/// every log and sorting. That argument holds exactly as long as no two running
/// installations believe they are the same device.
///
/// Normal use cannot break it. The dangerous cases are all forms of copying:
/// a cloned VM, a restored backup, a user duplicating an install directory. In
/// those, two processes legitimately hold the same id and interleave writes into
/// one log — producing a file that still *parses*, still looks ordered, and is
/// unrecoverably wrong. This file exists to make that case detectable.
library;

import '../core/ids.dart';
import 'op_log.dart';

/// How a device's identity is stored and validated.
///
/// The id lives in **app settings, not in the notebook**. That is the whole
/// point: an id stored inside a notebook would be cloned along with it, so
/// copying a notebook folder to a second machine would instantly create two
/// writers on one log.
class DeviceIdentity {
  DeviceIdentity({required this.id, required this.forked});

  final String id;

  /// True when this instance forked away from a previous id because that id's
  /// log had writes we did not make. Surfaced so it can be logged/reported —
  /// silently forking would hide a real problem (a cloned install) that the
  /// user probably wants to know about.
  final bool forked;

  static const settingsKey = 'deviceId';
  static const _seqKeyPrefix = 'deviceSeq:';

  /// Per-notebook key under which we remember the last seq we wrote. Scoped per
  /// notebook because a device writes an independent sequence into each.
  static String seqKey(String notebookId) => '$_seqKeyPrefix$notebookId';

  /// Resolve this installation's identity for [notebookId], forking if another
  /// installation has been writing to our log.
  ///
  /// [readSetting]/[writeSetting] are injected rather than taking a Repository
  /// so this is testable without a database, and so it cannot accidentally grow
  /// a dependency on notebook state — the id must not live there.
  /// [lastSeqOf] overrides how the on-disk seq for an id is found. The async
  /// recorder open passes the per-device maxima its background replay already
  /// computed, so the fork check costs a map lookup instead of re-reading the
  /// device's whole log on the UI thread.
  static DeviceIdentity resolve({
    required OpLogStore store,
    required String notebookId,
    required Object? Function(String key) readSetting,
    required void Function(String key, Object? value) writeSetting,
    int Function(String id)? lastSeqOf,
  }) {
    var id = readSetting(settingsKey) as String?;
    if (id == null || id.isEmpty) {
      id = newId();
      writeSetting(settingsKey, id);
      // A brand-new id cannot collide, but it also has no remembered seq, and
      // an *existing* log under it would mean the id was reused. Fall through
      // to the check rather than special-casing.
    }

    final remembered = (readSetting(seqKey(notebookId)) as num?)?.toInt() ?? 0;
    final onDisk = (lastSeqOf ?? store.lastSeq)(id);

    if (onDisk > remembered) {
      // Someone else wrote as us. We cannot tell which ops were theirs, and
      // appending would interleave two writers in one log forever — so abandon
      // the id rather than the history. Their ops stay valid and readable under
      // the old id; we simply stop claiming to be them.
      final fresh = newId();
      writeSetting(settingsKey, fresh);
      writeSetting(seqKey(notebookId), 0);
      return DeviceIdentity(id: fresh, forked: true);
    }

    return DeviceIdentity(id: id, forked: false);
  }
}
