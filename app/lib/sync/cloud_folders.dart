/// Finding the cloud folders a user already has, so syncing a notebook is
/// picking one from a list rather than following instructions.
///
/// **Why no OAuth, no API clients, no tokens.**
///
/// Google Drive, OneDrive, iCloud Drive and Dropbox all ship a desktop client
/// that presents the cloud as an ordinary local folder. ADR-0006's design
/// already syncs correctly through *any* such folder, because each device only
/// ever appends to its own log file — the one-writer-per-file property means
/// conflicting versions cannot arise, so the provider never has to merge
/// anything, which is the exact thing these providers do badly.
///
/// Building OAuth clients instead would mean: registering the app with four
/// vendors, shipping client secrets in an open-source binary (where they are
/// not secret), holding refresh tokens with broad Drive scopes on disk, and
/// owning a token-refresh failure mode for every user. That is a large new
/// attack surface and a permanent maintenance burden, in exchange for
/// replicating what the user's existing sync client already does correctly.
///
/// So: we detect the folders, we explain the trade, and we copy files. The
/// same mechanism serves self-hosting — Syncthing, Nextcloud's client, a NAS
/// mount, or an rsync cron job all produce a folder too.
library;

import 'dart:io';

import '../store/workspace_fs.dart';
import 'volume_label.dart';

import 'package:path/path.dart' as p;

/// A sync location we can offer the user.
class CloudFolder {
  const CloudFolder({
    required this.name,
    required this.path,
    required this.kind,
    this.account,
  });

  /// What the provider is called — "Google Drive", "OneDrive (work)". Used in
  /// prose, so it stays a provider name rather than growing a path or an email.
  final String name;
  final String path;
  final CloudKind kind;

  /// Which account or volume this one is, when the platform can say.
  ///
  /// Google Drive mounts **one drive letter per signed-in account**, so a
  /// personal and a work account are two rows both called "Google Drive" and
  /// nothing on screen says which is which. The volume label carries the
  /// address — Windows truncates it to 32 characters, which keeps the part that
  /// identifies it. Null whenever the platform has nothing to add.
  final String? account;

  /// The provider, and whatever tells one mount from another:
  /// `Google Drive · name@example.com (G:)`, or just `OneDrive`.
  String get label {
    final where = _mountLetter(path);
    final who = _tidyVolumeLabel(account);
    if (who != null && where != null) return '$name · $who ($where)';
    if (who != null) return '$name · $who';
    if (where != null) return '$name · $where';
    return name;
  }

  /// Whether the directory still exists — a provider can be uninstalled.
  bool get exists => Directory(path).existsSync();
}

/// The drive letter [path] sits on, or null when it does not start with one.
String? _driveLetterOf(String path) {
  if (path.length < 2 || path[1] != ':') return null;
  final c = path[0].toUpperCase();
  return (c.codeUnitAt(0) >= 65 && c.codeUnitAt(0) <= 90) ? c : null;
}

/// `G:` when [path] is a provider's own mounted volume, null when it is an
/// ordinary folder.
///
/// A drive letter is worth showing when it is the thing that distinguishes two
/// mounts, `G:\\My Drive` against `I:\\My Drive`. It is noise on
/// `C:\\Users\\me\\OneDrive`, where it only ever says the system drive and
/// "OneDrive · C:" tells nobody anything. The test is whether the path sits
/// directly under the drive root.
/// **`p.windows`, not `p`.** A drive letter is a Windows idea, so the question
/// "is this path a drive root" has one answer everywhere rather than whatever
/// the host's own path flavour makes of it. On Windows nothing changes —
/// `p` IS `p.windows` there — and on a POSIX host nothing real changes either,
/// because this is only reached for a path beginning `X:` and no folder
/// discovered on Linux or macOS ever does.
///
/// What it changes is that the behaviour can be TESTED off Windows. With the
/// default context, `p.dirname(r'G:\My Drive')` is `.` on a POSIX host, so
/// the letter came back null, the label quietly lost its `(G:)`, and four
/// tests in `volume_label_test.dart` failed on two of CI's three runners
/// while passing on the owner's machine — which is how the branch sat red
/// from 23 October without it being obvious why.
String? _mountLetter(String path) {
  final letter = _driveLetterOf(path);
  if (letter == null) return null;
  final parent = p.windows.dirname(p.windows.normalize(path));
  return p.windows.equals(parent, '$letter:\\') ? '$letter:' : null;
}

