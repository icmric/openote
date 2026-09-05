import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../export/import_job.dart';
import '../export/md_import.dart';
import '../export/onenote_import.dart';
import '../model/models.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'join_git_dialog.dart';
import 'onboarding.dart';
import 'sync_dot.dart';
import '../theme/tokens.dart';
import 'onenote_cloud_dialog.dart';
import 'onote_dialog.dart';

/// The notebook manager (style guide §7b) — the one place notebooks are managed.
///
/// **Why a panel and not a pointer menu.** Management used to live in the
/// notebook dropdown: right-clicking a row popped a context menu, which closed
/// the dropdown underneath it. The action worked but the surface you were
/// working in vanished, which read as broken, and deleting three notebooks meant
/// reopening the dropdown three times. Here the list is *stable*: rename in
/// place, delete with an inline confirm, restore from the trash — the list never
/// disappears, and you can do several things in a row. The dropdown keeps only
/// what it is genuinely good at: switching fast.
Future<void> showNotebookManager(BuildContext context, AppState app,
    {String? focusId}) async {
  await app.purgeExpiredTrash();
  if (!context.mounted) return;
  await showOnoteDialog<void>(
    context: context,
    builder: (_) => _NotebookManager(app: app, focusId: focusId),
  );
}

class _NotebookManager extends StatefulWidget {
  const _NotebookManager({required this.app, this.focusId});
  final AppState app;
  final String? focusId;

  @override
  State<_NotebookManager> createState() => _NotebookManagerState();
}

class _NotebookManagerState extends State<_NotebookManager> {
  AppState get app => widget.app;

  /// The notebook whose row is expanded for editing, and which action it shows.
  String? _renamingId;
  String? _confirmDeleteId;
  String? _busyId;
  late String? _highlightId = widget.focusId;

  final _renameCtl = TextEditingController();

  @override
  void dispose() {
    _renameCtl.dispose();
    super.dispose();
  }

  void _startRename(NotebookRef nb) {
    _renameCtl.text = nb.title;
    _renameCtl.selection =
        TextSelection(baseOffset: 0, extentOffset: _renameCtl.text.length);
    setState(() {
      _renamingId = nb.id;
      _confirmDeleteId = null;
    });
  }

  Future<void> _commitRename(NotebookRef nb) async {
    final v = _renameCtl.text.trim();
    setState(() => _renamingId = null);
    if (v.isEmpty || v == nb.title) return;
    await app.renameNotebook(nb.id, v);
    if (mounted) setState(() {});
  }

  Future<void> _delete(NotebookRef nb) async {
    setState(() {
      _confirmDeleteId = null;
      _busyId = nb.id;
    });
    final ok = await app.deleteNotebook(nb.id);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (!ok) {
      _toast("That's your only notebook — create another one first.");
    }
  }

