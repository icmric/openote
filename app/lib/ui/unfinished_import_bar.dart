/// **The quiet reminder that a notebook is not all here yet.**
///
/// The owner, on an import that stopped when Microsoft throttled it: *"Even if
/// they dismiss this warning i want a partial import warning to stay visible …
/// While it needs to be clear, its also important to make sure its not
/// obnoxious and wont annoy the user too much if for whatever reason they
/// decide to cancel the import and work on a partially imported notebook
/// without ever intending on completing the import."*
///
/// Two requirements pulling in opposite directions, which is what makes this
/// worth a file of its own rather than a banner someone bolts on.
///
/// **Clear.** A notebook holding 152 of 332 pages with nothing on screen to
/// say so is a quiet lie: somebody finds the gaps weeks later and concludes
/// the import ate their notes. So it says so, on the notebook it is about,
/// every time that notebook is open.
///
/// **Not obnoxious.** It is one line at the top of the page, in the surface's
/// own colours rather than a warning yellow — nothing is wrong, something is
/// merely unfinished. It never steals focus, never covers anything, and takes
/// one row of height. There is no dismiss button because a dismissable notice
/// that must stay visible is a contradiction; the way to make it go away is to
/// finish the import, or to say you are not going to.
///
/// **"Not now" is a real answer.** Somebody who cancelled on purpose and is
/// happily working in a half-imported notebook can say so once and never be
/// asked again — that is what clearing the record means, and it is offered in
/// the same place as finishing.
library;

import 'package:flutter/material.dart';

import '../export/import_job.dart';
import '../l10n/l10n.dart';
import '../l10n/labels.dart';
import '../onenote/graph_auth.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

class UnfinishedImportBar extends StatelessWidget {
  const UnfinishedImportBar({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final nb = app.notebookId;
    if (nb == null) return const SizedBox.shrink();

    // **A running import says so here too, not only in the corner.**
    //
    // Reported: *"please make that import popup a bit clearer since its so
    // easy to miss at the moment and people might think nothing is
    // happening."*
    //
    // The card is bottom-left and 360px wide; somebody watching the middle of
    // a large screen for their notes to appear can miss it entirely, and what
    // they conclude is that nothing is happening. The fix is not a louder
    // card — it is putting the news where they are already looking.
    //
    // This is the same one-line strip that already says a notebook is
    // unfinished, which is the point: one place, one shape, two things it can
    // say. It steals no focus, covers nothing, and takes one row of height.
    // The card stays, because the card is where the buttons live — this says
    // WHAT is happening, the card is what you press.
    final job = ImportJob.current;
    if (job != null && !job.isFinished && job.notebookId == nb) {
      return _Running(job: job);
    }
    if (job != null && !job.isFinished) return const SizedBox.shrink();

    final u = app.unfinishedImportFor(nb);
    if (u == null) return const SizedBox.shrink();

    final s = context.surfaces;
    final left = u.pagesLeft;
    return Material(
      color: s.chrome2,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: OnoteSpace.x5, vertical: OnoteSpace.x3),
        child: Row(children: [
          Icon(Icons.cloud_download_outlined,
              size: OnoteIcon.sm, color: s.textSecondary),
          const SizedBox(width: OnoteSpace.x3),
          Expanded(
            child: Text(
              // Says what is missing and why, in that order, because the
              // first question is "is something wrong with my notes" and the
              // answer is no.
              u.stoppedByUser
                  ? 'You stopped this import with '
                      '${left > 0 ? '$left page${left == 1 ? '' : 's'}' : 'some pages'} '
                      'still to come.'
                  : 'This notebook is still arriving — '
                      '${left > 0 ? '$left page${left == 1 ? '' : 's'} to go' : 'some pages are still to come'}. '
                      'Microsoft asked Openote to slow down.',
              style: OnoteType.small.copyWith(color: s.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: OnoteSpace.x3),
          TextButton(
            onPressed: () => _finishNow(context, nb),
            child: const Text('Finish now'),
          ),
          TextButton(
            onPressed: () => app.clearUnfinishedImport(nb),
            // The honest opposite of "finish": not "dismiss", which would
            // suggest it comes back.
            child: const Text('Leave it'),
          ),
        ]),
      ),
    );
  }

  Future<void> _finishNow(BuildContext context, String nb) async {
    final auth = GraphAuth();
    await app.resumeOneNoteImport(auth: auth, nb: nb);
  }
}

/// The same strip, while an import is actually running.
///
/// Deliberately quiet: the accent is spent on the progress bar, which is the
/// part carrying information, and not on the row itself. Nothing here is
/// pressable — every action for a running import lives on the card, and two
/// places offering the same Stop is how somebody ends up pressing the wrong
/// one.
class _Running extends StatelessWidget {
  const _Running({required this.job});

  final ImportJob job;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final total = job.pagesTotal;
    final done = job.pagesDone;
    return ListenableBuilder(
      listenable: job,
      builder: (context, _) => Material(
        color: s.chrome2,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: OnoteSpace.x5, vertical: OnoteSpace.x3),
            child: Row(children: [
              const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: OnoteSpace.x3),
              Expanded(
                child: Text(
                  job.status.describe(L.of(context)),
                  style: OnoteType.small.copyWith(color: s.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (total > 0) ...[
                const SizedBox(width: OnoteSpace.x3),
                Text('$done / $total',
                    style: OnoteType.caption.copyWith(color: s.textSecondary)),
              ],
            ]),
          ),
          // A hairline, so the eye catches movement without the row shouting.
          // An indeterminate bar while the total is unknown says "working"
          // rather than "nothing yet", which is the whole complaint.
          SizedBox(
            height: 2,
            child: LinearProgressIndicator(
              value: total > 0 ? done / total : null,
              minHeight: 2,
              backgroundColor: s.chrome2,
            ),
          ),
        ]),
      ),
    );
  }
}
