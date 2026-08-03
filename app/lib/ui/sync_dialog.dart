/// "Sync this notebook" — pick a folder your cloud already syncs.
///
/// The whole flow is one dialog because the whole mechanism is one idea: put
/// the notebook where your existing sync client can see it. No sign-in, no
/// permissions grant, no account.
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../sync/cloud_folders.dart';
import '../theme/onote_theme.dart';

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
  late final List<CloudFolder> _folders = detectCloudFolders();
  bool _busy = false;
  String? _error;

  Future<void> _moveTo(String dir, {String? subfolder}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final target = subfolder == null ? dir : '$dir/$subfolder';
      final path = await app.moveNotebookToFolder(widget.notebookId, target);
      if (!mounted) return;
      Navigator.of(context).pop();
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

  @override
  Widget build(BuildContext context) {
    final path = app.notebookPath(widget.notebookId);
    final devices = app.syncDeviceCount(widget.notebookId);
    return AlertDialog(
      title: const Text('Sync this notebook'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Openote syncs through a folder your cloud already keeps in '
                'step — no account, no sign-in, and no access to the rest of '
                'your Drive. Each device only ever writes its own file, so '
                'your devices can never produce a conflicting copy.',
                style: TextStyle(fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 14),
              if (path != null)
                Text('Currently at: $path',
                    style: const TextStyle(
                        fontSize: 11, color: OnoteColors.graphite400)),
              if (devices > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('$devices devices have edited this notebook.',
                      style: const TextStyle(
                          fontSize: 11, color: OnoteColors.graphite400)),
                ),
              const Divider(height: 22),
              if (_folders.isEmpty)
                const Text(
                  'No cloud folders detected. If you use Drive, OneDrive, '
                  'iCloud, Dropbox, Nextcloud or Syncthing, install its '
                  'desktop app first — or pick any folder below (a network '
                  'share or a USB drive works too).',
                  style: TextStyle(fontSize: 12, height: 1.4),
                )
              else
                ..._folders.map(_folderTile),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _busy ? null : _chooseFolder,
                icon: const Icon(Icons.folder_open, size: 17),
                label: const Text('Choose a folder…'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(
                        fontSize: 12, color: OnoteColors.danger)),
              ],
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
                    'Watches for other devices\' changes and folds them in.',
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
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
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

  static IconData _iconFor(CloudKind k) => switch (k) {
        CloudKind.googleDrive => Icons.add_to_drive,
        CloudKind.oneDrive => Icons.cloud_outlined,
        CloudKind.iCloud => Icons.cloud_queue,
        CloudKind.dropbox => Icons.inventory_2_outlined,
        CloudKind.syncthing || CloudKind.nextcloud => Icons.dns_outlined,
        CloudKind.other => Icons.folder_outlined,
      };
}
