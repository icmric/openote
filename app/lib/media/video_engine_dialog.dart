/// The one click that fetches the video player.
///
/// **The sentence this dialog exists to make impossible.** A student opens a
/// notebook on a train, reaches the page with last week's lecture on it, and
/// concludes the recording is gone. It is not gone — it is sitting in
/// `<notebook>.onotebook/media/`, exactly where it was, and the only thing
/// missing is the code that decodes it. So the first line of this dialog says
/// where the video is, before it says anything about a download, and the
/// offline message says the same thing again.
///
/// Jargon rule (PLANNING, "no jargon"): nothing the student reads names
/// libmpv, ANGLE, a codec, a DLL or a URL. Those live under **Details
/// (advanced)**, folded away, the same shape as `open_notice_dialog.dart` and
/// `save_problem_dialog.dart`.
library;

import 'package:flutter/material.dart';

import '../theme/onote_theme.dart';
import '../ui/onote_dialog.dart';
import 'video_engine.dart';
import 'video_playback.dart';

/// Offer the download, and do it if the student says yes. Returns true when
/// the engine is installed and loaded by the time it closes.
Future<bool> showGetVideoPlayer(BuildContext context) async =>
    await showOnoteDialog<bool>(
      context: context,
      builder: (_) => const _GetVideoPlayerDialog(),
    ) ??
    false;

class _GetVideoPlayerDialog extends StatefulWidget {
  const _GetVideoPlayerDialog();

  @override
  State<_GetVideoPlayerDialog> createState() => _GetVideoPlayerDialogState();
}

class _GetVideoPlayerDialogState extends State<_GetVideoPlayerDialog> {
  double _progress = 0;
  bool _running = false;
  String _step = '';
  EngineInstallFailure? _failed;

  static String get _size =>
      '${(VideoEngine.installedBytes / 1024 / 1024).round()} MB';

  Future<void> _get() async {
    setState(() {
      _running = true;
      _failed = null;
      _progress = 0;
      _step = 'Starting';
    });
    try {
      await VideoEngine.install(
        fetch: VideoEngine.networkFetch,
        onProgress: (f, what) {
          if (!mounted) return;
          setState(() {
            _progress = f;
            _step = what;
          });
        },
      );
      await VideoPlayback.reprobe();
      if (mounted) Navigator.pop(context, VideoPlayback.available);
    } on EngineInstallFailure catch (e) {
      if (mounted) {
        setState(() {
          _running = false;
          _failed = e;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final failed = _failed;
    return AlertDialog(
      icon: Icon(failed == null ? Icons.play_circle_outline : Icons.error_outline,
          color: failed == null ? null : OnoteColors.danger),
      title: Text(failed == null
          ? 'Play videos inside Openote'
          : 'That did not download'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(failed?.message ??
                'Your video is already saved on this computer, inside this '
                    'notebook. To show it here in the page rather than in '
                    'another window, Openote needs its video player — a '
                    'one-off download of about $_size that then works for '
                    'every video, on every notebook, for good.'),
            const SizedBox(height: 10),
            const Text(
              'You can skip this. "Open in your usual player" and "Save a '
              'copy…" work either way, and nothing about your video changes.',
              style: TextStyle(fontSize: 12, color: OnoteColors.graphite400),
            ),
            if (_running) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                  value: _progress <= 0 ? null : _progress),
              const SizedBox(height: 6),
              Text(_step, style: const TextStyle(fontSize: 12)),
            ],
            if (failed != null) ...[
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
                      failed.details,
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
        TextButton(
          onPressed:
              _running ? null : () => Navigator.pop(context, false),
          child: Text(failed == null ? 'Not now' : 'Close'),
        ),
        FilledButton(
          onPressed: _running ? null : _get,
          child: Text(failed == null ? 'Get it' : 'Try again'),
        ),
      ],
    );
  }
}
