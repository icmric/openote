/// Joining a notebook from a git address — the other end of publishing one.
///
/// "Seems like the push side of things works. Work on pulling from it now."
///
/// Deliberately small. Everything that makes this work is decided elsewhere:
/// the address says which notebook, the manifest inside it says what to call
/// it, and the connected GitHub account (if there is one) says whether a
/// private repository can be read. So this asks for one thing and then gets
/// out of the way.
library;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';
import 'onote_dialog.dart';

Future<void> showJoinFromGitDialog(BuildContext context, AppState app,
    {ScaffoldMessengerState? messenger}) async {
  final m = messenger ?? ScaffoldMessenger.of(context);
  final joined = await showOnoteDialog<String>(
    context: context,
    builder: (_) => _JoinDialog(app: app),
  );
  if (joined != null) {
    m.showSnackBar(SnackBar(content: Text('Opened $joined.')));
  }
}

class _JoinDialog extends StatefulWidget {
  const _JoinDialog({required this.app});
  final AppState app;

  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  final TextEditingController _url = TextEditingController();
  bool _busy = false;
  String? _error;

  /// What the join is doing right now. Worth showing: a big notebook's clone
  /// is the longest wait in the app that is not an import, and a dialog that
  /// simply sits there for a minute reads as broken.
  String _stage = '';

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
      _stage = 'Fetching…';
    });
    final problem = await widget.app.joinNotebookFromGit(
      _url.text,
      onProgress: (s) {
        if (mounted) setState(() => _stage = s);
      },
    );
    if (!mounted) return;
    if (problem != null) {
      setState(() {
        _busy = false;
        _error = problem;
      });
      return;
    }
    Navigator.pop(context, widget.app.currentNotebook.title);
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.app.githubConnected;
    return AlertDialog(
      title: const Text('Open a notebook from a git address'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paste the address of a repository holding an Openote notebook. '
              'It is copied to this computer and kept in step from then on — '
              'this machine writes its own file, so the two can never '
              'overwrite each other.',
              style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: context.surfaces.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              autofocus: true,
              enabled: !_busy,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Repository address',
                hintText: 'https://github.com/you/my-notes',
              ),
              onSubmitted: (_) => _busy ? null : _go(),
            ),
            const SizedBox(height: 8),
            Text(
              connected
                  // Said plainly, because "repository not found" is what
                  // GitHub returns for a private repository you cannot see,
                  // and that is a confusing thing to be told about your own
                  // notebook.
                  ? 'Signed in to GitHub as ${widget.app.githubLogin}, so '
                      'private repositories on that account work too.'
                  : 'A private repository needs a connected GitHub account — '
                      'that is under Sync, on any notebook.',
              style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: context.surfaces.textSecondary),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              Row(children: [
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Text(_stage, style: const TextStyle(fontSize: 12)),
              ]),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(
                      fontSize: 12, height: 1.4, color: OnoteColors.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: _busy ? null : _go,
            child: Text(_busy ? 'Opening…' : 'Open')),
      ],
    );
  }
}