  Future<void> _duplicate(NotebookRef nb) async {
    setState(() => _busyId = nb.id);
    try {
      final copy = await app.duplicateNotebook(nb.id);
      if (mounted) {
        setState(() {
          _busyId = null;
          _highlightId = copy.id;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busyId = null);
        _toast("Couldn't duplicate that notebook: $e");
      }
    }
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final scheme = Theme.of(context).colorScheme;
    final notebooks = app.notebooks;
    final trashed = app.trashedNotebooks;
    return AlertDialog(
      title: Row(children: [
        Icon(Icons.menu_book_outlined, size: 18, color: scheme.primary),
        const SizedBox(width: 9),
        Text(l.nbTitle),
        const Spacer(),
        Text(l.nbOpenCount(notebooks.length),
            style: TextStyle(
                fontSize: 12, color: context.surfaces.textSecondary)),
      ]),
      contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 460),
          child: ListView(
            children: [
              for (final nb in notebooks) _row(nb, scheme),
              if (trashed.isNotEmpty) ...[
                const SizedBox(height: 8),
                _sectionLabel(l.nbInBin(app.recycleRetentionDays)),
                for (final nb in trashed) _trashRow(nb),
              ],
              if (_importOpen) ...[
                const SizedBox(height: 6),
                _sectionLabel(l.nbImportInto),
                _importRow(),
              ],
              // Repeated imports of the same notebook. Shown here rather than
              // behind a button because the whole problem is that nothing ever
              // pointed them out: a real workspace was holding 586 MB, of which
              // ~380 MB was four copies of one OneNote import made while
              // getting the importer working. Each import correctly mints
              // fresh ids, so nothing can merge them automatically — only a
              // person can say they are the same thing, and only if shown.
              ..._duplicateSection(),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      // ONE Row as the single action, because `AlertDialog.actions` is an
      // OverflowBar — a `Spacer` there throws ("applying parent data"), since
      // Spacer needs a Flex parent.
      actions: [
        Row(children: [
          TextButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: Text(l.nbNew),
            onPressed: () async {
              // Through the shared prompt, which owns the field's controller in
              // the dialog's own State. This used to build the field and
              // dispose its controller in a `finally` right after the await —
              // 150 ms before the route's exit transition had finished
              // unmounting the field. That is what crashed the app on Enter;
              // see [promptForText].
              final title = await promptForText(context,
                  title: l.nbNewTitle,
                  okLabel: l.nbCreate,
                  hintText: l.nbNameHint);
              if (title == null || !mounted) return;
              await app.createNotebook(title);
              if (mounted) setState(() {});
            },
          ),
          // Import expands INLINE rather than opening a popup menu: a popup here
          // would be the second kind of menu this panel exists to remove.
          TextButton.icon(
            icon: Icon(_importOpen ? Icons.expand_less : Icons.download_outlined,
                size: 18),
            label: Text(l.nbImport),
            onPressed: () => setState(() => _importOpen = !_importOpen),
          ),
          TextButton.icon(
            icon: const Icon(Icons.healing_outlined, size: 18),
            label: Text(l.nbRepair),
            onPressed: () => _repairWithProgress(context, app),
          ),
          // The welcome flow is where "open the notebook that's already in my
          // Drive" lives, and it should not be a one-shot you can never get
          // back to — that path matters most on a machine you set up months
          // after the first one.
          TextButton.icon(
            icon: const Icon(Icons.explore_outlined, size: 18),
            label: Text(l.nbGetStarted),
            onPressed: () async {
              // Root navigator's context, captured before the pop — the same
              // trap as the import row below: `showDialog` on a route that has
              // just been popped has no live Navigator to attach to.
              final root = Navigator.of(context, rootNavigator: true).context;
              Navigator.pop(context);
              await showOnboarding(root, app);
            },
          ),
          const Spacer(),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.commonDone)),
        ]),
      ],
    );
  }

  /// The inline import choices, shown under the list when Import is expanded.
  ///
  /// **Everything an import needs is captured BEFORE this dialog is popped.**
  /// The obvious spelling — pop, then call `importX(context, app)` — hands the
  /// import the context of a route that no longer exists, so every
  /// `context.mounted` guard inside it is false and the import silently does
  /// nothing at all. That is precisely how the `.onepkg` import stopped
  /// working: the file picker opened, the user chose their notebook, and the
  /// very next line returned.
  ///
  /// A `ScaffoldMessengerState` and the ROOT navigator's context both outlive
  /// this route, so neither can go stale under an import that takes a minute.
  Widget _importRow() {
    final l = L.of(context);
    Widget choice(IconData icon, String label,
            Future<void> Function(ScaffoldMessengerState, BuildContext) run) =>
        Padding(
          padding: const EdgeInsets.only(right: 6, top: 6),
          child: OutlinedButton.icon(
            icon: Icon(icon, size: 16),
            label: Text(label, style: const TextStyle(fontSize: 13)),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final rootContext = Navigator.of(context, rootNavigator: true).context;
              setState(() => _importOpen = false);
              // Close the panel first: the imports that still show a modal put
              // it over the shell, not over a list the user has finished with.
              Navigator.pop(context);
              await run(messenger, rootContext);
            },
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Wrap(children: [
        // FIRST among the OneNote routes, because it is the one that works
        // everywhere. Exporting a .onepkg needs OneNote for Windows; there is
        // no export at all on macOS and no OneNote on Linux, so for two
        // platforms out of three the file routes below are not a slower
        // option, they are no option.
        choice(Icons.cloud_sync_outlined, l.oneNoteCloudTitle,
            (m, c) => showOneNoteCloudDialog(c, app)),
        choice(Icons.library_books_outlined, l.nbImportOnepkg,
            (m, _) => importOneNotePackageWithFeedback(m, app)),
        choice(Icons.upload_file_outlined, l.nbImportOne,
            (m, c) => importOneNoteSectionWithFeedback(c, app, messenger: m)),
        choice(Icons.drive_folder_upload_outlined, l.nbImportMarkdown,
            (m, _) => importMarkdownWithFeedback(m, app)),
        // The other end of "put this notebook on GitHub". It sits with the
        // imports because that is where someone looks for "I have a notebook
        // somewhere else and I want it here" — the fact that this one arrives
        // over git rather than as a file is not the user's distinction to
        // make.
        choice(Icons.cloud_download_outlined, l.nbImportGit,
            (m, c) => showJoinFromGitDialog(c, app, messenger: m)),
      ]),
    );
  }

  bool _importOpen = false;

  /// Groups of notebooks that look like the same import repeated.
  ///
  /// Computed once per open (a container query and a directory walk each), and
  /// silent when there is nothing to say — a panel that shows an empty
  /// "Duplicates" heading to everyone teaches people to ignore the heading.
  ///
  /// Nothing is auto-selected and nothing is deleted here: the row deletes to
  /// the recycle bin through the same `deleteNotebook` path as any other, so
  /// a mistake is recoverable for the retention period.
  late final List<DuplicateGroup> _dupes = app.findDuplicateNotebooks();

  List<Widget> _duplicateSection() {
    final l = L.of(context);
    if (_dupes.isEmpty) return const [];
    return [
      const SizedBox(height: 6),
      _sectionLabel(l.nbDuplicates),
      for (final g in _dupes)
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.nbDuplicateGroup(g.members.length, g.title, g.pages,
                    _bytes(g.reclaimable)),
                style: const TextStyle(fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 2),
              Text(
                // Said explicitly, because "delete the duplicates" is a
                // frightening sentence unless the safest one is named.
                l.nbDuplicatesHint,
                style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: context.surfaces.textSecondary),
              ),
              const SizedBox(height: 4),
              for (final m in g.members)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 2),
                  child: Row(children: [
                    Icon(
                        m == g.members.first
                            ? Icons.star_outline
                            : Icons.content_copy_outlined,
                        size: 14,
                        color: context.surfaces.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          '${m.title} · ${_bytes(m.bytes)}'
                          '${m == g.members.first ? '  (largest — keep)' : ''}'
                          '${m.isOpen ? '  (open)' : ''}',
                          style: const TextStyle(fontSize: 11),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (m != g.members.first && !m.isOpen)
                      TextButton(
                        style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8)),
                        onPressed: _busyId == m.id
                            ? null
                            : () async {
                                setState(() => _busyId = m.id);
                                await app.deleteNotebook(m.id);
                                if (!mounted) return;
                                setState(() {
                                  _busyId = null;
                                  _dupes.remove(g);
                                });
                              },
                        child: Text(l.commonDelete,
                            style: const TextStyle(fontSize: 11)),
                      ),
                  ]),
                ),
            ],
          ),
        ),
    ];
  }

  static String _bytes(int n) {
    if (n >= 1 << 30) return '${(n / (1 << 30)).toStringAsFixed(1)} GB';
    if (n >= 1 << 20) return '${(n / (1 << 20)).toStringAsFixed(0)} MB';
    if (n >= 1 << 10) return '${(n / (1 << 10)).toStringAsFixed(0)} KB';
    return '$n B';
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .6,
                color: context.surfaces.textSecondary)),
      );

  Widget _row(NotebookRef nb, ColorScheme scheme) {
    final l = L.of(context);
    final current = nb.id == app.notebookId;
    final renaming = _renamingId == nb.id;
    final confirming = _confirmDeleteId == nb.id;
    final busy = _busyId == nb.id;
    final counts = app.notebookCounts(nb.id);
    final highlight = _highlightId == nb.id;

    return InkWell(
      // Clicking the row opens that notebook — the switching the dropdown did.
      borderRadius: BorderRadius.circular(8),
      onTap: current || renaming || confirming
          ? null
          : () async {
              Navigator.pop(context);
              await app.selectNotebook(nb.id);
            },
      child: Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: current
            ? scheme.primary.withValues(alpha: .07)
            : highlight
                ? scheme.secondary.withValues(alpha: .10)
                : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: current ? scheme.primary.withValues(alpha: .35) : scheme.outline,
            width: current ? 1.2 : .6),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(current ? Icons.menu_book : Icons.menu_book_outlined,
                  size: 18,
                  color: current ? scheme.primary : context.surfaces.textSecondary),
              const SizedBox(width: 6),
              // Which of these is safe if this laptop dies — answerable by
              // scanning the list, rather than by opening each one in turn.
              SyncDot(app: app, notebookId: nb.id),
              const SizedBox(width: 6),
              Expanded(
                child: renaming
                    ? TextField(
                        controller: _renameCtl,
                        autofocus: true,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                            isDense: true, border: OutlineInputBorder()),
                        onSubmitted: (_) => _commitRename(nb),
                        onTapOutside: (_) => _commitRename(nb),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nb.title,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: current
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: current ? scheme.primary : null)),
                          Text(
                              '${counts.sections} section${counts.sections == 1 ? '' : 's'} · '
                              '${counts.pages} page${counts.pages == 1 ? '' : 's'}'
                              '${current ? ' · open' : ''}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: context.surfaces.textSecondary)),
                        ],
                      ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (!renaming && !confirming) ...[
                if (!current)
                  _act(Icons.open_in_new, l.nbOpenThis, () async {
                    Navigator.pop(context);
                    await app.selectNotebook(nb.id);
                  }),
                _act(Icons.edit_outlined, l.nbRename, () => _startRename(nb)),
                _act(Icons.copy_all_outlined, l.nbDuplicate,
                    () => _duplicate(nb)),
                _act(Icons.delete_outline, l.nbMoveToBin,
                    () => setState(() {
                          _confirmDeleteId = nb.id;
                          _renamingId = null;
                        }),
                    danger: true),
              ],
            ],
          ),
          // Inline confirm — no second dialog, and the list stays put so you can
          // change your mind or delete another one straight after.
          if (confirming)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 28),
              child: Row(children: [
                Expanded(
                  child: Text(l.nbConfirmBin,
                      style: const TextStyle(fontSize: 13)),
                ),
                TextButton(
                    onPressed: () => setState(() => _confirmDeleteId = null),
                    child: Text(l.commonCancel)),
                const SizedBox(width: 4),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: OnoteColors.danger,
                      visualDensity: VisualDensity.compact),
                  onPressed: () => _delete(nb),
                  child: Text(l.commonDelete),
                ),
              ]),
            ),
        ],
      ),
      ),
    );
  }

  Widget _trashRow(NotebookRef nb) {
    final l = L.of(context);
    final days = _daysLeft(nb.deletedAt ?? 0, app.recycleRetentionDays);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(children: [
        const SizedBox(width: 10),
        Icon(Icons.delete_outline,
            size: 16, color: context.surfaces.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nb.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, color: OnoteColors.graphite500)),
              Text(days,
                  style: TextStyle(
                      fontSize: 11, color: context.surfaces.textSecondary)),
            ],
          ),
        ),
        TextButton(
          onPressed: () async {
            await app.restoreNotebook(nb.id);
            if (mounted) setState(() => _highlightId = nb.id);
          },
          child: Text(l.navRestore),
        ),
        _act(Icons.delete_forever, l.navDeletePermanently, () async {
          final ok =
              await _confirmPurge(context, nb, caveat: app.purgeCaveat(nb.id));
          if (!ok || !mounted) return;
          await app.purgeNotebook(nb.id);
          if (mounted) setState(() {});
        }, danger: true),
      ]),
    );
  }

  Widget _act(IconData icon, String tip, VoidCallback onTap,
          {bool danger = false}) =>
      IconButton(
        icon: Icon(icon, size: 16),
        color: danger ? OnoteColors.danger : null,
        visualDensity: VisualDensity.compact,
        tooltip: tip,
        onPressed: onTap,
      );
}

