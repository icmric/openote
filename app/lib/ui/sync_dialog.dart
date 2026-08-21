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
import '../store/media_gc.dart' show VideoSweep;
import '../store/repository.dart'
    show BlobReclaim, ContainerDemotion, SpaceReclaim;
import '../sync/cloud_folders.dart';
import '../sync/github_api.dart';
import '../sync/mirrors.dart';
import '../theme/onote_theme.dart';
import 'notebook_manager.dart';
import '../theme/tokens.dart';
import 'onote_dialog.dart';

Future<void> showSyncDialog(BuildContext context, AppState app) async {
  final nb = app.notebookId;
  if (nb == null) return;
  await showOnoteDialog<void>(
    context: context,
    builder: (_) => _SyncDialog(app: app, notebookId: nb),
  );
}

/// "3s ago", for the sync readout. [absent] when there is no time yet.
String _ago(DateTime? t, String absent, String label) {
  if (t == null) return absent;
  final s = DateTime.now().difference(t).inSeconds;
  final when = s < 2
      ? 'just now'
      : s < 60
          ? '${s}s ago'
          : s < 3600
              ? '${s ~/ 60} min ago'
              : '${s ~/ 3600} h ago';
  return '$label $when.';
}

/// The foldable halves of the dialog.
enum _Pane { git, mirrors, storage }

/// A section header that stands on its own, and its contents when opened.
///
/// Not an `ExpansionTile`: that draws its own dividers and its own padding,
/// animates a chevron on the wrong side, and cannot show a value beside the
/// title without fighting its `subtitle` slot. What is needed here is a row
/// that answers the question when closed — "Sync with git · github.com/you/n"
/// — so that opening it is a choice rather than the only way to find out.
class _Disclosure extends StatelessWidget {
  const _Disclosure({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.open,
    required this.onTap,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool open;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
            child: Row(children: [
              Icon(icon, size: 16, color: s.textSecondary),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              // Flexible, because a remote address and a folder name are both
              // user data of unbounded length in a fixed-width dialog.
              Flexible(
                child: Text(subtitle,
                    style: TextStyle(fontSize: 12, color: s.textSecondary),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    textAlign: TextAlign.right),
              ),
              const SizedBox(width: 4),
              Icon(open ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: s.textSecondary),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
            child: child,
          ),
        Divider(height: 1, color: s.border),
      ],
    );
  }
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

  /// Which of the folded sections is open, if any. One at a time: the whole
  /// point is that the dialog is short enough to read.
  _Pane? _open;

