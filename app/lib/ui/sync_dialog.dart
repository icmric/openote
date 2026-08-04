/// Sync, mirrors and backups — where a notebook's files live.
///
/// The whole mechanism is one idea: put the notebook where a sync client can
/// already see it. No sign-in, no permissions grant, no account, and nothing
/// exposed to the network by Openote.
///
/// The dialog has two faces, because "not set up yet" and "set up" are
/// different questions. Showing the folder chooser to someone who already
/// picked a folder reads as though nothing happened — which is exactly what it
/// did read as.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/platform_open.dart';
import '../state/app_state.dart';
import '../sync/cloud_folders.dart';
import '../sync/mirrors.dart';
import '../theme/onote_theme.dart';
import 'notebook_manager.dart';

Future<void> showSyncDialog(BuildContext context, AppState app) async {
  final nb = app.notebookId;
  if (nb == null) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _SyncDialog(app: app, notebookId: nb),
  );
}

class _SyncDialog extends StatefulWidget {
  const _SyncDialog({required this.app, required this.notebookId});
  final AppState app;
  final String notebookId;

  @override
  State<_SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<_SyncDialog> {
  AppState get app => widget.app;
  String get nb => widget.notebookId;

  late List<CloudFolder> _folders = detectCloudFolders();
  bool _busy = false;
  String? _error;

  /// Show the folder chooser even when already synced — "move this somewhere
  /// else" is a real thing to want.
  bool _changing = false;

  Future<void> _moveTo(String dir, {String? subfolder}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final target = subfolder == null ? dir : p.join(dir, subfolder);
      final path = await app.moveNotebookToFolder(nb, target);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _changing = false;
        _folders = detectCloudFolders();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 7),
        content: Text('Notebook moved to $path — open Openote on your other '
            'device and add it from the same folder.'),
      ));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _chooseFolder() async {
    final dir = await getDirectoryPath(confirmButtonText: 'Sync here');
    if (dir != null) await _moveTo(dir, subfolder: 'Openote');
  }

  Future<void> _addMirror({required bool backup}) async {
    final dir = await getDirectoryPath(
        confirmButtonText: backup ? 'Back up here' : 'Mirror here');
    if (dir == null || !mounted) return;
    app.addMirror(
        nb, MirrorTarget(path: dir, keepVersions: backup ? 10 : 0));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final status = app.syncStatus(nb);
    final path = app.notebookPath(nb);
    final showChooser = !status.isSynced || _changing;

    return AlertDialog(
      title: Row(children: [
        Icon(status.icon, size: 19, color: status.isSynced ? OnoteColors.success : null),
        const SizedBox(width: 8),
        Text(status.isSynced ? 'Syncing' : 'Sync this notebook'),
      ]),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (status.isSynced) _linkedCard(status, path),
              if (status.isSynced) const SizedBox(height: 4),
              if (!status.isSynced)
                const Text(
                  'Openote syncs through a folder your cloud already keeps in '
                  'step — no account, no sign-in, and no access to the rest of '
                  'your Drive. Each device only ever writes its own file, so '
                  'your devices can never produce a conflicting copy.',
                  style: TextStyle(fontSize: 12.5, height: 1.45),
                ),
              if (showChooser) ...[
                const Divider(height: 22),
                if (_changing)
                  const Text('Move it somewhere else',
                      style:
                          TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                if (_folders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'No cloud folders detected. If you use Drive, OneDrive, '
                      'iCloud, Dropbox, Nextcloud or Syncthing, install its '
                      'desktop app first — or pick any folder below (a network '
                      'share or a USB drive works too).',
                      style: TextStyle(fontSize: 12, height: 1.4),
                    ),
                  )
                else
                  ..._folders.map(_folderTile),
                const SizedBox(height: 6),
                Row(children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _chooseFolder,
                    icon: const Icon(Icons.folder_open, size: 17),
                    label: const Text('Choose a folder…'),
                  ),
                  if (_changing) ...[
                    const SizedBox(width: 8),
                    TextButton(
                        onPressed: () => setState(() => _changing = false),
                        child: const Text('Cancel')),
                  ],
                ]),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style:
                        const TextStyle(fontSize: 12, color: OnoteColors.danger)),
              ],
              const Divider(height: 22),
              _StorageSection(app: app, notebookId: nb),
              const Divider(height: 22),
              _mirrorSection(),
              const Divider(height: 22),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: app.autoSync,
                onChanged: _busy
                    ? null
                    : (v) {
                        // setAutoSync notifies listeners itself; wrapping it in
                        // setState would notify during a build.
                        app.setAutoSync(v);
                        setState(() {});
                      },
                title: const Text('Pull changes automatically',
                    style: TextStyle(fontSize: 12.5)),
                subtitle: const Text(
                    "Watches for other devices' changes and folds them in.",
                    style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(height: 6),
              const Text(
                'Running your own server? Point Syncthing, Nextcloud, or an '
                'rsync job at the same folder — Openote never talks to a '
                'server itself, so anything that copies files works and '
                'nothing is exposed to the network by Openote.',
                style: TextStyle(fontSize: 11.5, height: 1.4),
              ),
            ],
          ),
        ),
      ),
      actions: [
        // Reported: adding a notebook is hard to find. This dialog is where
        // people arrive when they are thinking about *where their notebooks
        // live*, so "add another one" belongs in the same thought — even
        // though the manager is the surface that owns it. One Row, because
        // AlertDialog.actions is an OverflowBar and a Spacer there throws.
        Row(children: [
          TextButton.icon(
            icon: const Icon(Icons.library_add_outlined, size: 17),
            label: const Text('Add a notebook…'),
            onPressed: _busy
                ? null
                : () async {
                    final navigator = Navigator.of(context);
                    final ctx = context;
                    navigator.pop();
                    if (ctx.mounted) await showNotebookManager(ctx, app);
                  },
          ),
          const Spacer(),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ]),
      ],
    );
  }

  /// The "you are already set up" card. Answering "where is it, is anything
  /// else using it, and how do I change it" in one glance is the whole job —
  /// re-offering the folder chooser instead read as "nothing happened".
  Widget _linkedCard(SyncStatus status, String? path) {
    final folder = status.folder!;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: OnoteColors.success.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(_iconFor(folder.kind), size: 16, color: OnoteColors.success),
            const SizedBox(width: 8),
            Expanded(
              child: Text('In your ${folder.name} folder',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 4),
          if (path != null)
            SelectableText(path,
                style: const TextStyle(
                    fontSize: 11, color: OnoteColors.graphite400)),
          const SizedBox(height: 2),
          Text(
            status.hasOtherDevices
                ? '${status.devices} devices have edited this notebook.'
                : 'No other device has picked it up yet — install Openote '
                    'there and open it from the same folder.',
            style:
                const TextStyle(fontSize: 11.5, height: 1.35),
          ),
          if (cloudCaveat(folder.kind) != null) ...[
            const SizedBox(height: 6),
            Text(cloudCaveat(folder.kind)!,
                style: const TextStyle(
                    fontSize: 11, height: 1.35, color: OnoteColors.graphite400)),
          ],
          const SizedBox(height: 6),
          Row(children: [
            if (path != null)
              TextButton.icon(
                onPressed: () => PlatformOpen.file(p.dirname(path)),
                icon: const Icon(Icons.folder_open, size: 15),
                label: const Text('Open folder', style: TextStyle(fontSize: 12)),
              ),
            TextButton.icon(
              onPressed: _busy ? null : () => setState(() => _changing = true),
              icon: const Icon(Icons.drive_file_move_outline, size: 15),
              label:
                  const Text('Move elsewhere', style: TextStyle(fontSize: 12)),
            ),
          ]),
        ],
      ),
    );
  }

  /// Mirrors and backups: a second copy, one way, never read back.
  Widget _mirrorSection() {
    final targets = app.mirrorsFor(nb);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Extra copies',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        const Text(
          'A mirror keeps one up-to-date copy somewhere else; a backup keeps '
          'the last ten dated snapshots. Both are one-way and never read back, '
          'so they are safe to point at a second cloud, a NAS or a USB stick '
          'without any risk of two devices fighting over the same file.',
          style: TextStyle(
              fontSize: 11.5, height: 1.4, color: OnoteColors.graphite400),
        ),
        const SizedBox(height: 6),
        for (final t in targets)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            leading: Icon(t.isBackup ? Icons.history : Icons.copy_all_outlined,
                size: 18),
            title: Text(p.basename(t.path), style: const TextStyle(fontSize: 12.5)),
            subtitle: Text(
              '${t.isBackup ? 'Backup · keeps ${t.keepVersions}' : 'Mirror'} · ${t.path}',
              style: const TextStyle(fontSize: 10.5),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 15),
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                app.removeMirror(nb, t.path);
                setState(() {});
              },
            ),
          ),
        Row(children: [
          TextButton.icon(
            onPressed: _busy ? null : () => _addMirror(backup: false),
            icon: const Icon(Icons.copy_all_outlined, size: 15),
            label: const Text('Add a mirror…', style: TextStyle(fontSize: 12)),
          ),
          TextButton.icon(
            onPressed: _busy ? null : () => _addMirror(backup: true),
            icon: const Icon(Icons.history, size: 15),
            label: const Text('Add a backup…', style: TextStyle(fontSize: 12)),
          ),
          if (targets.isNotEmpty)
            TextButton(
              onPressed: () async {
                await app.runMirrors(nb, force: true);
                if (mounted) setState(() {});
              },
              child: const Text('Run now', style: TextStyle(fontSize: 12)),
            ),
        ]),
      ],
    );
  }

  Widget _folderTile(CloudFolder f) {
    final caveat = cloudCaveat(f.kind);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(_iconFor(f.kind), size: 20),
      title: Text(f.name, style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        caveat ?? f.path,
        style: const TextStyle(fontSize: 11, height: 1.3),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: TextButton(
        onPressed: _busy ? null : () => _moveTo(f.path, subfolder: 'Openote'),
        child: const Text('Use', style: TextStyle(fontSize: 12)),
      ),
    );
  }
}

