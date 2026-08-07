/// Passcode-gating a page, section or section group **inside Openote**.
///
/// # Read this before touching it: what this is, and what it is not
///
/// This is a **lock on the app's own doors, not on the file**. It stops the
/// person who picks up your unlocked laptop from reading a page. It does
/// **nothing whatsoever** against anyone who has the `.onote` file: the notes
/// stay in plaintext in a documented SQLite container that any SQLite browser
/// opens in seconds, and in plaintext in the op log that syncs to your cloud
/// folder. Copy the file to another machine and every "protected" page is
/// readable with no passcode involved.
///
/// That limitation is not hidden from the user. It is stated in the dialog
/// that sets a passcode, before the first page is ever locked, in those words.
/// A padlock that lies about what it protects is worse than no padlock,
/// because someone will trust it with something that matters.
///
/// [ADR-0008](../../docs/adr/ADR-0008-page-protection.md) designs the real
/// thing — encryption at rest, node-level, reaching the op log — and explains
/// why a gate alone cannot be called security. This file is the interim answer
/// to "just basic password protection in app at a minimum would be fine too
/// for now", built deliberately and labelled honestly, not a substitute for
/// that work.
///
/// # Why the passcode is still hashed
///
/// It buys nothing against the file-level attacker above — they never see the
/// prompt. It is done because people reuse passcodes, and writing someone's
/// reused passcode into a plaintext JSON file on disk would be a genuine harm
/// this feature has no business causing, quite separate from whether the gate
/// works.
///
/// Salted SHA-256, not a password KDF. A KDF's work factor exists to slow an
/// offline guessing attack on the hash — and an attacker who can read the hash
/// (it is in `workspace.json`) can equally read the notes themselves, so the
/// work factor would protect nothing here. Argon2id belongs with the
/// encryption in ADR-0008, where the derived key actually guards something.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../store/notebook_writer.dart' show sha256Hex;

/// How long an unlock lasts.
enum UnlockPolicy {
  /// Every time the page is opened.
  always('always', 'Every time it is opened', null),

  tenMinutes('10m', 'For 10 minutes', Duration(minutes: 10)),

  oneHour('1h', 'For 1 hour', Duration(hours: 1)),

  /// Until Openote exits. Nothing is persisted, so this is simply the absence
  /// of an expiry within a session.
  session('session', 'Until Openote is closed', null);

  const UnlockPolicy(this.id, this.label, this.duration);

  final String id;
  final String label;

  /// Null for [always] (never cached) and [session] (cached with no expiry).
  final Duration? duration;

  static UnlockPolicy fromId(String? id) =>
      UnlockPolicy.values.firstWhere((p) => p.id == id,
          orElse: () => UnlockPolicy.session);
}

/// What is stored for one protected node.
///
/// Lives in `workspace.json`, which is LOCAL and never synced — the same place
/// the app keeps which page you had open. That is the honest home for it: the
/// protection is a property of this installation's UI, not of the notebook, so
/// it does not travel with a copied `.onote` and must not pretend to.
class ProtectionRecord {
  const ProtectionRecord({
    required this.salt,
    required this.hash,
    required this.policy,
    required this.createdAt,
  });

  final String salt;
  final String hash;
  final UnlockPolicy policy;
  final int createdAt;

  Map<String, dynamic> toJson() => {
        'salt': salt,
        'hash': hash,
        'policy': policy.id,
        'createdAt': createdAt,
      };

  static ProtectionRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<String, dynamic>();
    final salt = m['salt'] as String?;
    final hash = m['hash'] as String?;
    if (salt == null || hash == null) return null;
    return ProtectionRecord(
      salt: salt,
      hash: hash,
      policy: UnlockPolicy.fromId(m['policy'] as String?),
      createdAt: (m['createdAt'] as num?)?.toInt() ?? 0,
    );
  }

  bool matches(String passcode) => _digest(passcode, salt) == hash;
}

/// Build a record for a new passcode. The passcode itself is never returned,
/// stored, or logged.
ProtectionRecord newProtection(String passcode, UnlockPolicy policy) {
  final salt = _randomSalt();
  return ProtectionRecord(
    salt: salt,
    hash: _digest(passcode, salt),
    policy: policy,
    createdAt: DateTime.now().millisecondsSinceEpoch,
  );
}

/// 16 random bytes, hex. `Random.secure()` rather than `Random()`: a
/// predictable salt would let one precomputed table cover every Openote user,
/// which is the only thing the salt is here to prevent.
String _randomSalt() {
  final r = Random.secure();
  final b = Uint8List.fromList(List.generate(16, (_) => r.nextInt(256)));
  return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}

String _digest(String passcode, String salt) =>
    sha256Hex(Uint8List.fromList(utf8.encode('$salt:$passcode')));