  Future<void> _moveTo(String dir, {String? subfolder}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final target = subfolder == null ? dir : p.join(dir, subfolder);
      // Remember what the user actually PICKED, before the move records the
      // subfolder it created inside it. Both work for "is this synced?", but
      // the pick is the one with a name worth showing — "Nextcloud", not
      // "Openote".
      app.rememberSyncRoot(dir);
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
    // A notebook synced through git is still not in a cloud folder, so the
    // folder chooser is still the answer to a question it has not been asked.
    final showChooser = !status.isFolderSynced || _changing;

    return AlertDialog(
      title: Row(children: [
        Icon(status.icon, size: 18, color: status.isSynced ? OnoteColors.success : null),
        const SizedBox(width: 8),
        Text(status.isSynced ? 'Syncing' : 'Sync this notebook'),
      ]),
      content: SizedBox(
        width: 480,
        // **Bounded.** This was a SingleChildScrollView with no height
        // constraint, so on a synced notebook with git on, two backups and the
        // storage figures open it measured well over a viewport — the dialog
        // filled the window and every answer was somewhere in a long scroll.
        // 460 is the number the notebook manager already uses.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 460),
          // **Listening.** Nothing here subscribed to AppState: every value it
          // reads — the status, gitStatus, gitBusy — was a snapshot refreshed
          // only by an explicit setState after a click. A sync that finished
          // on the 60-second timer, or a status written by a background push,
          // updated the state and left this dialog showing the old one.
          child: ListenableBuilder(
            listenable: app,
            builder: (context, _) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // `isFolderSynced`, not `isSynced`. This card is about a FOLDER
              // — it names one, and it offers "move it elsewhere" — and since
              // git started counting as synced, a git-only notebook reached it
              // with no folder to name. Same null assertion that took the
              // status chip down.
              if (status.isFolderSynced) _linkedCard(status, path),
              if (status.isFolderSynced) const SizedBox(height: 4),
              _containerInCloudCard(),
              if (!status.isFolderSynced)
                const Text(
                  'Openote syncs through a folder your cloud already keeps in '
                  'step — no account, no sign-in, and no access to the rest of '
                  'your Drive. Each device only ever writes its own file, so '
                  'your devices can never produce a conflicting copy.',
                  style: TextStyle(fontSize: 13, height: 1.45),
                ),
              if (showChooser) ...[
                const Divider(height: 22),
                if (_changing)
                  const Text('Move it somewhere else',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
                    icon: const Icon(Icons.folder_open, size: 18),
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
              const SizedBox(height: 12),
              _ComputerNameField(app: app, notebookId: nb),
              // ── The rest, folded away until asked for.
              //
              // These four are separate questions — "where are the files",
              // "keep it in git", "make me copies", "check for changes on my
              // own" — and only one of them is ever the reason someone opened
              // this. Stacked open they were four screens of controls and
              // prose above the fold, which is what "very cluttered and hard
              // to read" describes. One opens at a time.
              const Divider(height: 22),
              _Disclosure(
                icon: Icons.commit,
                title: 'Sync with git',
                // The subtitle answers the question without opening anything,
                // which is most of what a collapsed section is for.
                subtitle: app.gitEnabled
                    ? (app.gitRemote == null
                        ? 'On — this computer only'
                        : SyncStatus(
                                folder: null,
                                devices: 1,
                                mirrors: 0,
                                gitRemote: app.gitRemote)
                            .gitLabel!)
                    : 'Off',
                open: _open == _Pane.git,
                onTap: () => setState(
                    () => _open = _open == _Pane.git ? null : _Pane.git),
                child: _GitSection(app: app),
              ),
              _Disclosure(
                icon: Icons.folder_copy_outlined,
                title: 'Extra copies',
                subtitle: app.mirrorsFor(nb).isEmpty
                    ? 'None'
                    : '${app.mirrorsFor(nb).length} configured',
                open: _open == _Pane.mirrors,
                onTap: () => setState(() =>
                    _open = _open == _Pane.mirrors ? null : _Pane.mirrors),
                child: _mirrorSection(),
              ),
              _Disclosure(
                icon: Icons.sd_storage_outlined,
                title: 'Where the files are',
                subtitle: 'Sizes, paths and leftovers',
                open: _open == _Pane.storage,
                onTap: () => setState(() =>
                    _open = _open == _Pane.storage ? null : _Pane.storage),
                child: _StorageSection(app: app, notebookId: nb),
              ),
              const Divider(height: 12),
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
                    style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                    "Watches for other devices' changes and folds them in.",
                    style: TextStyle(fontSize: 11)),
              ),
              // **Say whether it is actually working.**
              //
              // Reported twice: "it seems like that change doesnt really ever
              // get reflected on the other machine". Whether the watcher was
              // armed, whether anything had arrived, and whether a pull had
              // run were all invisible — so the only way to diagnose it was to
              // press the button and guess. A switch that claims to watch
              // should be able to say that it is.
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 4),
                child: Row(children: [
                  Icon(
                      app.watchingForChanges
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 14,
                      color: app.watchingForChanges
                          ? OnoteColors.success
                          : OnoteColors.danger),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      app.watchingForChanges
                          ? 'Watching this notebook. '
                              '${_ago(app.lastForeignSignalAt, 'Nothing has arrived yet.', 'Last change seen')}'
                              '${app.lastPullAt == null ? '' : ' ${_ago(app.lastPullAt, '', 'Last pull')} (${app.lastSyncPull} changes).'}'
                          : 'NOT watching — ${app.notWatchingBecause}.',
                      style: TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: context.surfaces.textSecondary),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 6),
              // The old version of this ended "Openote never talks to a
              // server itself … nothing is exposed to the network by
              // Openote". That was true when folder sync was the only route
              // and it stopped being true the moment git and the GitHub API
              // shipped. A privacy claim that has quietly become false is
              // worse than no claim at all.
              const Text(
                'Running your own server? Point Syncthing, Nextcloud, or an '
                'rsync job at the same folder — anything that copies files '
                'works.',
                style: TextStyle(fontSize: 12, height: 1.4),
              ),
            ],
          ),
            ),
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
            icon: const Icon(Icons.library_add_outlined, size: 18),
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
  /// One button for a notebook an older build moved bodily into the cloud
  /// folder — the working file and all.
  ///
  /// **Nothing here happens on its own.** The file is in the user's Drive, and
  /// Openote does not move or delete things in someone's cloud folder without
  /// being asked. So this is an offer, in plain words, with the reason a year
  /// 10 student can act on ("a sync app can damage it") and every technical
  /// word — WAL, SQLite, container, torn database — behind Advanced, matching
  /// `open_notice_dialog.dart` and `save_problem_dialog.dart`.
  Widget _containerInCloudCard() {
    final folder = app.containerSyncFolder(nb);
    if (folder == null) return const SizedBox.shrink();
    final path = app.notebookPath(nb);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: OnoteColors.danger.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.warning_amber_rounded,
                size: 16, color: OnoteColors.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text('This notebook keeps a working file in ${folder.name}',
                  style: OnoteType.uiStrong),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            'Openote uses that file to open this notebook quickly. It is not '
            'the notes themselves, and it should stay on this computer: while '
            '${folder.name} is copying it, Openote may be writing to it, and '
            'that can damage the notebook.\n\n'
            'Moving it out changes nothing you can see. Your notes stay in '
            '${folder.name} and keep syncing to your other devices exactly as '
            'they do now.',
            style: const TextStyle(fontSize: 12.5, height: 1.45),
          ),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton.icon(
              onPressed: _busy ? null : _moveContainerOut,
              icon: const Icon(Icons.drive_file_move_outline, size: 18),
              label: Text('Move the working file out of ${folder.name}'),
            ),
          ]),
          if (path != null)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              shape: const Border(),
              title: const Text('Details (advanced)',
                  style: TextStyle(fontSize: 12.5)),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    '$path\n\n'
                    'The container is a WAL SQLite database. Its -wal and -shm '
                    'sidecars are replicated independently of the main file, '
                    'so a client that copies them out of step can produce a '
                    'torn database that still passes PRAGMA integrity_check '
                    '(ADR-0006 §2). Moving it copies the file into your '
                    'workspace, checkpoints the WAL first, compares SHA-256 of '
                    'both copies, and only then deletes the original and its '
                    'sidecars. The .onotebook directory is not touched.',
                    style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontFamilyFallback: onoteFontFallback,
                        fontSize: 11),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _moveContainerOut() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.moveContainerOutOfSyncFolder(nb);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration: Duration(seconds: 6),
        content: Text('Done — the working file is back on this computer, and '
            'your notes are still syncing.'),
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

  Widget _linkedCard(SyncStatus status, String? path) {
    final folder = status.folder!;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: OnoteColors.success.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(12),
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
                style: TextStyle(
                    fontSize: 11, color: context.surfaces.textSecondary)),
          const SizedBox(height: 2),
          Text(
            status.hasOtherDevices
                ? '${status.devices} devices have edited this notebook.'
                : 'No other device has picked it up yet — install Openote '
                    'there and open it from the same folder.',
            style:
                const TextStyle(fontSize: 12, height: 1.35),
          ),
          if (cloudCaveat(folder.kind) != null) ...[
            const SizedBox(height: 6),
            Text(cloudCaveat(folder.kind)!,
                style: TextStyle(
                    fontSize: 11, height: 1.35, color: context.surfaces.textSecondary)),
          ],
          const SizedBox(height: 6),
          Row(children: [
            if (path != null)
              TextButton.icon(
                onPressed: () => PlatformOpen.file(p.dirname(path)),
                icon: const Icon(Icons.folder_open, size: 16),
                label: const Text('Open folder', style: TextStyle(fontSize: 12)),
              ),
            TextButton.icon(
              onPressed: _busy ? null : () => setState(() => _changing = true),
              icon: const Icon(Icons.drive_file_move_outline, size: 16),
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
        // No heading: the disclosure row that opened this is still on screen
        // directly above and already says "Extra copies", in the same size and
        // the same weight.
        const SizedBox(height: 2),
        Text(
          'A mirror keeps one up-to-date copy somewhere else; a backup keeps '
          'the last ten dated snapshots. Both are one-way and never read back, '
          'so they are safe to point at a second cloud, a NAS or a USB stick '
          'without any risk of two devices fighting over the same file.',
          style: TextStyle(
              fontSize: 12, height: 1.4, color: context.surfaces.textSecondary),
        ),
        const SizedBox(height: 6),
        for (final t in targets)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            leading: Icon(t.isBackup ? Icons.history : Icons.copy_all_outlined,
                size: 18),
            title: Text(p.basename(t.path), style: const TextStyle(fontSize: 13)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${t.isBackup ? 'Backup · keeps ${t.keepVersions}' : 'Mirror'} · ${t.path}',
                  style: const TextStyle(fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                // **Whether it is actually working.** This row used to say
                // only where the copy was meant to go; a target that had
                // never once succeeded looked exactly like one that always
                // did.
                if (app.mirrorTroubleFor(nb)[t.path] case final why?)
                  Text(
                    "Couldn't reach this the last time it tried — $why",
                    style: TextStyle(
                        fontSize: 11, color: Theme.of(context).colorScheme.error),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 16),
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
            icon: const Icon(Icons.copy_all_outlined, size: 16),
            label: const Text('Add a mirror…', style: TextStyle(fontSize: 12)),
          ),
          TextButton.icon(
            onPressed: _busy ? null : () => _addMirror(backup: true),
            icon: const Icon(Icons.history, size: 16),
            label: const Text('Add a backup…', style: TextStyle(fontSize: 12)),
          ),
          if (targets.isNotEmpty)
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      // **It says what happened.** It used to give no
                      // feedback of any kind, in either direction, so a
                      // student could not tell a copy that worked from one
                      // that silently failed.
                      setState(() => _busy = true);
                      await app.runMirrors(nb, force: true);
                      if (!mounted) return;
                      setState(() => _busy = false);
                      final bad = app.mirrorTroubleFor(nb);
                      final messenger = ScaffoldMessenger.maybeOf(context);
                      messenger?.showSnackBar(SnackBar(
                        content: Text(bad.isEmpty
                            ? 'Copied to ${targets.length} '
                                '${targets.length == 1 ? 'place' : 'places'}.'
                            : "${bad.length} of ${targets.length} couldn't be "
                                'reached — see the list above.'),
                      ));
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
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        FutureBuilder<NotebookStorage>(
          future: _storage,
          builder: (_, snap) {
            final s = snap.data;
            if (s == null) {
              return Text('Measuring…',
                  style: TextStyle(
                      fontSize: 12, color: context.surfaces.textSecondary));
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('Notes', s.containerPath, s.containerBytes,
                    s.containerCloud, isContainer: true),
                const SizedBox(height: 6),
                _row('Sync log', s.logPath, s.logBytes, s.logCloud,
                    missing: !s.logExists),
                // Said separately because it is the number that can be
                // gigabytes: a video copied into the notebook lives in the
                // sync log directory, so without this line three hours of
                // lectures read as "sync log · 4.1 GB".
                if (s.mediaBytes > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 92, top: 2),
                    child: Text(
                        'including ${_bytes(s.mediaBytes)} of video and '
                        'recordings you copied in',
                        style: TextStyle(
                            fontSize: 11,
                            color: context.surfaces.textSecondary)),
                  ),
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
                          : app.gitRemoteFor(widget.notebookId) != null
                              // Git is a second way of being somewhere else,
                              // and this used to flatly deny it — telling
                              // someone whose notes had just been pushed to
                              // GitHub that they were on this computer only.
                              ? 'The notes are pushed to '
                                  '${app.gitRemoteFor(widget.notebookId)}. '
                                  'The working file stays on this computer, '
                                  'which is deliberate — two machines sharing '
                                  'one is what the sync log prevents.'
                              : 'Both are on this computer only. Pick a '
                                  'folder above to sync this notebook.',
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        // Reclaiming space, which is not the same job as finding leftovers.
        // Deleting a big import frees SQLite pages, but the FILE keeps its
        // high-water mark and the write-ahead log keeps whatever it grew to —
        // measured at 742 free pages and a 4 MB WAL on a real notebook. There
        // was no way to ask for either back.
        Row(children: [
          TextButton.icon(
            onPressed: _reclaiming
                ? null
                : () async {
                    setState(() => _reclaiming = true);
                    // Off the frame: VACUUM rewrites the whole database.
                    final r = await Future(
                        () => app.reclaimFreeSpace(widget.notebookId));
                    if (!mounted) return;
                    setState(() {
                      _reclaiming = false;
                      _reclaimed = r;
                      _storage = app.storageFor(widget.notebookId);
                    });
                  },
            icon: _reclaiming
                ? const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.compress, size: 16),
            label: Text(
                _reclaiming
                    ? 'Compacting…'
                    : _reclaimed == null
                        ? 'Reclaim space'
                        // "Could not run" is no longer spelled the same as
                        // "nothing to do": a compaction that died on a full
                        // disk or a locked file used to say "Nothing to
                        // reclaim" and the user had no way to tell.
                        : !_reclaimed!.ran
                            ? 'Could not tidy up'
                            : _reclaimed!.freed == 0
                                ? 'Nothing to reclaim'
                                : '${_bytes(_reclaimed!.freed)} reclaimed',
                style: TextStyle(
                    fontSize: 12,
                    color: _reclaimed?.ran == false ? OnoteColors.danger : null)),
          ),
          if (_orphans == null)
            TextButton.icon(
              onPressed: () => setState(
                  () => _orphans = app.findOrphanFiles()),
              icon: const Icon(Icons.cleaning_services_outlined, size: 16),
              label: const Text('Find leftovers…',
                  style: TextStyle(fontSize: 12)),
            ),
        ]),
        // Converting handwriting is offered only when there is handwriting to
        // convert, and it says how much: an action whose effect nobody can see
        // beforehand reads as a risk rather than a saving. New ink has been
        // binary since v0.11; this is for pages written before it.
        if (_inkPages == null)
          const SizedBox.shrink()
        else if (_inkPages! > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              TextButton.icon(
                onPressed: _converting
                    ? null
                    : () async {
                        setState(() {
                          _converting = true;
                          _inkResult = null;
                        });
                        final r =
                            await app.convertInkToBinary(widget.notebookId);
                        if (!mounted) return;
                        setState(() {
                          _converting = false;
                          _inkResult = r;
                          _inkPages =
                              app.inlineInkPageCount(widget.notebookId);
                          _storage = app.storageFor(widget.notebookId);
                        });
                      },
                icon: _converting
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.gesture, size: 16),
                label: Text(
                    _converting
                        ? 'Converting handwriting…'
                        : 'Shrink handwriting on $_inkPages '
                            '${_inkPages == 1 ? 'page' : 'pages'}',
                    style: const TextStyle(fontSize: 12)),
              ),
              if (_inkResult != null)
                Expanded(
                  child: Text(_inkResult!.describe(_bytes),
                      style: TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          // A run that changed nothing is not good news, and
                          // showing it in the same grey as a success is how it
                          // went unnoticed for 45 seconds.
                          color: _inkResult!.didNothing
                              ? OnoteColors.danger
                              : context.surfaces.textSecondary)),
                ),
            ]),
          ),
        // Offered only on a notebook that HAS videos, for the same reason the
        // handwriting button is: an action whose effect nobody can see
        // beforehand reads as a risk rather than a saving.
        //
        // A button, not automatic housekeeping, and that is the rule stated at
        // the top of `AppState`'s housekeeping section — only work that is
        // reversible in effect happens on its own, and deleting does not
        // qualify, because "the cost of being wrong is somebody's notes and
        // the cost of asking is one click".
        FutureBuilder<NotebookStorage>(
          future: _storage,
          builder: (_, snap) {
            if ((snap.data?.mediaBytes ?? 0) == 0 && _videos == null) {
              return const SizedBox.shrink();
            }
            if (_videos != null) return _videoList();
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextButton.icon(
                onPressed: () => setState(
                    () => _videos = app.findUnusedVideos(widget.notebookId)),
                icon: const Icon(Icons.videocam_off_outlined, size: 16),
                label: const Text('Check for videos you no longer use…',
                    style: TextStyle(fontSize: 12)),
              ),
            );
          },
        ),
        _tidyPictures(),
        _storageUpgrade(),
        if (_orphans != null) _orphanList(),
      ],
    );
  }

  bool _upgrading = false;
  ContainerDemotion? _upgraded;

  /// The one door to v0.17 Step 8's rename, in both directions.
  ///
  /// **Opt-in, and it stays opt-in.** Nothing runs this on open. Decision 4 of
  /// the plan ships macOS with no human pass, so a one-way v1 → v2 migration
  /// will run for the first time on a platform nobody has driven by hand; the
  /// answer is that the student picks the moment, the app runs indefinitely
  /// without it, and if a problem is ever reported the advice can be "don't
  /// press it yet" rather than "we already did".
  ///
  /// The button that comes back is the inverse, in the same place, because a
  /// rollback nobody can find is not a rollback.
  Widget _storageUpgrade() {
    final done = app.notebookIsDemoted(widget.notebookId);
    final r = _upgraded;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: _upgrading
                ? null
                : (done ? _confirmUndoUpgrade : _confirmUpgrade),
            icon: _upgrading
                ? const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(done ? Icons.undo : Icons.upgrade, size: 16),
            label: Text(
                _upgrading
                    ? 'Working…'
                    : done
                        ? 'Go back to the old way of storing this notebook…'
                        : 'Update how this notebook is stored…',
                style: const TextStyle(fontSize: 12)),
          ),
          if (r != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: Text(
                  r.done
                      ? (done
                          ? 'Done. This notebook now keeps its working file '
                              'tucked away on this computer, and your notes are '
                              'in the folder beside them as before.'
                          : 'Done. This notebook is stored the old way again.')
                      : r.refusal!,
                  style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: r.done
                          ? context.surfaces.textSecondary
                          : OnoteColors.danger)),
            ),
          if (r?.details != null)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              shape: const Border(),
              title: const Text('Details (advanced)',
                  style: TextStyle(fontSize: 12.5)),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(r!.details!,
                      style: const TextStyle(
                          fontFamily: 'JetBrains Mono', fontSize: 11)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// The one dialog the plan asks for: honest about what changes, what is kept,
  /// and that it cannot be undone from inside the app.
  ///
  /// Every sentence is a fact about this notebook rather than about the storage
  /// design. No "container", no "SQLite", no "user_version", no file extension —
  /// all of that is in the Advanced fold, which is where the jargon rule
  /// (PLANNING, year-10 bar) puts it.
  Future<void> _confirmUpgrade() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update how this notebook is stored?'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Openote keeps two things for every notebook: your notes, in '
                "the notebook's own folder, and a working file it uses to open "
                'them quickly.\n\n'
                'This tucks the working file away where it belongs — out of '
                'sight, on this computer only — and makes it something Openote '
                'can always build again from your notes. It checks first that '
                'your notes really do describe everything in this notebook, and '
                'stops without changing anything if they do not.\n\n'
                'What stays the same: every page, every picture, drawing, file '
                'and recording, your recycle bin, and sharing with your other '
                'computers.\n\n'
                'What you lose: the automatic copies of each page that Openote '
                'used to take every ten minutes. Undo, the recycle bin and your '
                'backups are unaffected.\n\n'
                'You can put this back from this same panel afterwards, except '
                'for those automatic copies — those are gone for good.',
                style: TextStyle(fontSize: 13, height: 1.45),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Update it')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _upgrading = true;
      _upgraded = null;
    });
    final out = await app.demoteContainerToCache(widget.notebookId);
    if (!mounted) return;
    setState(() {
      _upgrading = false;
      _upgraded = out;
      _storage = app.storageFor(widget.notebookId);
    });
  }

  Future<void> _confirmUndoUpgrade() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go back to the old way?'),
        content: const Text(
          "This puts the notebook's working file back where an older Openote "
          'looks for it, and puts its own copy of every picture and drawing '
          'back inside it.\n\n'
          'Your notes are not changed. The automatic copies of each page that '
          'the update removed cannot come back — they were deleted then, not '
          'now.',
          style: TextStyle(fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Put it back')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _upgrading = true;
      _upgraded = null;
    });
    final out = await app.undemoteContainerFromCache(widget.notebookId);
    if (!mounted) return;
    setState(() {
      _upgrading = false;
      _upgraded = out;
      _storage = app.storageFor(widget.notebookId);
    });
  }

  bool _reclaiming = false;
  SpaceReclaim? _reclaimed;

  bool _tidying = false;
  BlobReclaim? _tidied;

  /// The button that removes the notebook file's second copy of every picture
  /// (v0.17 Step 7), and the sentence that goes with whatever happened.
  ///
  /// **This is the only control in Openote that deletes bytes on purpose**, so
  /// the copy is written to the same rule as the rest of the app — plain words,
  /// no jargon, technical detail folded away — with one addition: it says what
  /// is removed *and* what is kept, before it is pressed, because "reclaim
  /// space" tells a student nothing about what they are about to lose.
  ///
  /// Refusals are shown in exactly the same place as successes, in full. Every
  /// gate exists because something without it destroyed real data, and a
  /// refusal a user cannot read is a bug report that never gets filed.
  Widget _tidyPictures() {
    final r = _tidied;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: _tidying ? null : _confirmTidyPictures,
            icon: _tidying
                ? const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.photo_library_outlined, size: 16),
            label: Text(
                _tidying
                    ? 'Checking your pictures…'
                    : 'Stop keeping pictures twice…',
                style: const TextStyle(fontSize: 12)),
          ),
          if (r != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: Text(
                  r.done
                      ? 'Done. ${_bytes(r.freed)} freed, and all '
                          '${r.checked} of your pictures and drawings are '
                          "safe in this notebook's own folder."
                      : r.refusal!,
                  style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: r.done
                          ? context.surfaces.textSecondary
                          : OnoteColors.danger)),
            ),
          if (r?.details != null)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              shape: const Border(),
              title: const Text('Details (advanced)',
                  style: TextStyle(fontSize: 12.5)),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(r!.details!,
                      style: const TextStyle(
                          fontFamily: 'JetBrains Mono', fontSize: 11)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _confirmTidyPictures() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop keeping pictures twice?'),
        content: const Text(
          'Every picture and drawing in this notebook is stored twice at the '
          "moment: once inside the notes file, and once in the notebook's own "
          'folder beside it.\n\n'
          'Openote will remove the copy inside the notes file. The copy in the '
          "notebook's folder is kept — that is the one your notes point at, "
          'the one that reaches your other devices, and the one your backups '
          'copy.\n\n'
          'It checks every picture first, and stops without changing anything '
          'if even one of them is not safely in that folder. If you ever need '
          'the second copy back, Openote can put it there again.',
          style: TextStyle(fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove the extra copy')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _tidying = true;
      _tidied = null;
    });
    final out = await app.reclaimContainerBlobs(widget.notebookId);
    if (!mounted) return;
    setState(() {
      _tidying = false;
      _tidied = out;
      _storage = app.storageFor(widget.notebookId);
    });
  }

  /// The video sweep, once asked for. Null until the user presses the button —
  /// scanning reads every page, every saved version and every device's log,
  /// which is not work to do on the chance the dialog gets opened.
  Future<VideoSweep>? _videos;

  bool _converting = false;
  InkConversionResult? _inkResult;

  /// How many pages still hold handwriting as JSON.
  ///
  /// Counted once in [initState] and again after a conversion — not in
  /// `build`. It is a LIKE scan over the page mirror, and the section now sits
  /// inside a `ListenableBuilder`, so a per-build query would run it on every
  /// notifyListeners the app makes.
  int? _inkPages;

  @override
  void initState() {
    super.initState();
    _inkPages = app.inlineInkPageCount(widget.notebookId);
  }

  Widget _row(String label, String path, int bytes, CloudFolder? cloud,
      {bool isContainer = false, bool missing = false}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: 62,
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .4,
                color: context.surfaces.textSecondary)),
      ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(path,
                style: const TextStyle(fontSize: 11, height: 1.3)),
            Row(children: [
              Icon(
                  missing
                      ? Icons.help_outline
                      : cloud != null
                          ? Icons.cloud_done_outlined
                          : Icons.computer_outlined,
                  size: 16,
                  color: cloud != null
                      ? OnoteColors.success
                      : context.surfaces.textSecondary),
              const SizedBox(width: 4),
              Text(
                missing
                    ? 'not created yet'
                    : '${cloud?.name ?? 'this computer'} · ${_bytes(bytes)}',
                style: TextStyle(
                    fontSize: 11, color: context.surfaces.textSecondary),
              ),
            ]),
          ],
        ),
      ),
      IconButton(
        icon: const Icon(Icons.folder_open, size: 16),
        visualDensity: VisualDensity.compact,
        tooltip: 'Open containing folder',
        onPressed: () => PlatformOpen.file(
            isContainer ? p.dirname(path) : path),
      ),
    ]);
  }

  /// What the sweep found, in the words a fifteen-year-old reads once.
  ///
  /// No counts of references, no mention of logs, devices or snapshots: the
  /// only two things the reader needs are how much space this is and what
  /// would go. The caveat says what is being kept in terms of things they have
  /// — a page, the bin, a template, another computer — because that is the
  /// question anyone about to press Delete is actually asking.
  Widget _videoList() => FutureBuilder<VideoSweep>(
        future: _videos,
        builder: (_, snap) {
          final s = snap.data;
          if (s == null) {
            return Text('Looking through your notes…',
                style: TextStyle(
                    fontSize: 12, color: context.surfaces.textSecondary));
          }
          if (s.refusal != null) {
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(s.refusal!,
                  style: const TextStyle(fontSize: 12, height: 1.35)),
            );
          }
          if (s.unused.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  'Every video in this notebook is still used somewhere. '
                  'Nothing to free up.',
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: context.surfaces.textSecondary)),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                  '${s.unused.length} video${s.unused.length == 1 ? '' : 's'} '
                  'nothing points at  ·  ${_bytes(s.freeableBytes)}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              for (final v in s.unused.take(8))
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(children: [
                    Icon(Icons.movie_outlined,
                        size: 16, color: context.surfaces.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('${v.name}  ·  ${_bytes(v.bytes)}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ]),
                ),
              const SizedBox(height: 4),
              Text(
                'A video still on a page, in your deleted items, in an earlier '
                'version of a page, in a template, or in use on another one of '
                'your computers is left alone. So are videos added in the last '
                'month. Deleting these cannot be undone.',
                style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: context.surfaces.textSecondary),
              ),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        final freed = await app.deleteUnusedVideos(s.unused);
                        if (!mounted) return;
                        setState(() {
                          _busy = false;
                          _videos =
                              app.findUnusedVideos(widget.notebookId);
                          _storage = app.storageFor(widget.notebookId);
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Freed ${_bytes(freed)}')));
                      },
                icon: const Icon(Icons.delete_outline, size: 16),
                label: Text(
                    'Delete ${s.unused.length} video'
                    '${s.unused.length == 1 ? '' : 's'} '
                    '(${_bytes(s.freeableBytes)})',
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          );
        },
      );

  Widget _orphanList() => FutureBuilder<List<OrphanFile>>(
        future: _orphans,
        builder: (_, snap) {
          final list = snap.data;
          if (list == null) {
            return Text('Looking…',
                style:
                    TextStyle(fontSize: 12, color: context.surfaces.textSecondary));
          }
          if (list.isEmpty) {
            return Text('No leftover notebook files found.',
                style:
                    TextStyle(fontSize: 12, color: context.surfaces.textSecondary));
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
                        size: 16, color: context.surfaces.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('${p.basename(o.path)}  ·  ${_bytes(o.bytes)}'
                          '${o.safeToDelete ? '' : '  ·  shared folder'}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ]),
                ),
              const SizedBox(height: 4),
              // Only workspace files are ever deleted from here: a leftover in
              // a SHARED folder may be another device's notebook this machine
              // has never joined, and removing it would destroy data this
              // device never owned.
              Text(
                'Files in a shared folder are left alone — they may belong to '
                'another device. Open the folder to review those yourself.',
                style: TextStyle(
                    fontSize: 11, height: 1.35, color: context.surfaces.textSecondary),
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
                  icon: const Icon(Icons.delete_outline, size: 16),
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
///
/// **A `.onote` is only offered when its `.onotebook` is beside it — and a
/// lone `.onotebook` is offered on its own.**
///
/// Reported: "there were a bunch of files left over in the folder from deleted
/// notebooks … which meant that when i was running through the setup process
/// it thought there were several notebooks which didnt actually exist." That
/// is this list, and it was trusting a filename. A notebook another device
/// shares through a folder ALWAYS arrives as a pair — `moveNotebookTo` copies
/// the container and the log directory together — so a lone container is
/// never something to join. It is a leftover, and on the real machine there
/// was one 35.9 MB of it, offered beside the live notebook under a name one
/// character different.
///
/// The lone-directory case is the normal one from v0.17 on: sharing a notebook
/// moves the `.onotebook` into the folder and deliberately leaves the container
/// on the machine that made it (v0.17 plan, Step 4). Without this the second
/// device would find nothing at all in a folder that is syncing perfectly well.
/// It still has to *look* like a notebook — `manifest.json` or an `ops/`
/// directory — so an ordinary folder someone named `.onotebook` is not offered.
///
/// Checked by looking rather than by opening: the candidate lives in someone's
/// Drive, and opening a SQLite file to interrogate it writes to it (schema
/// DDL, a `-wal`, a `-shm`) — scanning for leftovers must not create any.
///
/// [searchIn] replaces the detected folders, for tests — the real ones are
/// this machine's actual Drive and OneDrive, which no test may write into.
List<({String name, String path, CloudFolder folder})> findExistingNotebooks({
  List<CloudFolder>? searchIn,
}) {
  final out = <({String name, String path, CloudFolder folder})>[];
  final seen = <String>{};
  for (final cloud in searchIn ?? detectCloudFolders()) {
    for (final root in [cloud.path, p.join(cloud.path, 'Openote')]) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      try {
        for (final e in dir.listSync(followLinks: false)) {
          if (e is Directory && p.extension(e.path) == '.onotebook') {
            // Its container's device is the one that shares it; if that device
            // is running an older build the `.onote` is beside it and the
            // branch below offers that instead, so this must not double up.
            if (File('${p.withoutExtension(e.path)}.onote').existsSync()) {
              continue;
            }
            if (!File(p.join(e.path, 'manifest.json')).existsSync() &&
                !Directory(p.join(e.path, 'ops')).existsSync()) {
              continue;
            }
            if (!seen.add(e.path)) continue;
            out.add((
              name: p.basenameWithoutExtension(e.path),
              path: e.path,
              folder: cloud
            ));
            continue;
          }
          if (e is! File || p.extension(e.path) != '.onote') continue;
          if (!Directory('${p.withoutExtension(e.path)}.onotebook')
              .existsSync()) {
            continue;
          }
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

/// Backing a notebook with a git remote.
///
/// Shown to everyone but honest about who it is for: it needs git installed
/// and a repository you already have somewhere. On a machine without git it
/// says so and offers nothing, rather than presenting a switch that cannot
/// work.
///
/// The wording avoids the word "backup". This IS a backup in every practical
/// sense, but calling it one invites people to rely on it before they have
/// checked that the remote is reachable, and the failure mode of a backup
/// nobody verified is the worst one there is.
class _GitSection extends StatefulWidget {
  const _GitSection({required this.app});
  final AppState app;

  @override
  State<_GitSection> createState() => _GitSectionState();
}

class _GitSectionState extends State<_GitSection> {
  late final TextEditingController _remote =
      TextEditingController(text: widget.app.gitRemote ?? '');

  @override
  void initState() {
    super.initState();
    if (widget.app.gitAvailable == null) {
      widget.app.checkGitAvailable();
    }
  }

  @override
  void dispose() {
    _remote.dispose();
    super.dispose();
  }

  AppState get app => widget.app;

  @override
  Widget build(BuildContext context) {
    final available = app.gitAvailable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Same as "Extra copies": the disclosure row above says this already.
        const SizedBox(height: 4),
        Text(
          available == false
              ? 'Git is not installed on this computer, so this is not '
                  'available here. Installing it from git-scm.com is all that '
                  'is needed.'
              : 'Keeps this notebook in a git repository and pushes it as you '
                  'work. Your notes go in; the working file Openote keeps on '
                  'this computer does not.',
          style: TextStyle(
              fontSize: 12, height: 1.4, color: context.surfaces.textSecondary),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Sync this notebook with git',
              style: TextStyle(fontSize: 13)),
          subtitle: app.gitStatus == null
              ? null
              : Text(app.gitStatus!,
                  style: TextStyle(
                      fontSize: 11,
                      color: app.gitStatus!.startsWith('Could not')
                          ? OnoteColors.danger
                          : context.surfaces.textSecondary)),
          value: app.gitEnabled,
          onChanged: available == false || app.gitBusy
              ? null
              : (v) async {
                  await app.setGitEnabled(v, remote: _remote.text);
                  if (mounted) setState(() {});
                },
        ),
        if (app.gitEnabled) ...[
          if (app.gitRemote == null) ...[
            const SizedBox(height: 4),
            _GitHubPublish(
                app: app,
                onDone: () => setState(() {
                      // The field below is about to become the visible record
                      // of where this notebook lives; it must not still be
                      // showing the empty box the repository was created from.
                      _remote.text = app.gitRemote ?? _remote.text;
                    })),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: Divider(color: context.surfaces.border)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('or use a repository you already have',
                    style: TextStyle(
                        fontSize: 11, color: context.surfaces.textSecondary)),
              ),
              Expanded(child: Divider(color: context.surfaces.border)),
            ]),
          ],
          const SizedBox(height: 4),
          TextField(
            controller: _remote,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Remote address',
              hintText: 'https://github.com/you/my-notes.git',
              helperText: 'Leave empty to keep a history on this computer only',
              helperMaxLines: 2,
            ),
            onSubmitted: (v) async {
              await app.setGitEnabled(true, remote: v);
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(height: 8),
          Row(children: [
            TextButton.icon(
              onPressed: app.gitBusy
                  ? null
                  : () async {
                      await app.setGitEnabled(true, remote: _remote.text);
                      if (mounted) setState(() {});
                    },
              icon: app.gitBusy
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync, size: 16),
              label: Text(app.gitBusy ? 'Syncing…' : 'Sync now',
                  style: const TextStyle(fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            app.githubConnected
                ? 'Signed in to GitHub as ${app.githubLogin}. Openote keeps '
                    'the token in this computer\'s own password storage and '
                    'sends it only to GitHub — it is never written into a '
                    'plain file, the notebook, or its repository.'
                : 'Openote never asks for your password: it runs the git '
                    'already on this computer and uses whatever sign-in you '
                    'have set up for it. If a push needs credentials you have '
                    'not configured, it will say so here rather than appear '
                    'to work.',
            style: TextStyle(
                fontSize: 11, height: 1.4, color: context.surfaces.textSecondary),
          ),
        ],
      ],
    );
  }
}

/// Creating the repository, without leaving the app.
///
/// "I want to be able to create and push my notebook to github from within the
/// app, no extra steps required outside the app."
///
/// One thing genuinely cannot move inside, and it is worth being straight
/// about which: GitHub only issues tokens on its own site, so connecting an
/// account is a visit to one page, once. Everything on either side of that —
/// naming the repository, creating it, pointing the notebook at it, the first
/// push and every sync afterwards — happens here. The button opens the page
/// with the right scope already ticked so there is nothing to get wrong on it
/// but the copying.
class _GitHubPublish extends StatefulWidget {
  const _GitHubPublish({required this.app, required this.onDone});
  final AppState app;
  final VoidCallback onDone;

  @override
  State<_GitHubPublish> createState() => _GitHubPublishState();
}

class _GitHubPublishState extends State<_GitHubPublish> {
  late final TextEditingController _name =
      TextEditingController(text: repoNameFor(widget.app.currentNotebook.title));
  final TextEditingController _token = TextEditingController();

  /// Private unless the user says otherwise. These are somebody's notes, and a
  /// public repository of a student's coursework created by a default nobody
  /// read is not a mistake to make on their behalf.
  bool _private = true;
  bool _busy = false;
  String? _error;
  bool _pasting = false;

  @override
  void dispose() {
    _name.dispose();
    _token.dispose();
    super.dispose();
  }

  AppState get app => widget.app;

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final problem = await app.connectGitHub(_token.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = problem;
      if (problem == null) {
        _pasting = false;
        _token.clear(); // it is stored now; no reason to keep it on screen
      }
    });
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final problem =
        await app.createGitHubRepo(private: _private, name: _name.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = problem;
    });
    if (problem == null) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final connected = app.githubConnected;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.surfaces.chrome2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: context.surfaces.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.cloud_upload_outlined, size: 16),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('Put this notebook on GitHub',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            if (connected)
              Text(app.githubLogin!,
                  style: TextStyle(
                      fontSize: 11, color: context.surfaces.textSecondary)),
          ]),
          const SizedBox(height: 8),
          if (!connected && !_pasting)
            Text(
              'Openote can create the repository and push to it for you. It '
              'needs a token from GitHub first — one page, once.',
              style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: context.surfaces.textSecondary),
            ),
          if (!connected && !_pasting) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                // **Only move on if the browser actually opened.** The result
                // was discarded, so a machine with no registered browser
                // flipped straight to "paste your token here" — asking for
                // something the student had never been shown how to get.
                final opened = await PlatformOpen.url(GitHubApi.tokenPage);
                if (!mounted) return;
                if (!opened) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
                    content: Text(
                        "Openote couldn't open your browser. Go to "
                        '${GitHubApi.tokenPage} and make a token there.'),
                    duration: const Duration(seconds: 10),
                  ));
                  return;
                }
                setState(() => _pasting = true);
              },
              icon: const Icon(Icons.open_in_new, size: 15),
              label: const Text('Connect GitHub', style: TextStyle(fontSize: 12)),
            ),
          ],
          if (!connected && _pasting) ...[
            Text(
              'On the page that just opened, scroll to the bottom and press '
              '“Generate token”, then copy it and paste it here. Openote asked '
              'for the “repo” permission and nothing else.',
              style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: context.surfaces.textSecondary),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _token,
              autofocus: true,
              // Obscured because a token is a password in every way that
              // matters, and this dialog gets opened while screen sharing.
              obscureText: true,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Paste your token',
                hintText: 'ghp_…',
              ),
              onSubmitted: (_) => _connect(),
            ),
            const SizedBox(height: 6),
            Row(children: [
              FilledButton(
                onPressed: _busy ? null : _connect,
                child: Text(_busy ? 'Checking…' : 'Connect',
                    style: const TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: _busy ? null : () => setState(() => _pasting = false),
                child: const Text('Cancel', style: TextStyle(fontSize: 12)),
              ),
            ]),
          ],
          if (connected) ...[
            TextField(
              controller: _name,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Repository name',
              ),
            ),
            const SizedBox(height: 2),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _private,
              onChanged: _busy ? null : (v) => setState(() => _private = v ?? true),
              title: const Text('Keep it private', style: TextStyle(fontSize: 12)),
              subtitle: Text(
                _private
                    ? 'Only you can see it'
                    : 'ANYONE ON THE INTERNET WILL BE ABLE TO READ THESE NOTES',
                style: TextStyle(
                    fontSize: 11,
                    color: _private
                        ? context.surfaces.textSecondary
                        : OnoteColors.danger),
              ),
            ),
            Row(children: [
              FilledButton.icon(
                onPressed: _busy || app.gitBusy ? null : _create,
                icon: _busy || app.gitBusy
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add, size: 15),
                label: Text(_busy || app.gitBusy ? 'Working…' : 'Create and push',
                    style: const TextStyle(fontSize: 12)),
              ),
              const Spacer(),
              TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        app.disconnectGitHub();
                        setState(() {});
                      },
                child: const Text('Sign out', style: TextStyle(fontSize: 12)),
              ),
            ]),
          ],
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!,
                style: const TextStyle(
                    fontSize: 11, height: 1.4, color: OnoteColors.danger)),
          ],
        ],
      ),
    );
  }
}

