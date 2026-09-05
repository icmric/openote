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
