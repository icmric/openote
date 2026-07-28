import 'package:flutter/material.dart';

import '../export/md_import.dart';
import '../export/onenote_import.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';

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
  await showDialog<void>(
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
    final scheme = Theme.of(context).colorScheme;
    final notebooks = app.notebooks;
    final trashed = app.trashedNotebooks;
    return AlertDialog(
      title: Row(children: [
        Icon(Icons.menu_book_outlined, size: 19, color: scheme.primary),
        const SizedBox(width: 9),
        const Text('Notebooks'),
        const Spacer(),
        Text('${notebooks.length} open',
            style: const TextStyle(
                fontSize: 12, color: OnoteColors.graphite400)),
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
                _sectionLabel(
                    'In the recycle bin · deleted after ${app.recycleRetentionDays} days'),
                for (final nb in trashed) _trashRow(nb),
              ],
              if (_importOpen) ...[
                const SizedBox(height: 6),
                _sectionLabel('Import into a new notebook'),
                _importRow(),
              ],
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
            icon: const Icon(Icons.add, size: 17),
            label: const Text('New'),
            onPressed: () async {
              final title = await _promptNotebookName(context,
                  title: 'New notebook', okLabel: 'Create');
              if (title == null || !mounted) return;
              await app.createNotebook(title);
              if (mounted) setState(() {});
            },
          ),
          // Import expands INLINE rather than opening a popup menu: a popup here
          // would be the second kind of menu this panel exists to remove.
          TextButton.icon(
            icon: Icon(_importOpen ? Icons.expand_less : Icons.download_outlined,
                size: 17),
            label: const Text('Import'),
            onPressed: () => setState(() => _importOpen = !_importOpen),
          ),
          const Spacer(),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done')),
        ]),
      ],
    );
  }

  /// The inline import choices, shown under the list when Import is expanded.
  Widget _importRow() {
    Widget choice(IconData icon, String label, Future<void> Function() run) =>
        Padding(
          padding: const EdgeInsets.only(right: 6, top: 6),
          child: OutlinedButton.icon(
            icon: Icon(icon, size: 16),
            label: Text(label, style: const TextStyle(fontSize: 12.5)),
            onPressed: () async {
              setState(() => _importOpen = false);
              // Close the panel first: import shows its own progress dialog and
              // then navigates to the imported notebook.
              Navigator.pop(context);
              await run();
            },
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Wrap(children: [
        choice(Icons.library_books_outlined, 'OneNote notebook (.onepkg)',
            () => importOneNotePackageWithFeedback(context, app)),
        choice(Icons.upload_file_outlined, 'OneNote section (.one)',
            () => importOneNoteSectionWithFeedback(context, app)),
        choice(Icons.drive_folder_upload_outlined, 'Markdown folder',
            () => importMarkdownWithFeedback(context, app)),
      ]),
    );
  }

  bool _importOpen = false;

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .6,
                color: OnoteColors.graphite400)),
      );

  Widget _row(NotebookRef nb, ColorScheme scheme) {
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
                  color: current ? scheme.primary : OnoteColors.graphite400),
              const SizedBox(width: 10),
              Expanded(
                child: renaming
                    ? TextField(
                        controller: _renameCtl,
                        autofocus: true,
                        style: const TextStyle(fontSize: 14),
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
                                  fontSize: 14,
                                  fontWeight: current
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: current ? scheme.primary : null)),
                          Text(
                              '${counts.sections} section${counts.sections == 1 ? '' : 's'} · '
                              '${counts.pages} page${counts.pages == 1 ? '' : 's'}'
                              '${current ? ' · open' : ''}',
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  color: OnoteColors.graphite400)),
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
                  _act(Icons.open_in_new, 'Open this notebook', () async {
                    Navigator.pop(context);
                    await app.selectNotebook(nb.id);
                  }),
                _act(Icons.edit_outlined, 'Rename', () => _startRename(nb)),
                _act(Icons.copy_all_outlined, 'Duplicate',
                    () => _duplicate(nb)),
                _act(Icons.delete_outline, 'Move to recycle bin',
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
                const Expanded(
                  child: Text(
                      'Move to the recycle bin? You can restore it from here.',
                      style: TextStyle(fontSize: 12.5)),
                ),
                TextButton(
                    onPressed: () => setState(() => _confirmDeleteId = null),
                    child: const Text('Cancel')),
                const SizedBox(width: 4),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: OnoteColors.danger,
                      visualDensity: VisualDensity.compact),
                  onPressed: () => _delete(nb),
                  child: const Text('Delete'),
                ),
              ]),
            ),
        ],
      ),
      ),
    );
  }

  Widget _trashRow(NotebookRef nb) {
    final days = _daysLeft(nb.deletedAt ?? 0, app.recycleRetentionDays);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(children: [
        const SizedBox(width: 10),
        const Icon(Icons.delete_outline,
            size: 16, color: OnoteColors.graphite400),
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
                  style: const TextStyle(
                      fontSize: 11, color: OnoteColors.graphite400)),
            ],
          ),
        ),
        TextButton(
          onPressed: () async {
            await app.restoreNotebook(nb.id);
            if (mounted) setState(() => _highlightId = nb.id);
          },
          child: const Text('Restore'),
        ),
        _act(Icons.delete_forever, 'Delete permanently', () async {
          final ok = await _confirmPurge(context, nb);
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

Future<bool> _confirmPurge(BuildContext context, NotebookRef nb) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete permanently?'),
      content: Text('“${nb.title}” and all its pages will be removed for good. '
          "This can't be undone."),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: OnoteColors.danger),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete forever'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Single-field name prompt used by "New notebook".
Future<String?> _promptNotebookName(BuildContext context,
    {required String title, required String okLabel, String? initial}) async {
  final controller = TextEditingController(text: initial);
  controller.selection =
      TextSelection(baseOffset: 0, extentOffset: controller.text.length);
  try {
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Notebook name'),
          onSubmitted: (s) => Navigator.pop(ctx, s),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(okLabel)),
        ],
      ),
    );
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  } finally {
    controller.dispose(); // the old prompt leaked one of these per invocation
  }
}

