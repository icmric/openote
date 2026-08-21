/// The two dialogs that stand between "add a video" and a video on the page.
///
/// Moved out of `command_bar.dart` so the Insert catalog can reach them: the
/// ribbon and the canvas's right-click menu offer the same ten things, and
/// they can only be the same ten things if there is one definition of each.
library;


import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/platform_open.dart';
import '../editor/video_block_view.dart' show formatBytes;
import '../theme/tokens.dart';

/// What the media dialog came back with: a link to embed, or "let me pick a
/// file instead".
class MediaChoice {
  const MediaChoice.link(this.url, this.name) : pickFile = false;
  const MediaChoice.file()
      : url = null,
        name = null,
        pickFile = true;
  final String? url;
  final String? name;
  final bool pickFile;
}

/// Ask for a URL and a label for a media-link card, or send the user to the
/// file picker to copy a recording in.
///
/// Both routes in one dialog because they answer the same question — "put this
/// lecture in my notes" — and the difference between them is a decision about
/// storage the user should be making with both options in front of them, not
/// a choice between two menu entries whose distinction is invisible.
///
/// A URL is validated with the same allow-list that will later be asked to
/// open it (`PlatformOpen.isOpenableUrl`), so a link that cannot be opened is
/// refused at the point of typing rather than becoming a dead card in the page.
///
/// Public, so a widget test can pump it directly: this dialog shipped broken
/// (see the actions note below) and nothing could have caught that, because a
/// private dialog three calls deep behind a file picker is a widget no test
/// ever built.
class MediaLinkDialog extends StatefulWidget {
  const MediaLinkDialog({super.key});

  @override
  State<MediaLinkDialog> createState() => _MediaLinkDialogState();
}

class _MediaLinkDialogState extends State<MediaLinkDialog> {
  final _url = TextEditingController();
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _url.text.trim();
    // A bare "youtube.com/..." is what people paste out of a browser bar.
    final candidate =
        raw.contains('://') || raw.isEmpty ? raw : 'https://$raw';
    if (!PlatformOpen.isOpenableUrl(candidate)) {
      setState(() => _error = 'That needs to be an http or https link.');
      return;
    }
    final label = _name.text.trim();
    Navigator.of(context).pop(MediaChoice.link(
      candidate,
      label.isEmpty ? (Uri.tryParse(candidate)?.host ?? candidate) : label,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Embed a video or link'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A link gets a card that opens in your browser — right for a '
              'lecture on Panopto or YouTube, which is a web page rather than '
              'a file anything here can play.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _url,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Link',
                hintText: 'https://…',
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Label (optional)',
                hintText: 'Lecture 7 — Truth Tables',
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      // The file button sits LEFT of Cancel because it is the other half of
      // the question rather than a way out of it — pushed apart by the
      // alignment, NOT by a Spacer. AlertDialog lays its actions out in an
      // OverflowBar, which is not a Flex, and a Spacer is an Expanded: its
      // ParentData contract is only satisfiable inside a Flex, so the Spacer
      // broke the dialog's build — on a release build that renders as the
      // whole dialog replaced by a grey error box, reported on Linux as "the
      // popup was taking up the whole screen and was just grey".
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.video_file_outlined, size: 17),
          label: const Text('Use a file on this computer…'),
          onPressed: () =>
              Navigator.of(context).pop(const MediaChoice.file()),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          const SizedBox(width: 8),
          FilledButton(onPressed: _submit, child: const Text('Add link')),
        ]),
      ],
    );
  }
}

/// The progress of copying a video into the notebook.
///
/// Modal and un-dismissable except by Cancel, because the copy is writing into
/// the notebook's own directory and walking away mid-write is what leaves a
/// half file behind. Cancel is real: it stops the stream, and MediaStore
/// removes what it had written.
class MediaCopyDialog extends StatelessWidget {
  const MediaCopyDialog({
    required this.name,
    required this.bytes,
    required this.progress,
    required this.onCancel,
  });

  final String name;
  final int bytes;
  final ValueListenable<double> progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        // Escape IS Cancel here. `barrierDismissible: false` is deliberate —
        // a stray click on the scrim must not abandon a half-written file —
        // but it also switches off the framework's Escape handling
        // wholesale, which left the one real way out of this dialog
        // mouse-only (phase-3 audit).
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): onCancel},
        child: Focus(
          autofocus: true,
          child: _body(context),
        ),
      );

  Widget _body(BuildContext context) => AlertDialog(
        title: const Text('Copying into the notebook'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  overflow: TextOverflow.ellipsis, style: OnoteType.uiStrong),
              const SizedBox(height: OnoteSpace.x3),
              ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (_, v, __) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: v == 0 ? null : v),
                    const SizedBox(height: OnoteSpace.x2),
                    Text('${(v * 100).round()}% of ${formatBytes(bytes)}',
                        style: OnoteType.small),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
        ],
      );
}
