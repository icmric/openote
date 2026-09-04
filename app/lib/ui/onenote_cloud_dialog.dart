/// **"Bring a notebook over from OneNote"** — two ways in, and neither is
/// hidden behind the other.
///
/// ## Why there are two
///
/// The owner: *"i know many users wouldnt be comfortable with signing into
/// their microsoft account either to transfer it, so i want to make it clear
/// there is another option."*
///
/// That is a reasonable thing not to be comfortable with, and an import route
/// that assumes everyone will sign in is one that quietly turns those people
/// away. So both routes are on the first screen, side by side, described by
/// what they cost rather than by how they work:
///
///  * **Sign in** — nothing to export, works on any computer, but cannot
///    carry handwriting, because Graph's HTML has no representation of a
///    stroke.
///  * **A file you exported** — no account involved at all, and handwriting
///    comes with it, but you need OneNote on Windows to make the file.
///
/// Neither is "advanced". A person picks on the trade-off that matters to
/// them, which is the only honest way to present a choice where each option
/// genuinely wins at something.
///
/// ## Why it is not cluttered
///
/// One screen at a time, and the screen you are on shows only its own
/// question. Choosing a route replaces the choice rather than adding to it —
/// so the notebook list is a list of notebooks, not a list of notebooks
/// underneath the thing you already decided.
library;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../onenote/graph_auth.dart';
import '../onenote/graph_client.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';
import 'notebook_manager.dart';
import 'onote_dialog.dart';

/// Show the picker. Returns once an import has been STARTED, not finished.
Future<void> showOneNoteCloudDialog(BuildContext context, AppState app) =>
    showOnoteDialog<void>(
      context: context,
      builder: (_) => _OneNoteDialog(app: app),
    );

class _OneNoteDialog extends StatefulWidget {
  const _OneNoteDialog({required this.app});
  final AppState app;

  @override
  State<_OneNoteDialog> createState() => _OneNoteDialogState();
}

class _OneNoteDialogState extends State<_OneNoteDialog> {
  final _auth = GraphAuth();
  bool _busy = false;
  String? _error;
  String? _errorDetail;

  /// Null until a sign-in has produced one. Non-null means the dialog has
  /// moved on to its second screen.
  List<GraphNotebook>? _notebooks;