String _bytes(int n) {
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
  if (n < 1024 * 1024 * 1024) {
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(n / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Where this notebook's bytes are, said plainly — and what else is lying
/// around that nothing points at.
///
/// The reason this exists: a notebook can sit on this machine with its logs
/// beside it while old copies of it sit in a cloud folder, and every surface
/// in the app read that as "synced". It wasn't. Naming the two paths is the
/// only answer that can't mislead.
class _StorageSection extends StatefulWidget {
  const _StorageSection({required this.app, required this.notebookId});
  final AppState app;
  final String notebookId;

  @override
  State<_StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends State<_StorageSection> {
  AppState get app => widget.app;
  late Future<NotebookStorage> _storage = app.storageFor(widget.notebookId);
  Future<List<OrphanFile>>? _orphans;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Where this notebook lives',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        FutureBuilder<NotebookStorage>(
          future: _storage,
          builder: (_, snap) {
            final s = snap.data;
            if (s == null) {
              return const Text('Measuring…',
                  style: TextStyle(
                      fontSize: 11.5, color: OnoteColors.graphite400));
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('Notes', s.containerPath, s.containerBytes,
                    s.containerCloud, isContainer: true),
                const SizedBox(height: 6),
                _row('Sync log', s.logPath, s.logBytes, s.logCloud,
                    missing: !s.logExists),
                const SizedBox(height: 8),
                Text(
                  s.syncs
                      ? 'The sync log is in your ${s.logCloud!.name} folder, '
                          'so this notebook reaches your other devices.'
                      : s.containerCloud != null
                          ? 'The notes file is in your '
                              '${s.containerCloud!.name} folder but the sync '
                              'log is not — so it is being re-uploaded on '
                              'every save without actually syncing. Use '
                              '"Move elsewhere" above to put both in place.'
                          : 'Both are on this computer only. Pick a folder '
                              'above to sync this notebook.',
                  style: const TextStyle(fontSize: 11.5, height: 1.4),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        if (_orphans == null)
          TextButton.icon(
            onPressed: () => setState(
                () => _orphans = app.findOrphanFiles()),
            icon: const Icon(Icons.cleaning_services_outlined, size: 15),
            label: const Text('Find leftover files…',
                style: TextStyle(fontSize: 12)),
          )
        else
          _orphanList(),
      ],
    );
  }

  Widget _row(String label, String path, int bytes, CloudFolder? cloud,
      {bool isContainer = false, bool missing = false}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 62,
        child: Text(label,
            style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .4,
                color: OnoteColors.graphite400)),
      ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(path,
                style: const TextStyle(fontSize: 10.5, height: 1.3)),
            Row(children: [
              Icon(
                  missing
                      ? Icons.help_outline
                      : cloud != null
                          ? Icons.cloud_done_outlined
                          : Icons.computer_outlined,
                  size: 12,
                  color: cloud != null
                      ? OnoteColors.success
                      : OnoteColors.graphite400),
              const SizedBox(width: 4),
              Text(
                missing
                    ? 'not created yet'
                    : '${cloud?.name ?? 'this computer'} · ${_bytes(bytes)}',
                style: const TextStyle(
                    fontSize: 10.5, color: OnoteColors.graphite400),
              ),
            ]),
          ],
        ),
      ),
      IconButton(
        icon: const Icon(Icons.folder_open, size: 14),
        visualDensity: VisualDensity.compact,
        tooltip: 'Open containing folder',
        onPressed: () => PlatformOpen.file(
            isContainer ? p.dirname(path) : path),
      ),
    ]);
  }

  Widget _orphanList() => FutureBuilder<List<OrphanFile>>(
        future: _orphans,
        builder: (_, snap) {
          final list = snap.data;
          if (list == null) {
            return const Text('Looking…',
                style:
                    TextStyle(fontSize: 11.5, color: OnoteColors.graphite400));
          }
          if (list.isEmpty) {
            return const Text('No leftover notebook files found.',
                style:
                    TextStyle(fontSize: 11.5, color: OnoteColors.graphite400));
          }
          final safe = list.where((o) => o.safeToDelete).toList();
          final safeBytes = safe.fold<int>(0, (a, o) => a + o.bytes);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${list.length} leftover file'
                  '${list.length == 1 ? '' : 's'} nothing points at',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              for (final o in list.take(8))
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(children: [
                    Icon(o.isLog ? Icons.history : Icons.description_outlined,
                        size: 12, color: OnoteColors.graphite400),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('${p.basename(o.path)}  ·  ${_bytes(o.bytes)}'
                          '${o.safeToDelete ? '' : '  ·  shared folder'}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5)),
                    ),
                  ]),
                ),
              const SizedBox(height: 4),
              // Only workspace files are ever deleted from here: a leftover in
              // a SHARED folder may be another device's notebook this machine
              // has never joined, and removing it would destroy data this
              // device never owned.
              const Text(
                'Files in a shared folder are left alone — they may belong to '
                'another device. Open the folder to review those yourself.',
                style: TextStyle(
                    fontSize: 10.5, height: 1.35, color: OnoteColors.graphite400),
              ),
              if (safe.isNotEmpty)
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          final freed = await app.deleteOrphans(safe);
                          if (!mounted) return;
                          setState(() {
                            _busy = false;
                            _orphans = app.findOrphanFiles();
                            _storage = app.storageFor(widget.notebookId);
                          });
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content:
                                  Text('Reclaimed ${_bytes(freed)}')));
                        },
                  icon: const Icon(Icons.delete_outline, size: 15),
                  label: Text(
                      'Delete ${safe.length} on this computer '
                      '(${_bytes(safeBytes)})',
                      style: const TextStyle(fontSize: 12)),
                ),
            ],
          );
        },
      );
}

