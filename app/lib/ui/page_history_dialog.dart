/// "Recent changes" — the surface for the simplified version history
/// (v0.17 plan, Step 8a).
///
/// Two questions, and the plainest words for each:
///
///  * **Who changed what you can see.** One line per thing on the page, with a
///    computer's *name* — never a device id. A device the notebook has no name
///    for reads *"another computer"*, which is true and is not jargon.
///  * **What was deleted.** The last ten deletions worth remembering: a page, a
///    section, anything holding a picture, drawing, file or recording, and a
///    paragraph-sized piece of writing. Not every keystroke, and deliberately
///    not eraser gestures — one tidy-up would fill the list by itself. Undo is
///    the remedy for editing.
///
/// The jargon rule (PLANNING, "no jargon", year-10 bar): no uuid, no Lamport
/// clock, no "op", no file extension anywhere a student reads. All of that
/// lives under **Details (advanced)**, folded away, matching
/// `open_notice_dialog.dart` and `save_problem_dialog.dart`.
library;

import 'package:flutter/material.dart';

import '../model/history.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'onote_dialog.dart';

Future<void> showPageHistory(BuildContext context, AppState app) async {
  // The list is a fold of the log tail, so it is fetched before the dialog
  // rather than inside it: an empty list that fills in a frame later reads as
  // "nothing was recorded", which is the one thing this must never say wrongly.
  final nb = app.notebookId;
  if (nb != null) await app.refreshHistory(nb);
  if (!context.mounted) return;
  await showOnoteDialog<void>(
    context: context,
    builder: (_) => _PageHistoryDialog(app: app),
  );
}

class _PageHistoryDialog extends StatefulWidget {
  const _PageHistoryDialog({required this.app});
  final AppState app;

  @override
  State<_PageHistoryDialog> createState() => _PageHistoryDialogState();
}

class _PageHistoryDialogState extends State<_PageHistoryDialog> {
  AppState get app => widget.app;
  String? _note;

  @override
  Widget build(BuildContext context) {
    final nb = app.notebookId;
    final labels = nb == null ? const <String, String>{} : app.deviceLabels(nb);
    final me = app.localDeviceId();
    final authors = app.pageAuthors();
    final deletions = app.recentDeletions();
    final snapshots = app.pageVersions();

    String who(String device) => deviceDisplayName(labels[device],
        isThisComputer: device == me);

    return AlertDialog(
      title: const Text('Recent changes'),
      content: SizedBox(
        width: 420,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 460),
          child: ListView(
            shrinkWrap: true,
            children: [
              if (_note != null) ...[
                Text(_note!,
                    style: const TextStyle(
                        fontSize: 12.5, color: OnoteColors.danger)),
                const SizedBox(height: 8),
              ],
              _heading('Who changed this page'),
              if (authors.isEmpty)
                _quiet('Nothing recorded for this page yet. It fills in as you '
                    'and anyone you share with make changes.')
              else
                for (final b in app.blocks)
                  if (authors[b.id] != null)
                    _changeLine(authors[b.id]!, who(authors[b.id]!.device)),
              const SizedBox(height: 14),
              _heading('Recently deleted'),
              _quiet('The last ten things worth keeping track of — pages, '
                  'sections, and anything holding a picture, drawing, file or '
                  'recording. Everyday typing is not listed; use undo for that.'),
              const SizedBox(height: 4),
              if (deletions.isEmpty)
                _quiet('Nothing yet.')
              else
                for (final d in deletions) _deletionLine(d, who(d.device)),
              if (snapshots.isNotEmpty) ...[
                const SizedBox(height: 14),
                _heading('Earlier copies of this page'),
                for (final at in snapshots.take(30))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    leading: const Icon(Icons.history, size: 16),
                    title:
                        Text(whenWords(at), style: const TextStyle(fontSize: 13)),
                    trailing: TextButton(
                      child: const Text('Put this back'),
                      onPressed: () async {
                        await app.restoreVersion(at);
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  ),
              ],
              const SizedBox(height: 6),
              _advanced(authors, deletions, labels, me),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      );

  Widget _quiet(String text) => Text(text,
      style: const TextStyle(
          fontSize: 12, height: 1.35, color: OnoteColors.graphite400));

  Widget _changeLine(BlockAuthor a, String who) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text('${a.friendlyKind} — changed by $who, ${whenWords(a.changedAt)}',
            style: const TextStyle(fontSize: 13)),
      );

  Widget _deletionLine(NotableDeletion d, String who) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        leading: Icon(_iconFor(d.kind), size: 16),
        title: Text('${_wordFor(d)} — deleted by $who',
            style: const TextStyle(fontSize: 13)),
        subtitle:
            Text(whenWords(d.deletedAt), style: const TextStyle(fontSize: 11)),
        trailing: TextButton(
          child: const Text('Put it back'),
          onPressed: () async {
            final ok = await app.restoreDeletion(d);
            if (!mounted) return;
            if (ok) {
              Navigator.pop(context);
            } else {
              setState(() => _note =
                  "Openote couldn't find that one to put back. Nothing was "
                  'changed.');
            }
          },
        ),
      );

  static IconData _iconFor(DeletionKind k) => switch (k) {
        DeletionKind.page => Icons.description_outlined,
        DeletionKind.section => Icons.folder_outlined,
        DeletionKind.sectionGroup => Icons.folder_copy_outlined,
        DeletionKind.block => Icons.delete_outline,
      };

  /// The noun a student would use. A section says "section", a page says the
  /// page's own name — nothing here says "node", "block" or "subtree".
  static String _wordFor(NotableDeletion d) => switch (d.kind) {
        DeletionKind.page => 'Page "${d.what}"',
        DeletionKind.section => 'Section "${d.what}" and everything in it',
        DeletionKind.sectionGroup =>
          'Group "${d.what}" and everything in it',
        DeletionKind.block => d.what,
      };

  /// Everything a student never has to see, for the one person in a hundred
  /// who wants it: which computer wrote what, and the counters that put those
  /// changes in order.
  Widget _advanced(Map<String, BlockAuthor> authors,
      List<NotableDeletion> deletions, Map<String, String> labels, String me) {
    final lines = <String>[
      'this device: $me',
      for (final e in labels.entries) 'device ${e.key} = "${e.value}"',
      for (final e in authors.entries)
        'block ${e.key}: dev=${e.value.device} lc=${e.value.lamport} '
            'seq=${e.value.seq}',
      for (final d in deletions)
        'deleted ${d.kind.name} ${d.targetId}: dev=${d.device} lc=${d.lamport} '
            'seq=${d.seq} pins=${d.pins.length}',
    ];
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      shape: const Border(),
      title:
          const Text('Details (advanced)', style: TextStyle(fontSize: 12.5)),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            lines.join('\n'),
            style: const TextStyle(
                fontFamily: 'JetBrains Mono',
                fontFamilyFallback: onoteFontFallback,
                fontSize: 11),
          ),
        ),
      ],
    );
  }
}

/// A time in the words people use, not a timestamp.
String whenWords(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final hm =
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (day == today) return 'today at $hm';
  if (day == today.subtract(const Duration(days: 1))) {
    return 'yesterday at $hm';
  }
  return '${d.day}/${d.month}/${d.year} at $hm';
}