/// A volume label with Windows' truncation tidied away.
///
/// Labels cap at 32 characters and Google Drive sets longer ones, so what comes
/// back is `name@example.com -...` or `name@example.com - Google D...` — the
/// second ending mid-word. When a label is truncated, cut back to the last
/// ` - ` separator if there is one: the address identifies the account, and the
/// provider's own name is already beside it.
String? _tidyVolumeLabel(String? label) {
  var v = label?.trim();
  if (v == null || v.isEmpty) return null;
  if (!v.endsWith('...')) return v;
  v = v.substring(0, v.length - 3).trimRight();
  final cut = v.lastIndexOf(' - ');
  if (cut > 0) v = v.substring(0, cut);
  v = v.replaceFirst(RegExp(r'[\s-]+$'), '');
  return v.isEmpty ? null : v;
}

enum CloudKind {
  googleDrive('Google Drive'),
  oneDrive('OneDrive'),
  iCloud('iCloud Drive'),
  dropbox('Dropbox'),
  syncthing('Syncthing'),
  nextcloud('Nextcloud'),
  other('Folder');

  const CloudKind(this.label);
  final String label;
}

String? _env(String key) {
  // **Guarded, because `Platform.environment` throws in a web build** rather
  // than coming back empty, and this is reached from the navigator's header on
  // every build. The throw took the whole sidebar down: Flutter replaced it
  // with an `ErrorWidget`, which in a release build is a plain grey rectangle
  // and in a stretched Column is a hundred thousand pixels of one — exactly
  // the failure `_NotebookHeader` already documents having seen once before.
  //
  // There are no cloud folders in a tab, so the empty answer below is true as
  // well as safe: `detectCloudFolders` returns nothing, the dot says "This
  // computer only", and nothing else has to know.
  if (!workspaceIsOnDisk) return null;
  final v = Platform.environment[key];
  return (v == null || v.isEmpty) ? null : v;
}

String? get _home =>
    _env('USERPROFILE') ?? _env('HOME');

/// Cloud folders present on this machine.
///
/// Detection is by well-known path, deliberately: reading a provider's config
/// files to find a relocated folder means parsing four undocumented formats
/// that change without notice. If someone has moved theirs, "Choose a
/// folder…" covers it in one click and cannot break.
/// Which detected cloud folder [path] lives inside, if any.
///
/// This is what tells the UI a notebook *is* syncing. The previous status used
/// "more than one device has written a log", which is a different question and
/// answers "no" for the whole period between setting sync up and a second
/// device actually appearing — exactly when a user most wants confirmation
/// that it worked.
/// [also] carries folders the **user told us about** — the one they picked in
/// "Choose a folder…", or the shared folder they joined a notebook from. Those
/// are checked first, and they are the reason this function can be trusted.
///
/// Detection alone cannot be: it is a list of ~15 well-known paths probed with
/// `existsSync`, so it answers "no" for a perfectly good sync folder that
/// simply is not on the list (a self-hosted Nextcloud anywhere but `~/Nextcloud`,
/// a relocated OneDrive, a Google Drive on a letter outside G–Q), **and** it
/// answers "no" for a folder that is on the list but has not mounted yet.
/// That second case is why the chip could go grey after a restart and stay
/// grey: cloud clients mount asynchronously, so a probe made two seconds after
/// launch fails where the same probe a minute later succeeds. A remembered
/// folder does not have that failure mode, because it is a fact the user gave
/// us rather than a guess we re-derive on every paint.
CloudFolder? cloudFolderContaining(String path,
    {List<CloudFolder> also = const []}) {
  for (final f in [...also, ...detectCloudFolders()]) {
    if (p.isWithin(f.path, path) || p.equals(f.path, path)) return f;
  }
  return null;
}