/// What other people in this notebook see this computer called.
///
/// **The one genuinely new thing the simplified version history needs**
/// (v0.17 plan, Step 8a). Attribution comes free out of the log — every op
/// already carries the device that wrote it — but a device id is a uuid, and
/// *"last changed by 019fdff4-8c31-7a2e-…"* is worse than saying nothing at
/// all. One field, in the words a question would be asked in, and a default
/// that means nobody has to answer it at first run.
///
/// **The sentence underneath is not decoration.** In a folder-shared notebook
/// `manifest.json` is a synced file, so this name really is visible to everyone
/// in the notebook, and someone typing their own name into it deserves to know
/// that before they do rather than after.
class _ComputerNameField extends StatefulWidget {
  const _ComputerNameField({required this.app, required this.notebookId});
  final AppState app;
  final String notebookId;

  @override
  State<_ComputerNameField> createState() => _ComputerNameFieldState();
}

class _ComputerNameFieldState extends State<_ComputerNameField> {
  // Owned by this State and disposed with it. Building the controller in the
  // parent and disposing it beside an `await` is the defect
  // `dialog_controller_lifetime_test.dart` exists for: the route is popped but
  // its exit transition has not finished, so the field is still mounted and
  // still rebuilding against a dead controller.
  late final TextEditingController _c = TextEditingController(
      text: widget.app.thisComputerLabel(widget.notebookId));
  String? _problem;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _save() {
    final ok =
        widget.app.setThisComputerLabel(widget.notebookId, _c.text);
    setState(() => _problem = ok
        ? null
        : "Openote couldn't save that name. Your notes are unaffected.");
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _c,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'What should other people call this computer?',
            ),
            onEditingComplete: _save,
            onTapOutside: (_) => _save(),
          ),
          const SizedBox(height: 4),
          Text(
            'Changes you make are shown against this name, so everyone sharing '
            'the notebook can see it.',
            style: TextStyle(
                fontSize: 11, height: 1.35, color: context.surfaces.textSecondary),
          ),
          if (_problem != null) ...[
            const SizedBox(height: 4),
            Text(_problem!,
                style:
                    const TextStyle(fontSize: 11, color: OnoteColors.danger)),
          ],
        ],
      );
}
