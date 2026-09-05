/// The import's face while it runs in the background (v0.9 §1).
///
/// A floating card, bottom-LEFT — the alert popup owns bottom-right, and an
/// import progress card colliding with a lecture reminder would hide exactly
/// the surface whose job is interrupting. Follows the §7f-2 rules for things
/// that float over the page: it never pushes layout, never auto-dismisses
/// while running, and every state offers its action — Cancel while working,
/// **Open notebook** when done, Dismiss on failure.
///
/// Deliberately NOT a modal. The entire point of the background import is
/// that a first-run user picks their `.onepkg` and then explores the app —
/// finishes onboarding, pokes at the starter notebook — while five years of
/// notes stream in behind them. A modal would reintroduce the wait this
/// removed; a card in the corner says "working on it" without charging rent.
library;

import 'package:flutter/material.dart';

import '../export/import_job.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';

class ImportProgressCard extends StatelessWidget {
  const ImportProgressCard({super.key, required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    final job = ImportJob.current;
    if (job == null) return const SizedBox.shrink();
    // **A first import is a different situation.** Every later one happens
    // beside notebooks that already exist, so a card in the corner reads as
    // "something is going on over there". A first one happens in front of an
    // empty notebook with nothing else on screen, and the same card reads as
    // "it did nothing". The panel below sits where the person is looking.
    if (job.isFirstNotebook && !job.isFinished) {
      return Positioned.fill(
        child: IgnorePointer(
          // Only the panel takes clicks — the rest of the canvas stays live,
          // which is the whole point of importing in the background.
          ignoring: false,
          child: Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ListenableBuilder(
                listenable: job,
                builder: (context, _) => _FirstImportPanel(job: job),
              ),
            ),
          ),
        ),
      );
    }
    return Positioned(
      left: OnoteSpace.x6,
      bottom: OnoteSize.statusBar + OnoteSpace.x4,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: ListenableBuilder(
          listenable: job,
          builder: (context, _) => _Card(job: job),
        ),
      ),
    );
  }
}

/// What a first import looks like: a panel in the middle of the empty
/// notebook it is filling.
///
/// Reported: *"as it creates a blank notebook its easy to think that its just
/// doing nothing/it failed"*. Three things it has to say, in this order —
/// that something IS happening, how far along it is, and that the person does
/// not have to sit and watch.
///
/// It is not a modal. It takes no keyboard focus, dims nothing, and blocks
/// nothing but the rectangle it occupies; a first-run user can close the
/// welcome flow, poke at the sidebar and start reading the pages that have
/// already landed. Making it a modal would put back the wait the background
/// import exists to remove.
class _FirstImportPanel extends StatelessWidget {
  const _FirstImportPanel({required this.job});

  final ImportJob job;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final scheme = Theme.of(context).colorScheme;
    final total = job.pagesTotal;
    final done = job.pagesDone;

