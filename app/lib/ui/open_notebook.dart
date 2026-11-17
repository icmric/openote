/// **Open a notebook that already exists in a folder.**
///
/// One button, "Open", in the notebook list, on every device:
///
///  * **On a computer** it shows the notebooks it can already see in Google
///    Drive, OneDrive, Dropbox and the like, and lets you choose a folder to look
///    in; whichever you choose, you are shown the notebooks in it and pick one.
///  * **On a phone** it says in one line what to choose, opens Android's own
///    folder picker, then does the same looking and asks which notebook if there
///    is more than one. No sign-in: the picker grants access to that one folder.
///
/// Nobody has to know that a notebook is a folder whose name ends in
/// `.onotebook`, or which folder that is.
library;

import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../sync/cloud_folders.dart';
import '../sync/notebook_scan.dart';
import '../sync/saf_folder.dart';
import '../theme/tokens.dart';
import 'onote_dialog.dart';
import 'toast.dart';

/// The cloud folders the dialog looks in on its own. A test replaces it: the
/// real ones are this machine's actual Drive.
@visibleForTesting
List<CloudFolder> Function() cloudFoldersToSearch = detectCloudFolders;

/// Start the flow. [messenger] and [context] must outlive the notebook list that
/// started this (take them before it is closed).
Future<void> openNotebookFromFolder(BuildContext context, AppState app,
    {required ScaffoldMessengerState messenger}) =>
    safAvailable
        ? _openFromDrive(context, app, messenger)
        : _openFromComputer(context, app, messenger);

// ── A computer ─────────────────────────────────────────────────────────────

Future<void> _openFromComputer(
    BuildContext context, AppState app, ScaffoldMessengerState messenger) async {
  final chosen = await showOnoteDialog<String>(
    context: context,
    builder: (_) => const _ComputerDialog(),
  );
  if (chosen == null || !context.mounted) return;
  final stage = ValueNotifier<String>(L.of(context).navOpening);
  _showProgress(context, stage);
  String? failed;
  try {
    await app.openExistingNotebook(chosen);
  } catch (e) {
    failed = '$e';
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  stage.dispose();
  if (failed != null && context.mounted) {
    messenger.showToast(SnackBar(
        content: Text(L.of(context).onboardingOpenFailed),
        duration: const Duration(seconds: 6)));
  }
}

class _ComputerDialog extends StatefulWidget {
  const _ComputerDialog();

  @override
  State<_ComputerDialog> createState() => _ComputerDialogState();
}

class _ComputerDialogState extends State<_ComputerDialog> {
  /// Null while looking.
  List<FoundNotebook>? _found;
  bool _chose = false;

  @override
  void initState() {
    super.initState();
    unawaited(_scanClouds());
  }

  /// The cloud folders this computer has, to a couple of levels: enough to find
  /// "Drive / Openote / Honours.onotebook" and "Drive / Uni / Openote / ..."
  /// without anyone choosing anything.
  Future<void> _scanClouds() async {
    final out = <FoundNotebook>[];
    try {
      for (final cloud in cloudFoldersToSearch()) {
        out.addAll(await findNotebooksUnder(cloud.path));
      }
    } catch (_) {}
    if (mounted) setState(() => _found = out);
  }

  Future<void> _choose() async {
    final dir = await getDirectoryPath(
        confirmButtonText: L.of(context).openFolderChoose.replaceAll('…', ''));
    if (dir == null || !mounted) return;
    setState(() {
      _found = null;
      _chose = true;
    });
    final found = await findNotebooksUnder(dir);
    if (!mounted) return;
    // Exactly one, in the folder they chose: no need to ask again.
    if (found.length == 1) {
      Navigator.pop(context, found.single.path);
      return;
    }
    setState(() => _found = found);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final s = context.surfaces;
    final found = _found;
    return AlertDialog(
      title: Text(l.openFolderTitle),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: ListView(shrinkWrap: true, children: [
            Text(l.openFolderBody,
                style: TextStyle(fontSize: 13, color: s.textSecondary)),
            const SizedBox(height: 12),
            if (found == null)
              Row(children: [
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2)),
                const SizedBox(width: 12),
                Text(l.openFolderLooking, style: const TextStyle(fontSize: 13)),
              ])
            else if (found.isEmpty && _chose)
              Text(l.openFolderNone, style: const TextStyle(fontSize: 13))
            else if (found.isNotEmpty) ...[
              Text(l.openFolderFound.toUpperCase(),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .6,
                      color: s.textSecondary)),
              for (final n in found)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.menu_book_outlined, size: 20),
                  title: Text(n.name, overflow: TextOverflow.ellipsis),
                  subtitle: Text(p.dirname(n.path),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11)),
                  trailing: Text(l.commonOpen,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(context, n.path),
                ),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.folder_open_outlined, size: 18),
          label: Text(l.openFolderChoose),
          onPressed: _choose,
        ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.commonCancel)),
      ],
    );
  }
}

// ── A phone ────────────────────────────────────────────────────────────────

Future<void> _openFromDrive(
    BuildContext context, AppState app, ScaffoldMessengerState messenger) async {
  final l = L.of(context);
  // One line of explanation before the system screen, because the system screen
  // does not say what to choose.
  final go = await showOnoteDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.openFolderTitle),
      content: Text(l.openFolderAndroidHint),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.commonCancel)),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.openFolderChoose)),
      ],
    ),
  );
  if (go != true || !context.mounted) return;
  final tree = await SafFolder.pick();
  if (tree == null || !context.mounted) return;

  final stage = ValueNotifier<String>(l.openFolderLooking);
  _showProgress(context, stage);
  List<FoundNotebook> found;
  try {
    found = await findNotebooksInFolder(SafFolder(tree));
  } catch (_) {
    found = const [];
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  if (!context.mounted) {
    stage.dispose();
    return;
  }
  if (found.isEmpty) {
    stage.dispose();
    messenger.showToast(SnackBar(
        content: Text(l.openFolderNone), duration: const Duration(seconds: 8)));
    return;
  }
  FoundNotebook pick = found.first;
  if (found.length > 1) {
    final chosen = await showOnoteDialog<FoundNotebook>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.openFolderFound),
        contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(shrinkWrap: true, children: [
            for (final n in found)
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(n.name, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(ctx, n),
              ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(l.commonCancel)),
        ],
      ),
    );
    if (chosen == null || !context.mounted) {
      stage.dispose();
      return;
    }
    pick = chosen;
  }

  stage.value = l.navOpening;
  _showProgress(context, stage);
  final problem = await app.joinNotebookFromFolder(tree,
      rootDoc: pick.root, onProgress: (s) => stage.value = s);
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  stage.dispose();
  messenger.showToast(SnackBar(
      content: Text(problem ??
          'Opened. Pictures load as you reach them.'
              '${app.folderPullSummary == null ? '' : '\n${app.folderPullSummary}'}')));
}

void _showProgress(BuildContext context, ValueNotifier<String> stage) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 16),
          Expanded(
            child: ValueListenableBuilder<String>(
                valueListenable: stage, builder: (_, s, __) => Text(s)),
          ),
        ]),
      ),
    ),
  );
}