// ── Import entry points ────────────────────────────────────────────────────
// These live here because the notebook manager is the single surface that owns
// notebook-level actions, importing included.

/// Import a `.onepkg` as a new notebook, reporting partial imports honestly.
Future<void> importOneNotePackageWithFeedback(
    BuildContext context, AppState app) async {
  try {
    final count = await importOneNotePackage(app, progressContext: context);
    if (count == null || !context.mounted) return;
    final skipped = lastSkippedSections;
    final err = lastImportError;
    final String msg;
    if (count == 0) {
      msg = err == null
          ? "Couldn't read any sections from that .onepkg file."
          : "That notebook couldn't be imported: $err";
    } else if (skipped.isEmpty) {
      msg = 'Imported a notebook with $count page'
          '${count == 1 ? '' : 's'} from OneNote.'
          '${_strokeNote()}';
    } else {
      msg = 'Imported $count page${count == 1 ? '' : 's'}, but '
          '${skipped.length} section${skipped.length == 1 ? '' : 's'} '
          'could not be read: ${skipped.take(3).join(', ')}'
          '${skipped.length > 3 ? '…' : ''}'
          '${_strokeNote()}';
    }
    _snack(context, msg,
        seconds:
            skipped.isEmpty && count > 0 && lastDroppedStrokes == 0 ? 4 : 9);
  } on OneNoteUnavailable {
    if (context.mounted) _snack(context, _coreMissing, seconds: 8);
  }
}

/// Import a single `.one` section into the current notebook.
Future<void> importOneNoteSectionWithFeedback(
    BuildContext context, AppState app) async {
  try {
    final count = await importOneNoteFile(app, progressContext: context);
    if (count == null || !context.mounted) return;
    _snack(
        context,
        count == 0
            ? "Couldn't read any content from that .one file."
            : 'Imported $count page${count == 1 ? '' : 's'} from OneNote.');
  } on OneNoteUnavailable {
    if (context.mounted) _snack(context, _coreMissing, seconds: 8);
  }
}

/// Import a folder of Markdown (Obsidian-style) as a new section.
Future<void> importMarkdownWithFeedback(
    BuildContext context, AppState app) async {
  final count = await importMarkdownFolder(app);
  if (count == null || !context.mounted) return;
  _snack(
      context,
      count == 0
          ? 'No Markdown files found in that folder.'
          : 'Imported $count page${count == 1 ? '' : 's'}.');
}

const _coreMissing =
    'OneNote import needs the Rust core — build onote_core.dll '
    '(see rust/onote_core/INTEGRATION.md).';

/// One sentence when the parser dropped undecodable ink (~0.02 % of strokes on
/// the reference notebook). The notes LOOK complete when a stroke vanishes,
/// which is exactly why it has to be said out loud.
String _strokeNote() => lastDroppedStrokes == 0
    ? ''
    : ' $lastDroppedStrokes ink stroke'
        '${lastDroppedStrokes == 1 ? '' : 's'} could not be decoded and '
        '${lastDroppedStrokes == 1 ? 'was' : 'were'} left out.';

void _snack(BuildContext context, String msg, {int seconds = 4}) =>
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: Duration(seconds: seconds)));
