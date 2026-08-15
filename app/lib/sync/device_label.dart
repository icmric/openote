/// The name a computer goes by inside a notebook.
///
/// **The one genuinely new thing Step 8a needs.** Attribution derived from the
/// log is free — the ops already carry `dev` — but a device id is a uuid, and
/// *"last changed by 019fdff4-8c31-7a2e-…"* is worse than saying nothing. The
/// machinery was half-built: `OpLogStore.announceDevice` takes an optional
/// `label` and writes it into `manifest.json`'s `devices` map, whose own
/// comment says the map exists *"for showing the user which devices touched a
/// notebook"* — and both call sites pass no label, so the map has entries and
/// no names.
///
/// This is the missing half: read the names, set this computer's, and default
/// it without asking a question at first run.
///
/// **The label is shared.** In a folder-shared notebook `manifest.json` is a
/// synced file, so everyone in the notebook sees this string. That is why the
/// default is a plain description of the machine and deliberately **not** the
/// Windows hostname — `DESKTOP-4G7H2K` is jargon by any reasonable reading of
/// the bar, and it is not the sort of thing anyone chose to publish.
///
/// Last-writer-wins on a display string, which is the weakest merge in the
/// codebase and the right one: the worst outcome is a name that is briefly out
/// of date.
library;

import 'dart:convert';
import 'dart:io';

import 'op_log.dart';

abstract final class DeviceLabels {
  /// Every device this notebook has heard of, with the name it goes by. A
  /// device with no name is absent rather than mapped to null, so callers fall
  /// through to `deviceDisplayName`'s *"another computer"*.
  static Map<String, String> read(OpLogStore store) {
    final devices = (store.readManifest()['devices'] as Map?) ?? const {};
    final out = <String, String>{};
    devices.forEach((k, v) {
      if (k is! String || v is! Map) return;
      final label = v['label'];
      if (label is String && label.trim().isNotEmpty) out[k] = label.trim();
    });
    return out;
  }

  static String? labelOf(OpLogStore store, String device) =>
      read(store)[device];

  /// Give this computer a name in this notebook, or clear it (empty string).
  ///
  /// Returns false when the manifest could not be written — a read-only
  /// folder, a cloud client holding the file. A name that would not save is
  /// worth reporting to the caller rather than pretending, but it is never
  /// worth failing a save over: the notebook is unaffected either way.
  static bool set(OpLogStore store, String device, String label) {
    final m = store.readManifest();
    if (m.isEmpty) return false;
    final devices = (m['devices'] as Map?)?.cast<String, dynamic>() ?? {};
    final entry = (devices[device] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{'firstSeen': DateTime.now().millisecondsSinceEpoch};
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      entry.remove('label');
    } else {
      // Capped, because it is displayed in a list beside a date and a synced
      // file should not carry a paragraph.
      entry['label'] =
          trimmed.length > 60 ? trimmed.substring(0, 60).trimRight() : trimmed;
    }
    devices[device] = entry;
    m['devices'] = devices;
    return _write(store, m);
  }

  /// Name this computer if it has no name yet, so attribution reads sensibly
  /// on a notebook nobody has ever visited the sync dialog for.
  ///
  /// Idempotent, and never overwrites a name the user chose.
  static bool ensureNamed(OpLogStore store, String device) {
    if (read(store).containsKey(device)) return false;
    return set(store, device, defaultLabel());
  }

  /// What this computer is called before anybody says otherwise.
  ///
  /// Plain words, no hostname, no model number. Two Windows machines in one
  /// notebook will both start out as *"Windows computer"* — which is honest,
  /// and the field in the sync dialog is one click away for whoever minds.
  static String defaultLabel() {
    if (Platform.isWindows) return 'Windows computer';
    if (Platform.isMacOS) return 'Mac computer';
    if (Platform.isLinux) return 'Linux computer';
    if (Platform.isAndroid) return 'Android phone';
    if (Platform.isIOS) return 'iPhone or iPad';
    return 'Another computer';
  }

  /// Atomic, for the same reason `OpLogStore._writeManifest` is: unlike the
  /// logs this file is rewritten in place, so a torn write would lose the whole
  /// device map rather than one line of it.
  ///
  /// Spelled here rather than reached for inside `OpLogStore` only because that
  /// writer is private; if it is ever made public this should call it, so that
  /// there is exactly one function that replaces a manifest.
  static bool _write(OpLogStore store, Map<String, dynamic> m) {
    try {
      final target = store.manifestFile;
      final tmp = File('${target.path}.tmp');
      tmp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(m),
          flush: true);
      tmp.renameSync(target.path);
      return true;
    } catch (_) {
      return false;
    }
  }
}
