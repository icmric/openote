/// First run: the three things somebody actually arrives wanting to do.
///
/// **Why this exists.** A new install dropped you into an empty notebook with
/// no hint that any of the interesting paths existed. The three real starting
/// points — I already have this notebook on another machine, I am coming from
/// OneNote, I am starting fresh — were spread across a folder dialog, an
/// inline Import row inside the notebook manager, and nothing at all.
///
/// The second-device case is the one worth engineering: it *looks* for the
/// notebook rather than asking where it is. If your cloud folder already has
/// an Openote notebook in it, that is almost certainly the answer, and the
/// difference between offering it and asking for a path is the difference
/// between sync working and sync being a thing you gave up on.
library;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'notebook_manager.dart';
import 'sync_dialog.dart';
import '../theme/tokens.dart';

/// Show the welcome flow if this workspace has never been used.
///
/// "Never been used" means: the setting has not been stamped AND the workspace
/// holds nothing but the starter notebook. Both conditions, because someone
/// who upgraded into this version has notebooks and must not be greeted as a
/// beginner.
Future<void> maybeShowOnboarding(BuildContext context, AppState app) async {
  if (app.onboardingSeen) return;
  final fresh = app.notebooks.length <= 1 &&
      app.nodes.where((n) => n.kind == NodeKind.page).length <= 1;
  app.markOnboardingSeen();
  if (!fresh || !context.mounted) return;
  await showOnboarding(context, app);
}

Future<void> showOnboarding(BuildContext context, AppState app) =>
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _Onboarding(app: app),
    );

class _Onboarding extends StatefulWidget {
  const _Onboarding({required this.app});
  final AppState app;

  @override
  State<_Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<_Onboarding> {
  AppState get app => widget.app;

  late final List<({String name, String path, dynamic folder})> _found =
      findExistingNotebooks()
          .map((e) => (name: e.name, path: e.path, folder: e.folder as dynamic))
          .toList();

  bool _oneNoteHelp = false;
  String? _error;

  Future<void> _open(String path) async {
    try {
      await app.openExistingNotebook(path);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(children: [
        Icon(Icons.menu_book_outlined, size: 20, color: scheme.primary),
        const SizedBox(width: 9),
        const Text('Welcome to Openote'),
      ]),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your notes live in an open, readable file you own. Pick a '
                'starting point — you can do any of these later too.',
                style: TextStyle(fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 14),

              // Found notebooks first: on a second machine this is the answer,
              // and offering it beats asking for a path.
              if (_found.isNotEmpty) ...[
                _label('Already have a notebook in your cloud folder'),
                for (final n in _found)
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.cloud_done_outlined, size: 20),
                      title: Text(n.name,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text(p.dirname(n.path),
                          style: const TextStyle(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      trailing: FilledButton(
                        onPressed: () => _open(n.path),
                        child: const Text('Open'),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
              ],

              _label('Start here'),
              _choice(
                icon: Icons.cloud_sync_outlined,
                title: 'Sync with another device',
                body: _found.isEmpty
                    ? 'Put this notebook in a folder your cloud already keeps '
                        'in step — Drive, OneDrive, iCloud, Dropbox, '
                        'Syncthing, a NAS. No account and no sign-in.'
                    : "Not one of the above? Choose the folder yourself.",
                action: 'Choose folder…',
                onTap: () async {
                  Navigator.of(context).pop();
                  await showSyncDialog(context, app);
                },
              ),
              _choice(
                icon: Icons.library_books_outlined,
                title: 'Bring my notes over from OneNote',
                body: 'Imports pages, formatting, images, ink and tags from a '
                    '.onepkg notebook or a .one section.',
                action: _oneNoteHelp ? 'Hide steps' : 'How do I export?',
                onTap: () => setState(() => _oneNoteHelp = !_oneNoteHelp),
                secondaryAction: 'Choose file…',
                onSecondary: () async {
                  Navigator.of(context).pop();
                  await importOneNotePackageWithFeedback(context, app);
                },
              ),
              if (_oneNoteHelp) _oneNoteSteps(),
              _choice(
                icon: Icons.note_add_outlined,
                title: 'Just start writing',
                body: 'A notebook is already open. Click anywhere on the page '
                    'and type; drag a picture in from anywhere.',
                action: 'Start',
                onTap: () => Navigator.of(context).pop(),
              ),

              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(
                        fontSize: 12, color: OnoteColors.danger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Skip')),
      ],
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .6,
                color: context.surfaces.textSecondary)),
      );

  Widget _choice({
    required IconData icon,
    required String title,
    required String body,
    required String action,
    required VoidCallback onTap,
    String? secondaryAction,
    VoidCallback? onSecondary,
  }) =>
      Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: context.surfaces.textSecondary),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(body,
                      style: const TextStyle(fontSize: 12, height: 1.4)),
                  Row(children: [
                    TextButton(
                        onPressed: onTap,
                        child:
                            Text(action, style: const TextStyle(fontSize: 12))),
                    if (secondaryAction != null)
                      FilledButton.tonal(
                        onPressed: onSecondary,
                        child: Text(secondaryAction,
                            style: const TextStyle(fontSize: 12)),
                      ),
                  ]),
                ],
              ),
            ),
          ]),
        ),
      );

  /// Exporting from OneNote is the step people get stuck on, and it is not
  /// discoverable — the desktop app hides it, and the web and store versions
  /// cannot do it at all. Saying so plainly beats letting someone hunt.
  Widget _oneNoteSteps() => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: context.surfaces.textSecondary.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Exporting from OneNote',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text(
              '1. Open OneNote for Windows (the desktop app — the Store and '
              'web versions cannot export).\n'
              '2. Make sure the notebook has finished syncing, so everything '
              'is on this machine.\n'
              '3. File ▸ Export ▸ Notebook ▸ OneNote Package (*.onepkg), then '
              'Export.\n'
              '4. Come back here and choose that file.',
              style: TextStyle(fontSize: 12, height: 1.55),
            ),
            const SizedBox(height: 8),
            Text(
              'On a Mac, or with only the Store version: export one section at '
              'a time as .one, or ask a Windows machine to make the .onepkg. '
              'Openote never signs into your Microsoft account — it only reads '
              'the file you hand it.',
              style: TextStyle(
                  fontSize: 11, height: 1.45, color: context.surfaces.textSecondary),
            ),
          ],
        ),
      );
}
