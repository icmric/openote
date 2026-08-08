/// "Is this notebook backed up?", answered at a glance (style guide §7e).
///
/// **Why it needs to exist.** The status bar's sync chip answers this for the
/// notebook you have *open*, and nowhere else did. Someone with four notebooks
/// — one in Drive, one in a shared folder, two only on this laptop — had to
/// open each in turn to find out which were safe. That is the wrong shape for
/// a question whose whole value is being asked about everything at once.
///
/// **A dot, deliberately, not a word.** The notebook list already carries a
/// title, a section/page count and four action buttons per row; a "Synced to
/// OneDrive" label per row would be the widest thing in it. A dot is glanceable
/// at list scale, and §3.5 forbids colour carrying meaning alone — so the
/// tooltip always says it in words, and [SyncDot.withLabel] exists for the one
/// place (the navigator header) with room for both.
library;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import '../theme/tokens.dart';

/// How a notebook's storage reads to someone scanning a list.
enum SyncState {
  /// In a folder something else keeps in step — the notes exist elsewhere.
  synced,

  /// Not in a sync folder, but one-way mirrors are configured. Recoverable,
  /// but not live, so it is deliberately NOT the same green as [synced].
  mirrored,

  /// Only on this machine. Not an error — most notebooks start here — so this
  /// is a hollow ring rather than a red warning.
  local,
}

/// Work out the state for [notebookId] without the caller reaching into
/// `syncStatus` and re-deriving the rules differently each time.
SyncState syncStateOf(AppState app, String notebookId) {
  final s = app.syncStatus(notebookId);
  if (s.isSynced) return SyncState.synced;
  if (s.mirrors > 0) return SyncState.mirrored;
  return SyncState.local;
}

/// The sentence behind the dot. Always available, because the dot's colour is
/// never the only carrier of the meaning.
String syncStateTooltip(AppState app, String notebookId) {
  final s = app.syncStatus(notebookId);
  if (s.isSynced) {
    // `where`, never `folder!` — a git-synced notebook has no folder, and this
    // is called for every row of the notebook list.
    final where = s.where ?? 'a remote';
    final how = s.isFolderSynced
        ? 'Syncing through $where — this notebook lives in a folder your '
            'cloud keeps in step'
        // Named as a minute behind rather than as continuous. It is the
        // difference between the two mechanisms, and the moment it matters is
        // the moment someone closes a laptop mid-sentence.
        : 'Syncing to $where — pushed a minute after you stop typing, and '
            'again when you close Openote';
    return s.hasOtherDevices
        ? '$how · ${s.devices} devices have opened it'
        : how;
  }
  if (s.mirrors > 0) {
    return 'Backed up to ${s.mirrors} '
        '${s.mirrors == 1 ? 'place' : 'places'}, but not syncing — copies are '
        'made on a schedule, not as you type';
  }
  return 'On this computer only — not synced or backed up anywhere';
}

/// The status bar chip's longer, two-line tooltip.
///
/// Here rather than in `app_shell.dart` because it lived there as a private
/// method on a private widget, which meant nothing could reach it — and it was
/// the one of the three `folder!` dereferences that no amount of reading
/// caught, because no test in the suite renders the status bar. Public, taking
/// a [SyncStatus], it is coverable by anything that can build one.
String syncChipTooltip(SyncStatus s) {
  final b = StringBuffer();
  if (s.isSynced) {
    b.write(s.isFolderSynced
        ? 'Syncing through ${s.where}.\n'
        : 'Pushed to ${s.where} a minute after you stop typing, and again '
            'when you close Openote.\n');
    b.write(s.hasOtherDevices
        ? 'Edited on ${s.devices} devices — changes arrive automatically.'
        : 'Open this notebook on another device to sync it.');
  } else {
    b.write('Only on this computer.\n'
        'Click to put it in a folder your cloud already syncs.');
  }
  if (s.mirrors > 0) {
    b.write('\n${s.mirrors} backup destination${s.mirrors == 1 ? '' : 's'}.');
  }
  return b.toString();
}

/// A 8px status dot for one notebook.
class SyncDot extends StatelessWidget {
  const SyncDot({super.key, required this.app, required this.notebookId});

  final AppState app;
  final String notebookId;

  static const double size = 8;

  @override
  Widget build(BuildContext context) {
    final state = syncStateOf(app, notebookId);
    return Tooltip(
      message: syncStateTooltip(app, notebookId),
      child: SizedBox(
        // A fixed box the same size for every state, so a row's layout does
        // not shift by a pixel when a notebook starts syncing.
        width: size + 4,
        height: size + 4,
        child: Center(child: _Dot(state: state, surfaces: context.surfaces)),
      ),
    );
  }
}

/// The dot plus its word, for surfaces with the room. Used by the navigator
/// header, where there is exactly one notebook to describe and the answer is
/// worth spelling out.
class SyncDotWithLabel extends StatelessWidget {
  const SyncDotWithLabel(
      {super.key, required this.app, required this.notebookId});

  final AppState app;
  final String notebookId;

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final state = syncStateOf(app, notebookId);
    return Tooltip(
      message: syncStateTooltip(app, notebookId),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _Dot(state: state, surfaces: s),
        const SizedBox(width: OnoteSpace.x2),
        // `Flexible`, because a folder name is user data of unbounded length
        // and this sits in the navigator, whose width the user drags. Without
        // it, "Syncing through My Very Long Folder Name" overflows the panel
        // — `TextOverflow.ellipsis` alone cannot help a Text that was never
        // given a bound to ellipsise against.
        Flexible(
          child: Text(
            switch (state) {
              SyncState.synced =>
                app.syncStatus(notebookId).where ?? 'Syncing',
              SyncState.mirrored => 'Backed up',
              SyncState.local => 'This computer only',
            },
            style: OnoteType.caption.copyWith(color: s.textSecondary),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ]),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.state, required this.surfaces});

  final SyncState state;
  final OnoteSurfaces surfaces;

  @override
  Widget build(BuildContext context) => Container(
        width: SyncDot.size,
        height: SyncDot.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Filled for the two states that mean "a copy exists somewhere
          // else"; hollow for local-only. Shape carries the meaning as well as
          // colour, which is the §3.5 rule and also what makes it readable at
          // 8px on a bad monitor.
          color: switch (state) {
            SyncState.synced => OnoteColors.success,
            SyncState.mirrored => OnoteColors.brass500,
            SyncState.local => Colors.transparent,
          },
          border: state == SyncState.local
              ? Border.all(color: surfaces.textDisabled, width: 1.4)
              : null,
        ),
      );
}
