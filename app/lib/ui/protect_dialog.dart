/// The dialogs for passcode-gating a page, section or section group.
///
/// The wording here is load-bearing, not decoration. What this feature does
/// and does not do is stated in the dialog that SETS a passcode, before the
/// first page is ever locked — see page_protection.dart for why. A user who
/// reads "password protect" and assumes their file is safe has been misled by
/// us, not by their own carelessness, and the only place to prevent that is
/// here, at the moment they decide.
///
/// It is kept SHORT, and says "beta" and "yet", on the owner's instruction:
/// *"at the moment it is stated like its super insecure (which granted it is),
/// but that also it will not be changed or made more secure in the future,
/// which i plan on doing."* A warning long enough to be skipped protects
/// nobody, and one that implies the limitation is permanent is now simply
/// wrong — ADR-0008 is the plan. Both facts a user needs are still here: the
/// file is readable without the passcode, and the passcode cannot be
/// recovered.
library;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../state/page_protection.dart';
import '../theme/onote_theme.dart';
import 'onote_dialog.dart';

/// Ask for a new passcode and a policy. Returns null if cancelled.
Future<({String passcode, UnlockPolicy policy})?> askNewPasscode(
        BuildContext context, String nodeTitle) =>
    showOnoteDialog<({String passcode, UnlockPolicy policy})>(
      context: context,
      builder: (_) => _SetPasscodeDialog(nodeTitle: nodeTitle),
    );

/// Ask for an existing passcode. Returns null if cancelled, else the attempt.
/// [verify] is called so a wrong entry can be reported without closing.
Future<bool> askToUnlock(
        BuildContext context, String nodeTitle, bool Function(String) verify) =>
    showOnoteDialog<bool>(
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
      setState(() => _error = L.of(context).protectEnterPasscode);
      return;
    }
    if (pw != _b.text) {
      setState(() => _error = L.of(context).protectMismatch);
      return;
    }
    Navigator.of(context).pop((passcode: pw, policy: _policy));
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.lock_outline, size: 19),
        const SizedBox(width: 8),
        Flexible(child: Text(l.protectLockTitle(widget.nodeTitle))),
      ]),
      content: SizedBox(
        width: 460,
        child: DialogScrollBody(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.protectBetaHeadline,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(
                      l.protectBetaBody,
                      style: const TextStyle(fontSize: 12.5, height: 1.45),
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
                    InputDecoration(labelText: l.protectPasscode, errorText: _error),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _b,
                obscureText: true,
                decoration: InputDecoration(labelText: l.protectPasscodeAgain),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              Text(l.protectAskAgain,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
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
                        title: Text(_policyLabel(l, p),
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
            child: Text(l.commonCancel)),
        FilledButton(onPressed: _submit, child: Text(l.protectLock)),
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
      setState(() => _error = L.of(context).protectWrong);
      _c.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.lock_outline, size: 19),
        const SizedBox(width: 8),
        Flexible(child: Text(l.protectLockedTitle(widget.nodeTitle))),
      ]),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: _c,
          autofocus: true,
          obscureText: true,
          decoration:
              InputDecoration(labelText: l.protectPasscode, errorText: _error),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.commonCancel)),
        FilledButton(onPressed: _submit, child: Text(l.shellUnlock)),
      ],
    );
  }
}

/// **Before a window shows, or is made onto, page [pageId]** (v1.0.2 bug 33).
///
/// True at once for a page a window may already show; otherwise only once the
/// passcode has been given, which opens the windows onto that passcode's pages
/// for the rest of this visit to the open page — and nothing else: the page
/// stays locked in the navigator. See [AppState.windowShows].
Future<bool> confirmWindowOnto(
    BuildContext context, AppState app, String pageId) async {
  if (app.windowShows(pageId)) return true;
  if (app.node(pageId) == null) return false; // in the recycle bin
  return askToUnlock(context, app.windowLockTitle(pageId),
      (pw) => app.unlockWindowsOnto(pageId, pw));
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

/// How long an unlock lasts, in the person's language. [UnlockPolicy.label]
/// stays the English name the policy is known by in code.
String _policyLabel(L l, UnlockPolicy p) => switch (p) {
      UnlockPolicy.always => l.protectPolicyAlways,
      UnlockPolicy.tenMinutes => l.protectPolicyTenMinutes,
      UnlockPolicy.oneHour => l.protectPolicyOneHour,
      UnlockPolicy.session => l.protectPolicySession,
    };
