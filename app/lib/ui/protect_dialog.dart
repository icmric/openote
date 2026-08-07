/// The dialogs for passcode-gating a page, section or section group.
///
/// The wording here is load-bearing, not decoration. What this feature does
/// and does not do is stated in the dialog that SETS a passcode, before the
/// first page is ever locked — see page_protection.dart for why. A user who
/// reads "password protect" and assumes their file is safe has been misled by
/// us, not by their own carelessness, and the only place to prevent that is
/// here, at the moment they decide.
library;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/page_protection.dart';
import '../theme/onote_theme.dart';

/// Ask for a new passcode and a policy. Returns null if cancelled.
Future<({String passcode, UnlockPolicy policy})?> askNewPasscode(
        BuildContext context, String nodeTitle) =>
    showDialog<({String passcode, UnlockPolicy policy})>(
      context: context,
      builder: (_) => _SetPasscodeDialog(nodeTitle: nodeTitle),
    );

/// Ask for an existing passcode. Returns null if cancelled, else the attempt.
/// [verify] is called so a wrong entry can be reported without closing.
Future<bool> askToUnlock(
        BuildContext context, String nodeTitle, bool Function(String) verify) =>
    showDialog<bool>(
      context: context,
      builder: (_) => _UnlockDialog(nodeTitle: nodeTitle, verify: verify),
    ).then((v) => v ?? false);

class _SetPasscodeDialog extends StatefulWidget {
  const _SetPasscodeDialog({required this.nodeTitle});
  final String nodeTitle;

  @override
  State<_SetPasscodeDialog> createState() => _SetPasscodeDialogState();
}

class _SetPasscodeDialogState extends State<_SetPasscodeDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  UnlockPolicy _policy = UnlockPolicy.session;
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _submit() {
    final pw = _a.text;
    if (pw.isEmpty) {
      setState(() => _error = 'Enter a passcode.');
      return;
    }
    if (pw != _b.text) {
      setState(() => _error = 'The two entries do not match.');
      return;
    }
    Navigator.of(context).pop((passcode: pw, policy: _policy));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.lock_outline, size: 19),
        const SizedBox(width: 8),
        Flexible(child: Text('Lock “${widget.nodeTitle}”')),
      ]),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Said first, and in full, because after this dialog there is no
              // other moment where the user is deciding what to trust it with.
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: OnoteColors.brass400.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('This hides the page inside Openote. '
                        'It does not encrypt it.',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    SizedBox(height: 6),
                    Text(
                      'Anyone who has your notebook file can still read this '
                      'page — the passcode only applies to this copy of '
                      'Openote on this computer. Do not use it for anything '
                      'you would be harmed by someone else reading.',
                      style: TextStyle(fontSize: 12.5, height: 1.45),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'There is no way to recover a forgotten passcode, but '
                      'your notes are not lost either: they are still in the '
                      'file.',
                      style: TextStyle(fontSize: 12.5, height: 1.45),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _a,
                autofocus: true,
                obscureText: true,
                decoration:
                    InputDecoration(labelText: 'Passcode', errorText: _error),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _b,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Passcode again'),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              const Text('Ask for it again…',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              RadioGroup<UnlockPolicy>(
                groupValue: _policy,
                onChanged: (v) => setState(() => _policy = v ?? _policy),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final p in UnlockPolicy.values)
                      RadioListTile<UnlockPolicy>(
                        value: p,
                        title: Text(p.label,
                            style: const TextStyle(fontSize: 13.5)),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Lock')),
      ],
    );
  }
}

class _UnlockDialog extends StatefulWidget {
  const _UnlockDialog({required this.nodeTitle, required this.verify});
  final String nodeTitle;
  final bool Function(String) verify;

  @override
  State<_UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends State<_UnlockDialog> {
  final _c = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    // Verified in place rather than by returning the attempt, so a wrong
    // passcode keeps the dialog open with the caret where it was — retyping
    // from a closed dialog is the thing that makes a lock feel punitive.
    if (widget.verify(_c.text)) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = 'That is not the passcode.');
      _c.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.lock_outline, size: 19),
        const SizedBox(width: 8),
        Flexible(child: Text('“${widget.nodeTitle}” is locked')),
      ]),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: _c,
          autofocus: true,
          obscureText: true,
          decoration: InputDecoration(labelText: 'Passcode', errorText: _error),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Unlock')),
      ],
    );
  }
}

/// Run the whole "the user clicked a locked page" interaction. Returns true
/// when the subtree is now unlocked.
Future<bool> promptUnlock(
    BuildContext context, AppState app, String nodeId) async {
  final root = app.governingNode(nodeId);
  if (root == null || !app.isLocked(nodeId)) return true;
  final title =
      app.nodes.where((n) => n.id == root).firstOrNull?.title ?? 'This';
  return askToUnlock(context, title, (pw) => app.unlockNode(nodeId, pw));
}
