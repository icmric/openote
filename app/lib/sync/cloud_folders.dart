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

import 'package:path/path.dart' as p;

/// A sync location we can offer the user.
class CloudFolder {
  const CloudFolder({
    required this.name,
    required this.path,
    required this.kind,
  });

  final String name;
  final String path;
  final CloudKind kind;

  /// Whether the directory still exists — a provider can be uninstalled.
  bool get exists => Directory(path).existsSync();
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
CloudFolder? cloudFolderContaining(String path) {
  for (final f in detectCloudFolders()) {
    if (p.isWithin(f.path, path) || p.equals(f.path, path)) return f;
  }
  return null;
}

List<CloudFolder> detectCloudFolders() {
  final home = _home;
  final out = <CloudFolder>[];
  if (home == null) return out;

  void add(String name, String path, CloudKind kind) {
    if (!Directory(path).existsSync()) return;
    if (out.any((f) => p.equals(f.path, path))) return;
    out.add(CloudFolder(name: name, path: path, kind: kind));
  }

  // ── Google Drive ──
  if (Platform.isWindows) {
    // The current client mounts a virtual drive; "My Drive" is the synced root.
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
