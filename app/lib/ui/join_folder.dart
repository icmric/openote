/// **Open a notebook that lives in a Drive folder** (Android).
///
/// One tap on "Open from a Drive folder" in the notebook list: the system's own
/// folder picker, a short wait with a line saying what is happening, and the
/// notebook opens. Nothing is typed, nothing is signed into, and the folder is
/// only read.
library;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../sync/saf_folder.dart';
import 'toast.dart';

Future<void> openFromDriveFolder(BuildContext context, AppState app,
    {required ScaffoldMessengerState messenger}) async {
  final tree = await SafFolder.pick();
  if (tree == null) return;
  if (!context.mounted) return;
  final stage = ValueNotifier<String>('Looking at the folder…');
  // A small modal the person cannot dismiss mid-read: closing it would not stop
  // the read, only hide that it was happening.
  _showProgress(context, stage);
  final problem =
      await app.joinNotebookFromFolder(tree, onProgress: (s) => stage.value = s);
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
