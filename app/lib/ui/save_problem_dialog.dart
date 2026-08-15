/// What Openote says when something it owed the disk did not get written.
///
/// Reached from one place — the status bar's save chip, which is clickable
/// exactly when there is a problem to explain. The chip has room for four
/// words; this has room for the rest.
///
/// Jargon rule (PLANNING, "no jargon"): the sentences name no file, no path,
/// no exception and no format version. A year-10 student has to be able to read
/// what happened and what to do about it. The raw error lives under **Details
/// (advanced)**, folded away, for a bug report — the same split
/// `showOpenNotebookNotice` makes, deliberately, so the two failure dialogs in
/// the app behave identically.
library;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'onote_dialog.dart';

Future<void> showSaveProblemDialog(BuildContext context, SaveProblem problem) =>
    showOnoteDialog<void>(
      context: context,
      builder: (_) => _SaveProblemDialog(problem: problem),
    );

class _SaveProblemDialog extends StatelessWidget {
  const _SaveProblemDialog({required this.problem});

  final SaveProblem problem;

  @override
  Widget build(BuildContext context) {
    final details = problem.details;
    return AlertDialog(
      icon: const Icon(Icons.error_outline, color: OnoteColors.danger),
      title: Text(problem.short),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(problem.message),
              if (details != null) ...[
                const SizedBox(height: 4),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  shape: const Border(),
                  title: const Text('Details (advanced)',
                      style: TextStyle(fontSize: 12.5)),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        details,
                        style: const TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontFamilyFallback: onoteFontFallback,
                            fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(context), child: const Text('OK')),
      ],
    );
  }
}
