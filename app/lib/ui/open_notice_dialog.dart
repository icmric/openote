/// What Openote says when a notebook it was handed could not simply be opened.
///
/// Reached from two places, both outside the app's own UI: a notebook named on
/// the command line at launch, and a `.onote` double-clicked in the file
/// manager while Openote is already running.
///
/// **The happy path never comes here.** A notebook that opened is on the
/// screen, which is the only confirmation anybody needs; a dialog saying
/// "opened Physics" over the top of Physics is noise. This shows for the four
/// cases where the app did something other than what the user asked, and it
/// says which in one sentence.
///
/// Jargon rule (PLANNING, "no jargon"): the sentence has no path, no
/// exception and no file format in it. The path and the raw error live under
/// **Details (advanced)**, folded away, for the one person in a hundred who
/// wants to know which file the app was actually looking at.
library;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'onote_dialog.dart';

Future<void> showOpenNotebookNotice(
        BuildContext context, OpenNotebookResult result) =>
    showOnoteDialog<void>(
      context: context,
      builder: (_) => _OpenNotebookNotice(result: result),
    );

class _OpenNotebookNotice extends StatelessWidget {
  const _OpenNotebookNotice({required this.result});

  final OpenNotebookResult result;

  /// A copy that worked is information; the rest are failures. The icon is the
  /// only place that distinction is drawn, because the sentence already says
  /// which one it is.
  bool get _isFailure => !result.ok;

  String get _title => switch (result.outcome) {
        OpenNotebookOutcome.notFound => "That notebook isn't there any more",
        OpenNotebookOutcome.notANotebook => "That isn't a notebook",
        OpenNotebookOutcome.copiedIn => 'Added to your notebooks',
        _ => "Openote couldn't open that",
      };

  @override
  Widget build(BuildContext context) {
    final details = result.details;
    return AlertDialog(
      icon: Icon(
          _isFailure ? Icons.error_outline : Icons.library_add_check_outlined,
          color: _isFailure ? OnoteColors.danger : null),
      title: Text(_title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result.message),
            if (_isFailure) ...[
              const SizedBox(height: 10),
              const Text(
                'Everything else in Openote is untouched — your other '
                'notebooks are exactly as you left them.',
                style: TextStyle(fontSize: 12, color: OnoteColors.graphite400),
              ),
            ],
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
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(context), child: const Text('OK')),
      ],
    );
  }
}