/// A folder the user chose, described the way the UI wants to name it.
///
/// Recognised as a known provider when it *is* one (so "Choose a folder…" onto
/// your OneDrive still says OneDrive and shows OneDrive's caveat); otherwise
/// named after the folder itself, which is what the user will recognise.
CloudFolder describeChosenFolder(String path) {
  for (final f in detectCloudFolders()) {
    if (p.equals(f.path, path) || p.isWithin(f.path, path)) {
      return CloudFolder(name: f.name, path: path, kind: f.kind);
    }
  }
  final base = p.basename(p.normalize(path));
  return CloudFolder(
      name: base.isEmpty ? path : base, path: path, kind: CloudKind.other);
}

List<CloudFolder> detectCloudFolders() {
  final home = _home;
  final out = <CloudFolder>[];
  if (home == null) return out;

  void add(String name, String path, CloudKind kind) {
    if (!Directory(path).existsSync()) return;
    if (out.any((f) => p.equals(f.path, path))) return;
    final letter = _driveLetterOf(path);
    out.add(CloudFolder(
      name: name,
      path: path,
      kind: kind,
      // Only for a mounted drive. A folder under the home directory has no
      // label to read, and asking for one would be a syscall per candidate on
      // a path that runs on every open of the sync dialog.
      account: letter == null ? null : platformVolumeLabel(letter),
    ));
  }

  // ── Google Drive ──
  if (Platform.isWindows) {
    // The current client mounts a virtual drive; "My Drive" is the synced root.
    // One letter PER SIGNED-IN ACCOUNT, which is why the row needs the volume
    // label to be distinguishable — see [CloudFolder.account].
    for (final letter in 'GHIJKLMNOPQ'.split('')) {
      add('Google Drive', '$letter:\\My Drive', CloudKind.googleDrive);
    }
  }
  add('Google Drive', p.join(home, 'Google Drive'), CloudKind.googleDrive);
  add('Google Drive', p.join(home, 'GoogleDrive'), CloudKind.googleDrive);
  if (Platform.isMacOS) {
    add('Google Drive',
        p.join(home, 'Library', 'CloudStorage', 'GoogleDrive'),
        CloudKind.googleDrive);
  }

  // ── OneDrive ──
  final od = _env('OneDrive') ?? _env('OneDriveConsumer');
  if (od != null) add('OneDrive', od, CloudKind.oneDrive);
  final odc = _env('OneDriveCommercial');
  if (odc != null) add('OneDrive (work)', odc, CloudKind.oneDrive);
  add('OneDrive', p.join(home, 'OneDrive'), CloudKind.oneDrive);

  // ── iCloud Drive ──
  if (Platform.isMacOS) {
    add(
        'iCloud Drive',
        p.join(home, 'Library', 'Mobile Documents', 'com~apple~CloudDocs'),
        CloudKind.iCloud);
  }
  if (Platform.isWindows) {
    add('iCloud Drive', p.join(home, 'iCloudDrive'), CloudKind.iCloud);
  }

  // ── Dropbox ──
  add('Dropbox', p.join(home, 'Dropbox'), CloudKind.dropbox);

  // ── Self-hosted / peer-to-peer ──
  add('Nextcloud', p.join(home, 'Nextcloud'), CloudKind.nextcloud);
  add('ownCloud', p.join(home, 'ownCloud'), CloudKind.nextcloud);
  add('Syncthing', p.join(home, 'Sync'), CloudKind.syncthing);
  add('Syncthing', p.join(home, 'Syncthing'), CloudKind.syncthing);

  return out;
}

/// Advice shown next to a chosen folder.
///
/// Providers differ in ways that matter to an append-only log, and saying so
/// up front is cheaper than debugging it later with a confused user.
String? cloudCaveat(CloudKind kind) => switch (kind) {
      CloudKind.googleDrive =>
        'Google Drive mounts files on demand. Turn on "Available offline" for '
            'the notebook folder so your notes work without a connection.',
      CloudKind.oneDrive =>
        'OneDrive Files On-Demand can leave files as placeholders. Right-click '
            'the notebook folder ▸ "Always keep on this device".',
      CloudKind.iCloud =>
        'iCloud may evict files it thinks are unused. If a notebook seems '
            'empty after a while, open its folder in Finder to fetch it back.',
      CloudKind.dropbox =>
        'If you use Dropbox Smart Sync, set the notebook folder to "Local".',
      CloudKind.syncthing || CloudKind.nextcloud =>
        'Good choice for self-hosting — this stays entirely on machines you '
            'control.',
      CloudKind.other => null,
    };
