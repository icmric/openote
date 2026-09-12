import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../model/inline_atom.dart';
import '../theme/onote_theme.dart';
import 'inline_table.dart';

/// **Everything an inline atom needs from the note it is sitting in.**
///
/// One object rather than a handful of loose callbacks on the controller,
/// because the read renderer needs the same set and two lists of hooks that
/// have to stay in step are two lists that will not. The host is supplied by
/// whoever knows the block — the editing session, or the read view — and
/// nothing below this line knows what a `Block` or an `AppState` is.
class InlineAtomHost {
  const InlineAtomHost({
    required this.atoms,
    required this.write,
    required this.editable,
    this.revision,
    this.onKeyboard,
    this.onExit,
    this.onOpen,
    this.takeInitialCell,
    this.onNeedWidth,
  });

  /// The atoms this block is carrying, read fresh. Never a snapshot: an atom
  /// widget is built once per id and then handed back unchanged for as long
  /// as its id is unchanged, so anything it cached at construction would be
  /// what it showed for ever.
  final Map<String, InlineAtom> Function() atoms;

  /// Save a new payload for [id]. [pushUndo] false continues the undo step
  /// the previous write opened, which is what makes a sentence typed into a
  /// cell one step rather than forty.
  final void Function(String id, Map<String, dynamic> content,
      {required bool pushUndo}) write;

  /// Whether an atom accepts typing at all. False on every read surface, and
  /// false while the note is read-only — a version-gated notebook must not be
  /// editable through a table cell when it is not editable anywhere else.
  final bool editable;

  /// Notifies when the block may have changed underneath the atom.
  final Listenable? revision;

  /// An atom took or gave up the keyboard.
  final void Function(bool holding)? onKeyboard;

  /// Give the keyboard back to the paragraph, with the caret just after the
  /// atom's own reference. Offset-free on purpose: the atom is cached and its
  /// offsets move under it, so the host looks its reference up by id.
  final void Function(String id)? onExit;

  /// Somebody clicked inside an atom that is only being read.
  final void Function(String id, int row, int col)? onOpen;

  /// The cell a click asked for, consumed once — so re-entering the block
  /// later does not jump to where the pointer was a quarter of an hour ago.
  final ({int row, int col})? Function(String id)? takeInitialCell;

  /// The atom wants more room than the box has.
  final void Function(double total)? onNeedWidth;
}

/// **One atom, drawn — the same widget wherever it is drawn.**
///
/// Called by the live editor's span builder and by the read renderer, so a
/// table cannot look one way while the caret is in the paragraph and another
/// way when it is not. That single shape-change was the defect this whole
/// piece of work exists to remove.
///
/// [alt] is the CommonMark fallback text from the reference itself, and it is
/// what is drawn when there is nothing else honest to draw.
Widget inlineAtomWidget({
  required InlineAtomHost? host,
  required String id,
  required String alt,
  required TextStyle style,
  required bool dark,
  double? maxWidth,
}) {
  final atom = host?.atoms()[id];
  if (atom == null) {
    // No payload. An older export, a reference pasted from somewhere the
    // payload could not follow, or a block still arriving from a sync. The
    // alt text is the whole point of the alt text.
    return Text(alt, style: style.copyWith(color: OnoteColors.graphite400));
  }
  if (atom.type != 'table') {
    // A type this build has never heard of — which means a NEWER build made
    // it. Not a corrupt note, and emphatically not something to overwrite.
    return _NewerVersion(
        madeIn: atom.content['madeIn'] as String?,
        style: style,
        dark: dark,
        maxWidth: maxWidth);
  }
  final h = host!;
  return InlineTable(
    binding: TableBinding(
      read: () {
        final live = h.atoms()[id];
        return TableData.from(live?.content ?? atom.content);
      },
      write: (next, {required bool pushUndo}) {
        final live = h.atoms()[id] ?? atom;
        h.write(
            id,
            {
              // Everything the payload was carrying that is not the table —
              // the version that made it, and anything a newer build put
              // there — is kept. A save that dropped a field it did not
              // understand would quietly delete the other device's work.
              ...live.content,
              ...next.toContent(),
            },
            pushUndo: pushUndo);
      },
      onNeedWidth: h.onNeedWidth,
    ),
    editable: h.editable,
    style: style,
    dark: dark,
    revision: h.revision,
    maxWidth: maxWidth,
    onKeyboard: h.onKeyboard,
    onExit: h.onExit == null ? null : () => h.onExit!(id),
    onOpen: h.onOpen == null ? null : (r, c) => h.onOpen!(id, r, c),
    initialCell: h.takeInitialCell?.call(id),
  );
}

/// **A box where the thing should be, saying what to do about it.**
///
/// The owner, on what another of their devices should show for a table this
/// build cannot draw: *"if we have the data lets draw out a box the size of
/// the table which says that the table has been created on version x, update
/// openote to view"*. This is that box, and it is drawn for any atom type
/// this build does not know — which is the same problem seen from the other
/// side, and the only side a build can actually do anything about.
///
/// It draws the box rather than nothing precisely because the payload is
/// still there and still syncing: what is missing is a way to READ it, not
/// the data. Nothing here writes, so an old build cannot damage a new one's
/// work by looking at it.
class _NewerVersion extends StatelessWidget {
  const _NewerVersion({
    required this.madeIn,
    required this.style,
    required this.dark,
    this.maxWidth,
  });

  final String? madeIn;
  final TextStyle style;
  final bool dark;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final line = madeIn == null
        ? l.atomNewerVersionUnknown
        : l.atomNewerVersion(madeIn!);
    final ink = dark ? OnoteColors.moon300 : OnoteColors.graphite500;
    return Container(
      width: maxWidth == null ? 280 : (maxWidth! < 280 ? maxWidth : 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(
            color: dark ? OnoteColors.night300 : OnoteColors.paper300),
        borderRadius: BorderRadius.circular(4),
        color: dark ? OnoteColors.night100 : OnoteColors.paper100,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(line, style: style.copyWith(color: ink)),
          Text(l.atomUpdateToView,
              style: style.copyWith(
                  color: ink, fontSize: (style.fontSize ?? 14) * 0.9)),
        ],
      ),
    );
  }
}