IconData _iconFor(CloudKind k) => switch (k) {
      CloudKind.googleDrive => Icons.add_to_drive,
      CloudKind.oneDrive => Icons.cloud_outlined,
      CloudKind.iCloud => Icons.cloud_queue,
      CloudKind.dropbox => Icons.inventory_2_outlined,
      CloudKind.syncthing || CloudKind.nextcloud => Icons.dns_outlined,
      CloudKind.other => Icons.folder_outlined,
    };

/// Notebooks already sitting in a cloud folder, found by looking rather than
/// by asking.
///
/// The single most useful thing onboarding can do on a second machine is
/// notice the notebook that is already there. Scans one level under each
/// detected cloud folder plus an `Openote` subfolder — deep enough to find
/// what the sync dialog itself creates, shallow enough not to walk somebody's
/// whole Drive.
List<({String name, String path, CloudFolder folder})> findExistingNotebooks() {
  final out = <({String name, String path, CloudFolder folder})>[];
  final seen = <String>{};
  for (final cloud in detectCloudFolders()) {
    for (final root in [cloud.path, p.join(cloud.path, 'Openote')]) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      try {
        for (final e in dir.listSync(followLinks: false)) {
          if (e is! File || p.extension(e.path) != '.onote') continue;
          if (!seen.add(e.path)) continue;
          out.add((
            name: p.basenameWithoutExtension(e.path),
            path: e.path,
            folder: cloud
          ));
        }
      } catch (_) {
        // An unreadable cloud folder (offline placeholder, permissions) must
        // not break onboarding.
      }
    }
  }
  return out;
}