  @override
  void initState() {
    super.initState();
    // A remembered sign-in should not make somebody press "sign in" again for
    // no reason — a refresh token is exactly the thing that avoids it.
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
      _fail(e.message, e.details);
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
      _fail(e.message, e.details);
    } on GraphAuthException catch (e) {
      _fail(e.message, e.details);
    } finally {
      client.close();
    }
  }

  void _fail(String message, String? detail) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
      _errorDetail = detail;
    });
  }

  void _useAnotherAccount() {
    _auth.signOut();
    setState(() {
      _notebooks = null;
      _error = null;
    });
    _signIn();
  }

  Future<void> _chooseFile() async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    await importOneNotePackageWithFeedback(messenger, widget.app);
  }

  Future<void> _import(GraphNotebook nb) async {
    Navigator.of(context).pop();
    await widget.app.importFromOneNoteCloud(auth: _auth, notebook: nb);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final picking = _notebooks != null;
    return AlertDialog(
      title: Text(picking ? l.oneNotePickTitle : l.oneNoteCloudTitle,
          style: OnoteType.title),
      content: SizedBox(
        width: 460,
        child: AnimatedSize(
          duration: OnoteMotion.standard,
          curve: OnoteMotion.curve,
          alignment: Alignment.topCenter,
          child: picking ? _pickNotebook(l) : _chooseRoute(l),
        ),
      ),
      actions: [
        if (picking && _auth.hasStoredSignIn)
          TextButton(
            onPressed: _busy ? null : _useAnotherAccount,
            // What replaces showing the signed-in email address. Openote
            // deliberately never learns who anybody is, so the answer to
            // "wrong account" is to change it rather than to read it back.
            child: Text(l.oneNoteCloudOther),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.commonCancel),
        ),
      ],
    );
  }

  /// Screen one: the two ways in.
  Widget _chooseRoute(L l) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RouteCard(
            title: l.oneNoteCloudSignIn,
            body: l.oneNoteSignInBody,
            // The reassurance belongs on the card you press, at the moment
            // you are deciding — not in a paragraph above both of them.
            note: '${l.oneNoteCloudIntro} ${l.oneNoteCloudNoInk}',
            icon: Icons.cloud_outlined,
            enabled: !_busy,
            onTap: _signIn,
          ),
          const SizedBox(height: OnoteSpace.x3),
          _RouteCard(
            title: l.oneNoteFileTitle,
            body: l.oneNoteFileBody,
            icon: Icons.folder_open_outlined,
            enabled: !_busy,
            onTap: _chooseFile,
          ),
          if (_busy) _working(l.oneNoteCloudSigningIn),
          if (_error != null) _problem(),
        ],
      );

  /// Screen two: which notebook.
  Widget _pickNotebook(L l) {
    final list = _notebooks!;
    final s = context.surfaces;
    if (list.isEmpty && !_busy) {
      return Text(l.oneNoteCloudEmpty,
          style: OnoteType.ui.copyWith(color: s.textSecondary));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: list.length,
            itemBuilder: (_, i) => _NotebookRow(
              notebook: list[i],
              onTap: _busy ? null : () => _import(list[i]),
            ),
          ),
        ),
        if (_busy) _working(l.oneNoteCloudLoading),
        if (_error != null) _problem(),
      ],
    );
  }

  Widget _working(String label) => Padding(
        padding: const EdgeInsets.only(top: OnoteSpace.x5),
        child: Row(children: [
          const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: OnoteSpace.x4),
          Flexible(
            child: Text(label,
                style: OnoteType.small
                    .copyWith(color: context.surfaces.textSecondary)),
          ),
        ]),
      );

  Widget _problem() => Padding(
        padding: const EdgeInsets.only(top: OnoteSpace.x5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_error!,
                style: OnoteType.small.copyWith(color: OnoteColors.danger)),
            if (_errorDetail != null) ...[
              const SizedBox(height: OnoteSpace.x2),
              // The technical half stays behind the plain sentence, the way
              // every other failure in this app reports itself.
              SelectableText(_errorDetail!,
                  style: OnoteType.caption
                      .copyWith(color: context.surfaces.textSecondary)),
            ],
          ],
        ),
      );
}

/// One way in, described by what it costs.
class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.title,
    required this.body,
    required this.icon,
    required this.onTap,
    this.note,
    this.enabled = true,
  });

  final String title;
  final String body;

  /// The smaller print underneath — a caveat, never a second sentence of the
  /// same thought.
  final String? note;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    return Opacity(
      opacity: enabled ? 1 : OnoteAlpha.disabled,
      child: InkWell(
        borderRadius: OnoteRadius.mdAll,
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(OnoteSpace.x5),
          decoration: BoxDecoration(
            color: s.chrome2,
            borderRadius: OnoteRadius.mdAll,
            border: Border.all(color: s.border),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: OnoteIcon.lg, color: s.textSecondary),
            const SizedBox(width: OnoteSpace.x5),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style:
                          OnoteType.uiStrong.copyWith(color: s.textPrimary)),
                  const SizedBox(height: OnoteSpace.x1),
                  Text(body,
                      style: OnoteType.small
                          .copyWith(color: s.textSecondary, height: 1.4)),
                  if (note != null) ...[
                    const SizedBox(height: OnoteSpace.x2),
                    Text(note!,
                        style: OnoteType.caption
                            .copyWith(color: s.textSecondary, height: 1.4)),
                  ],
                ],
              ),
            ),
          ]),
        ),
      ),
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
            Icon(Icons.chevron_right,
                size: OnoteIcon.md, color: s.textSecondary),
          ]),
        ),
      ),
    );
  }
}
