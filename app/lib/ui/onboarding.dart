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

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../export/import_job.dart';
import '../export/onenote_import.dart' show OneNoteUnavailable;
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'sync_dialog.dart';
import '../theme/tokens.dart';
import 'onote_dialog.dart';

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
    showOnoteDialog<void>(
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
  bool _importing = false;
  String? _error;

  /// The exception itself, shown only if the student asks for it.
  String? _errorDetail;

  Future<void> _open(String path) async {
    try {
      await app.openExistingNotebook(path);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // A sentence first, the exception behind the fold. The very first
      // screen of the app is the last place to print
      // "FileSystemException: ... errno = 32" and nothing else — the two
      // other failure surfaces in the app (`save_problem_dialog`,
      // `open_notice_dialog`) go to real trouble to keep exactly this text
      // behind "Details (advanced)", and this path had no such fold.
      if (mounted) {
        setState(() {
          _error = "Openote couldn't open that notebook.";
          _errorDetail = '$e';
        });
      }
    }
  }

  /// Pick a `.onepkg` and hand it to the background job. The dialog stays
  /// open: the whole point of importing first is doing the rest of this while
  /// it works.
  Future<void> _startImport() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'OneNote notebook package', extensions: ['onepkg'])
    ]);
    if (file == null || !mounted) return;
    try {
      final job = ImportJob.start(app, p.basename(file.name), file.path);
      if (job != null) setState(() => _importing = true);
    } on OneNoteUnavailable {
      setState(() => _error =
          'OneNote import needs the native core, which this build does not '
          'include.');
    } catch (e) {
      setState(() => _error = "Couldn't read that file: $e");
    }
  }

  /// The in-dialog echo of the floating progress card, so starting the import
  /// visibly *did something* right here — and so the dialog can say the one
  /// sentence that explains the new shape: you don't have to wait.
  Widget _importRow() => ListenableBuilder(
        listenable: ImportJob.current ?? Listenable.merge(const []),
        builder: (context, _) {
          final job = ImportJob.current;
          final s = context.surfaces;
          if (job == null) return const SizedBox.shrink();
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: s.chrome2,
              borderRadius: OnoteRadius.mdAll,
            ),
            child: Row(children: [
              if (!job.isFinished)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2.2))
              else
                Icon(
                    job.state == ImportJobState.done
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    size: 16,
                    color: job.state == ImportJobState.done
                        ? OnoteColors.success
                        : OnoteColors.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          job.state == ImportJobState.done
                              ? 'Your notebook is ready'
                              : 'Importing ${job.fileName}',
                          style: OnoteType.uiStrong
                              .copyWith(color: s.textPrimary)),
                      Text(
                          job.isFinished
                              ? job.message
                              : 'Keep going — this runs in the background, '
                                  'and the card in the corner will say when '
                                  "it's done.",
                          style: OnoteType.caption
                              .copyWith(color: s.textSecondary)),
                    ]),
              ),
              if (job.state == ImportJobState.done)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    job.open();
                  },
                  child: const Text('Open'),
                ),
            ]),
          );
        },
      );

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
              // The import runs in the BACKGROUND, and that is the design:
              // picking the .onepkg is the first thing a switcher should do,
              // so that five years of notes stream in while they finish this
              // dialog and poke around — instead of the app freezing for a
              // minute the moment they arrive. (The old wiring here was also
              // the bug that lost the progress dialog entirely: it popped this
              // dialog and then passed the popped dialog's context as the
              // progress dialog's parent, which failed the mounted check and
              // showed nothing at all.)
              if (_importing)
                _importRow()
              else
                _choice(
                  icon: Icons.library_books_outlined,
                  title: 'Bring my notes over from OneNote',
                  body: 'Imports pages, formatting, images, ink and tags from '
                      'a .onepkg notebook. It runs in the background — keep '
                      'going while it works.',
                  action: _oneNoteHelp ? 'Hide steps' : 'How do I export?',
                  onTap: () => setState(() => _oneNoteHelp = !_oneNoteHelp),
                  secondaryAction: 'Choose file…',
                  onSecondary: _startImport,
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
                if (_errorDetail != null)
                  Theme(
                    // The divider lines an ExpansionTile draws by default cut
                    // the dialog in half for one folded line of text.
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: Text('Details (advanced)',
                          style: OnoteType.caption
                              .copyWith(color: context.surfaces.textSecondary)),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SelectableText(_errorDetail!,
                              style: OnoteType.caption.copyWith(
                                  fontFamily: 'JetBrains Mono',
                                  color: context.surfaces.textSecondary)),
                        ),
                      ],
                    ),
                  ),
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