String _daysLeft(int deletedAt, int retentionDays) {
  final remaining = deletedAt +
      Duration(days: retentionDays).inMilliseconds -
      DateTime.now().millisecondsSinceEpoch;
  final days = (remaining / const Duration(days: 1).inMilliseconds).ceil();
  return days <= 0 ? 'Deletes soon' : 'Deletes in $days day${days == 1 ? '' : 's'}';
}

Future<bool> _confirmPurge(BuildContext context, NotebookRef nb,
    {String? caveat}) async {
  final ok = await showOnoteDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(L.of(ctx).navDeleteForeverTitle),
      content: Text(L.of(ctx).navDeleteForeverBody(
          nb.title, caveat == null ? '' : '\n\n$caveat')),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(L.of(ctx).commonCancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: OnoteColors.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(L.of(ctx).navDeleteForever),
        ),
      ],
    ),
  );
  return ok == true;
}

// ── Import entry points ────────────────────────────────────────────────────
// These live here because the notebook manager is the single surface that owns
// notebook-level actions, importing included.

/// Import a `.onepkg` as a new notebook — as a background job.
///
/// This used to be a modal that owned the app for the whole import; the job
/// (see `import_job.dart`) is the same work, chunked, with a floating card
/// for progress and honesty about partial imports at the end. The completion
/// message lives on the card now, so nothing here waits for anything.
/// **Takes a messenger, not a `BuildContext`, on purpose.** The background job
/// needs no context, so there is nothing here that a dead route can stop —
/// which is the structural half of the fix for the import that silently did
/// nothing. `ScaffoldMessengerState` lives above the navigator, so it is still
/// good long after whichever dialog started the import has gone.
Future<void> importOneNotePackageWithFeedback(
    ScaffoldMessengerState messenger, AppState app,
    {Future<XFile?> Function()? pickFile}) async {
  // Through the MESSENGER's context, not a dialog's: this function
  // deliberately takes no `BuildContext` (see above), and the messenger lives
  // above the navigator, so its context is still good.
  final l = L.of(messenger.context);
  final file = await (pickFile?.call() ??
      openFile(acceptedTypeGroups: [
        XTypeGroup(label: l.nbOnePkgFileType, extensions: const ['onepkg'])
      ]));
  if (file == null) return;
  try {
    final job = ImportJob.start(app, p.basename(file.name), file.path);
    _say(
        messenger,
        job == null ? l.nbImportBusy : l.nbImportStarted);
  } on OneNoteUnavailable {
    _say(messenger, l.nbCoreMissing, seconds: 8);
  } catch (e) {
    _say(messenger, l.nbReadFileFailed('$e'));
  }
}

