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
    // Never while an import is actually running: the progress card is already
    // saying a better version of this, and two of them is the noise the owner
    // was worried about.
    final job = ImportJob.current;
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