    return Material(
      color: s.raised,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: .32),
      borderRadius: OnoteRadius.lgAll,
      child: Container(
        padding: const EdgeInsets.all(OnoteSpace.x7),
        decoration: BoxDecoration(
          borderRadius: OnoteRadius.lgAll,
          border: Border.all(color: s.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              const SizedBox(
                  width: OnoteIcon.md,
                  height: OnoteIcon.md,
                  child: CircularProgressIndicator(strokeWidth: 2.6)),
              const SizedBox(width: OnoteSpace.x4),
              Expanded(
                child: Text('Bringing your notes over',
                    style: OnoteType.title.copyWith(color: s.textPrimary)),
              ),
            ]),
            const SizedBox(height: OnoteSpace.x4),
            Text(job.message,
                style: OnoteType.ui.copyWith(color: s.textSecondary),
                maxLines: 3),
            if (total > 0) ...[
              const SizedBox(height: OnoteSpace.x5),
              ClipRRect(
                borderRadius: OnoteRadius.smAll,
                child: LinearProgressIndicator(
                  value: done / total,
                  minHeight: 7,
                  backgroundColor: s.chrome2,
                ),
              ),
              const SizedBox(height: OnoteSpace.x3),
              Text('$done of $total pages',
                  style: OnoteType.small.copyWith(color: s.textSecondary)),
            ],
            const SizedBox(height: OnoteSpace.x5),
            // The sentence that stops somebody sitting and watching a bar.
            // The notebook is empty ONLY because nothing has landed yet, and
            // saying so is the difference between waiting and getting on.
            Container(
              padding: const EdgeInsets.all(OnoteSpace.x4),
              decoration: BoxDecoration(
                color: s.chrome2,
                borderRadius: OnoteRadius.mdAll,
              ),
              child: Row(children: [
                Icon(Icons.info_outline,
                    size: OnoteIcon.sm, color: s.textSecondary),
                const SizedBox(width: OnoteSpace.x3),
                Expanded(
                  child: Text(
                      'Your notebook is empty until the first pages arrive. '
                      'They show up in the sidebar as they come in, and you '
                      'can read and edit them straight away — there is no '
                      'need to wait here.',
                      style:
                          OnoteType.small.copyWith(color: s.textSecondary)),
                ),
              ]),
            ),
            const SizedBox(height: OnoteSpace.x5),
            // A Wrap rather than a Row: these are two full sentences of
            // button, and a narrow window or a larger text size has them
            // overflow rather than stack. Caught by the test at 800px, which
            // is a perfectly ordinary window.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: OnoteSpace.x2,
              runSpacing: OnoteSpace.x2,
              children: [
                if (job.isStopping)
                  TextButton(
                      onPressed: job.dismiss, child: const Text('Hide this'))
                else ...[
                  TextButton(
                      onPressed: job.cancel, child: const Text('Stop import')),
                  FilledButton.tonal(
                    onPressed: job.dismiss,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: scheme.primary,
                    ),
                    // Keeps importing; only stops explaining. Somebody who has
                    // read this once should not have to read it for the next
                    // three minutes.
                    child: const Text('Keep importing, hide this'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.job});

  final ImportJob job;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final scheme = Theme.of(context).colorScheme;
    final running = !job.isFinished;
    final failed = job.state == ImportJobState.failed;

    return Material(
      color: s.raised,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: .28),
      borderRadius: OnoteRadius.lgAll,
      child: Container(
        padding: const EdgeInsets.all(OnoteSpace.x5),
        decoration: BoxDecoration(
          borderRadius: OnoteRadius.lgAll,
          border: Border.all(color: s.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              if (running)
                const SizedBox(
                    width: OnoteIcon.md,
                    height: OnoteIcon.md,
                    child: CircularProgressIndicator(strokeWidth: 2.4))
              else
                Icon(
                    failed
                        ? Icons.error_outline
                        : job.state == ImportJobState.cancelled
                            ? Icons.block
                            : Icons.check_circle_outline,
                    size: OnoteIcon.md,
                    color: failed ? OnoteColors.danger : OnoteColors.success),
              const SizedBox(width: OnoteSpace.x4),
              Expanded(
                child: Text(
                  running
                      ? 'Importing ${job.fileName}'
                      : failed
                          ? 'Import failed'
                          : job.state == ImportJobState.cancelled
                              ? 'Import cancelled'
                              : 'Notebook ready',
                  style: OnoteType.uiStrong.copyWith(color: s.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
            const SizedBox(height: OnoteSpace.x3),
            Text(job.message,
                style: OnoteType.small.copyWith(color: s.textSecondary),
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
            if (running && job.pagesTotal > 0) ...[
              const SizedBox(height: OnoteSpace.x4),
              ClipRRect(
                borderRadius: OnoteRadius.smAll,
                child: LinearProgressIndicator(
                  value: job.pagesDone / job.pagesTotal,
                  minHeight: 5,
                  backgroundColor: s.chrome2,
                ),
              ),
              const SizedBox(height: OnoteSpace.x2),
              Text('${job.pagesDone} of ${job.pagesTotal} pages',
                  style: OnoteType.caption.copyWith(color: s.textSecondary)),
            ],
            const SizedBox(height: OnoteSpace.x3),
            Row(children: [
              // While the parse phase runs there is no page count yet — the
              // line above the buttons already says what is happening, and
              // this row keeps the one escape hatch visible throughout.
              const Spacer(),
              if (running && job.isStopping)
                // **Always a way out.** A user pressed Cancel, watched it say
                // "Stopping…", and then had nothing else to press — the card
                // sat there for good. Stopping is prompt now, but a card with
                // no escape is how a bug like that becomes unrecoverable, so
                // there is always a second press available.
                TextButton(
                  onPressed: job.dismiss,
                  child: const Text('Hide this'),
                )
              else if (running)
                TextButton(
                  onPressed: job.cancel,
                  child: const Text('Cancel'),
                )
              else ...[
                TextButton(
                  onPressed: job.dismiss,
                  child: const Text('Dismiss'),
                ),
                if (job.state == ImportJobState.done) ...[
                  const SizedBox(width: OnoteSpace.x2),
                  FilledButton(
                    onPressed: job.open,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: scheme.primary,
                    ),
                    child: const Text('Open notebook'),
                  ),
                ],
              ],
            ]),
          ],
        ),
      ),
    );
  }
}