/// Import a single `.one` section into the current notebook.
///
/// Still modal: a section is small, and its parse now happens in an isolate
/// with the decode work, so the dialog is short-lived. [context] must be one
/// that outlives the caller — the root navigator's, not a dialog's — or the
/// progress dialog silently does not appear. [messenger] carries the result
/// even if that context has gone by the time the import finishes.
Future<void> importOneNoteSectionWithFeedback(BuildContext context, AppState app,
    {ScaffoldMessengerState? messenger}) async {
  final m = messenger ?? ScaffoldMessenger.of(context);
  final l = L.of(context);
  try {
    final count = await importOneNoteFile(app, progressContext: context);
    if (count == null) return;
    _say(
        m,
        count == 0
            ? l.nbOneFileEmpty
            : l.nbImportedFromOneNote(
                importArrivalNote(count, lastImportedImages,
                    lastImportedStrokes, lastImportedTags),
                _strokeNote()));
  } on OneNoteUnavailable {
    _say(m, l.nbCoreMissing, seconds: 8);
  }
}

/// Import a folder of Markdown (Obsidian-style) as a new section.
Future<void> importMarkdownWithFeedback(
    ScaffoldMessengerState messenger, AppState app) async {
  // **It says what it is doing while it does it.** A vault of a few hundred
  // notes is seconds of work, and there was nothing on screen for any of it.
  final l = L.of(messenger.context);
  final progress = ValueNotifier<String>(l.nbReadingFolder);
  int? count;
  try {
    count = await importMarkdownFolder(
      app,
      onProgress: (done) => progress.value = l.nbImportedPagesProgress(done),
    );
  } catch (e) {
    progress.dispose();
    _say(messenger, l.nbReadFolderFailed('$e'), seconds: 8);
    return;
  }
  progress.dispose();
  if (count == null) return;
  _say(messenger,
      count == 0 ? l.nbNoMarkdown : l.nbImportedPages(count));
}

