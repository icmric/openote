/// **"Bring a notebook over from OneNote"** — the door that was missing.
///
/// Everything behind it existed and none of it was reachable: the sign-in, the
/// page reader and the importer all shipped without a button, which is why the
/// owner rebuilt three times and could not find the feature.
///
/// The flow is three screens in one dialog, and deliberately short:
///
///  1. **Sign in** — one button, plus the one sentence that matters
///     (Openote reads; it cannot change anything in OneNote).
///  2. **Pick a notebook** — the list, newest first.
///  3. Gone. The import runs behind the app, section by section, with the
///     progress card the `.onepkg` path already uses.
///
/// There is no third step where you wait, because the import does not make you
/// wait: [importNotebookFromGraph] writes each section as it arrives, so the
/// dialog closes and the notebook fills in behind it.
library;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../onenote/graph_auth.dart';
import '../onenote/graph_client.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';
import 'onote_dialog.dart';

/// Show the picker. Returns once the import has been STARTED, not finished.
Future<void> showOneNoteCloudDialog(BuildContext context, AppState app) =>
    showOnoteDialog<void>(
      context: context,
      builder: (_) => _OneNoteCloudDialog(app: app),
    );

class _OneNoteCloudDialog extends StatefulWidget {
  const _OneNoteCloudDialog({required this.app});
  final AppState app;

  @override
  State<_OneNoteCloudDialog> createState() => _OneNoteCloudDialogState();
}

class _OneNoteCloudDialogState extends State<_OneNoteCloudDialog> {
  final _auth = GraphAuth();
  bool _busy = false;
  String? _error;
  String? _errorDetail;
  List<GraphNotebook>? _notebooks;

  @override
  void initState() {
    super.initState();
    // A remembered sign-in should not make somebody press "sign in" again for
    // no reason — the refresh token is exactly the thing that avoids it.
    if (_auth.hasStoredSignIn) _load();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
      _errorDetail = null;
    });
    try {
      await _auth.signIn();
      await _load();
    } on GraphAuthException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
          _errorDetail = e.details;
        });
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final client = GraphClient(token: _auth.accessToken);
    try {
      final found = await client.notebooks();
      if (mounted) {
        setState(() {
          _busy = false;
          _notebooks = found;
        });
      }
    } on GraphException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
          _errorDetail = e.details;
        });
      }
    } on GraphAuthException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _notebooks = null;
          _error = e.message;
        });
      }
    } finally {
      client.close();
    }
  }

  void _useAnotherAccount() {
    _auth.signOut();
    setState(() {
      _notebooks = null;
      _error = null;
    });
    _signIn();
  }

  Future<void> _import(GraphNotebook nb) async {
    Navigator.of(context).pop();
    await widget.app.importFromOneNoteCloud(auth: _auth, notebook: nb);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final s = context.surfaces;
    final list = _notebooks;
    return AlertDialog(
      title: Text(l.oneNoteCloudTitle, style: OnoteType.title),
      content: SizedBox(
        width: 460,
        child: AnimatedSize(
          duration: OnoteMotion.standard,
          curve: OnoteMotion.curve,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (list == null) ...[
                // Said BEFORE the sign-in, not after: whether an app can
                // change your notes is the question a person actually has at
                // the moment they are deciding whether to press it.
                Text(l.oneNoteCloudIntro,
                    style: OnoteType.ui.copyWith(color: s.textSecondary)),
                const SizedBox(height: OnoteSpace.x4),
                Text(l.oneNoteCloudNoInk,
                    style: OnoteType.small.copyWith(color: s.textSecondary)),
              ] else if (list.isEmpty)
                Text(l.oneNoteCloudEmpty,
                    style: OnoteType.ui.copyWith(color: s.textSecondary))
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (_, i) => _NotebookRow(
                      notebook: list[i],
                      onTap: _busy ? null : () => _import(list[i]),
                    ),
                  ),
                ),
              if (_busy) ...[
                const SizedBox(height: OnoteSpace.x5),
                Row(children: [
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: OnoteSpace.x4),
                  Text(
                      list == null
                          ? l.oneNoteCloudSigningIn
                          : l.oneNoteCloudLoading,
                      style:
                          OnoteType.small.copyWith(color: s.textSecondary)),
                ]),
              ],
              if (_error != null) ...[
                const SizedBox(height: OnoteSpace.x5),
                Text(_error!,
                    style:
                        OnoteType.small.copyWith(color: OnoteColors.danger)),
                if (_errorDetail != null) ...[
                  const SizedBox(height: OnoteSpace.x2),
                  // The technical half stays behind the plain sentence, the
                  // way every other failure in this app reports itself.
                  SelectableText(_errorDetail!,
                      style: OnoteType.caption
                          .copyWith(color: s.textSecondary)),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (list != null && _auth.hasStoredSignIn)
          TextButton(
            onPressed: _busy ? null : _useAnotherAccount,
            // This is what replaces showing the signed-in email address.
            // Openote deliberately never learns who anybody is, so the way to
            // fix "wrong account" is to change it rather than to read it.
            child: Text(l.oneNoteCloudOther),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
        if (list == null)
          FilledButton(
            onPressed: _busy ? null : _signIn,
            child: Text(l.oneNoteCloudSignIn),
          ),
      ],
    );
  }
}

class _NotebookRow extends StatelessWidget {
  const _NotebookRow({required this.notebook, this.onTap});
  final GraphNotebook notebook;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    return Padding(
      padding: const EdgeInsets.only(bottom: OnoteSpace.x2),
      child: InkWell(
        borderRadius: OnoteRadius.mdAll,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: OnoteSpace.x5, vertical: OnoteSpace.x4),
          decoration: BoxDecoration(
            color: s.chrome2,
            borderRadius: OnoteRadius.mdAll,
            border: Border.all(color: s.border),
          ),
          child: Row(children: [
            Expanded(
              child: Text(notebook.name,
                  style: OnoteType.uiStrong.copyWith(color: s.textPrimary),
                  overflow: TextOverflow.ellipsis),
            ),
            Icon(Icons.chevron_right, size: OnoteIcon.md, color: s.textSecondary),
          ]),
        ),
      ),
    );
  }
}
