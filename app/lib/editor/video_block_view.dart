import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/platform_open.dart';
import '../media/video_playback.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import '../store/media_store.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';
import '../ui/onote_dialog.dart';

/// A video or recording kept in the notebook and played in the page.
///
/// content: `{ kind: 'video', media: '<name>', name, mime, size }` — `media`
/// is a filename inside `<notebook>.onotebook/media/` (see store/media_store.dart
/// for why a lecture does not go in the container).
///
/// **The player is not built until Play is pressed.** Every live player is an
/// mpv instance holding a decoder, a GPU texture and a file handle; a page with
/// six recordings on it would open six of them just by being looked at. So the
/// resting state is a poster card that costs nothing, and pressing Stop takes
/// it all back down again. This also means the common case — a page you
/// scrolled past — never touches libmpv at all.
class VideoBlockView extends StatefulWidget {
  const VideoBlockView({super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  @override
  State<VideoBlockView> createState() => _VideoBlockViewState();
}

class _VideoBlockViewState extends State<VideoBlockView> {
  Player? _player;
  VideoController? _controller;
  Object? _failure;

  String get _name =>
      (widget.block.content['name'] as String?)?.trim().isNotEmpty == true
          ? (widget.block.content['name'] as String).trim()
          : 'Recording';

  int get _size => (widget.block.content['size'] as num?)?.toInt() ?? 0;

  /// The file itself, or null when it is not here: a notebook copied without
  /// its `.onotebook`, a sync still bringing the bytes across, or a reference
  /// that does not name something we wrote.
  File? get _file {
    final name = widget.block.content['media'] as String?;
    if (name == null) return null;
    try {
      return MediaStore.resolve(widget.app.currentNotebook, name);
    } catch (_) {
      return null; // no notebook open
    }
  }

  Future<void> _play() async {
    final file = _file;
    if (file == null) return;
    try {
      final player = Player();
      final controller = VideoController(player);
      setState(() {
        _player = player;
        _controller = controller;
        _failure = null;
      });
      await player.open(Media(file.path));
    } catch (e) {
      await _stop();
      if (mounted) setState(() => _failure = e);
    }
  }

  Future<void> _stop() async {
    final player = _player;
    setState(() {
      _player = null;
      _controller = null;
    });
    await player?.dispose();
  }

  @override
  void dispose() {
    // Not awaited: dispose() cannot be async, and mpv tears itself down.
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null) return _playing(controller);
    return _poster(context);
  }

  Widget _playing(VideoController controller) => Stack(
        children: [
          Positioned.fill(
            child: Video(controller: controller),
          ),
          // Stop, not pause: this is what gives the decoder and the file handle
          // back. Placed clear of the controls at the bottom.
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.white),
                visualDensity: VisualDensity.compact,
                tooltip: 'Close the player',
                onPressed: _stop,
              ),
            ),
          ),
        ],
      );

  /// The resting state: video-shaped, so the page reads as having a recording
  /// on it rather than a row of buttons, and cheap, because nothing here has
  /// touched a decoder.
  Widget _poster(BuildContext context) {
    final file = _file;
    final playable = file != null && VideoPlayback.available;
    return Container(
      decoration: BoxDecoration(
        color: OnoteColors.graphite900,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Center(
            child: playable
                ? IconButton(
                    icon: const Icon(Icons.play_circle_fill,
                        size: 52, color: Colors.white),
                    tooltip: 'Play here',
                    onPressed: _play,
                  )
                : Icon(
                    file == null
                        ? Icons.videocam_off_outlined
                        : Icons.movie_outlined,
                    size: 40,
                    color: OnoteColors.graphite500),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black38,
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.white)),
                        Text(_subtitle(file),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                            style: const TextStyle(
                                fontSize: 11, color: OnoteColors.graphite400)),
                      ],
                    ),
                  ),
                  if (file != null) ...[
                    IconButton(
                      icon: const Icon(Icons.open_in_new,
                          size: 16, color: OnoteColors.graphite400),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Open in your usual player',
                      onPressed: () => _openExternally(context, file),
                    ),
                    IconButton(
                      icon: const Icon(Icons.download_outlined,
                          size: 16, color: OnoteColors.graphite400),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Save a copy…',
                      onPressed: () => _saveCopy(context, file),
                    ),
                    if (!VideoPlayback.available)
                      IconButton(
                        icon: const Icon(Icons.help_outline,
                            size: 16, color: OnoteColors.graphite400),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Why can this not play here?',
                        onPressed: () => _explainMissingLibrary(context),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _subtitle(File? file) {
    if (file == null) {
      return widget.block.content['media'] == null
          ? 'This card has no file'
          : 'The file is not in this copy of the notebook';
    }
    if (_failure != null) return 'That would not play: $_failure';
    if (!VideoPlayback.available) {
      return '${formatBytes(_size)} · plays in your usual player';
    }
    return formatBytes(_size);
  }

  Future<void> _openExternally(BuildContext context, File file) async {
    final ok = await PlatformOpen.file(file.path);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No app on this computer opens that kind of file.')));
    }
  }

  Future<void> _saveCopy(BuildContext context, File file) async {
    final loc = await getSaveLocation(suggestedName: _name);
    if (loc == null) return;
    // Streamed, not readAsBytes: this is the one file type where "read it all
    // into memory first" is a gigabyte.
    await file.openRead().pipe(File(loc.path).openWrite());
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved to ${loc.path}')));
    }
  }

  void _explainMissingLibrary(BuildContext context) => showOnoteDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Playing here needs one more package'),
          content: SizedBox(
            width: 460,
            child: Text(VideoPlayback.missingLibraryAdvice,
                style: OnoteType.ui),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close')),
          ],
        ),
      );
}

String formatBytes(int b) => b < 1024
    ? '$b B'
    : b < 1024 * 1024
        ? '${(b / 1024).toStringAsFixed(1)} KB'
        : b < 1024 * 1024 * 1024
            ? '${(b / 1024 / 1024).toStringAsFixed(1)} MB'
            : '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