/// Show a snackbar through a messenger that cannot go stale.
void _say(ScaffoldMessengerState m, String msg, {int seconds = 4}) =>
    m.showSnackBar(
        SnackBar(content: Text(msg), duration: Duration(seconds: seconds)));

/// One sentence when the parser dropped undecodable ink (~0.02 % of strokes on
/// the reference notebook). The notes LOOK complete when a stroke vanishes,
/// which is exactly why it has to be said out loud.
/// What arrived, in the switcher's own terms (P5).
String _strokeNote() => lastDroppedStrokes == 0
    ? ''
    : ' $lastDroppedStrokes ink stroke'
        '${lastDroppedStrokes == 1 ? '' : 's'} could not be decoded and '
        '${lastDroppedStrokes == 1 ? 'was' : 'were'} left out.';

/// "Repair" — heal every page of the open notebook at once.
///
/// The on-open repair is lazy on purpose (a clean page pays nothing), but a
/// notebook imported before the importer was fixed keeps its `﷟HYPERLINK`
/// junk and its needless `$…$` on every page you have not happened to visit.
/// This is the explicit "just fix all of it" pass, with a live count because
/// on a 300-page notebook it is seconds rather than milliseconds.
Future<void> _repairWithProgress(BuildContext context, AppState app) async {
  final l = L.of(context);
  final progress = ValueNotifier<String>(l.nbCheckingPages);
  var open = false;
  if (context.mounted) {
    open = true;
    showOnoteDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.6)),
          const SizedBox(width: 16),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: progress,
              builder: (_, t, __) => Text(t),
            ),
          ),
        ]),
      ),
    );
  }
  try {
    final r = await app.repairWholeNotebook(
      onProgress: (done, total) =>
          progress.value = l.nbCheckingPageProgress(done, total),
    );
    if (open && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      open = false;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 5),
      content: Text(r.pages == 0
          ? l.nbNothingToRepair
          : l.nbRepaired(
              l.nbRepairedBoxes(r.blocks), l.nbRepairedPages(r.pages))),
    ));
  } catch (e) {
    if (open && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.nbRepairFailed('$e'))));
    }
  } finally {
    progress.dispose();
  }
}
