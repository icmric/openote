import '../model/inline_atom.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import 'inline_atom_view.dart';

/// **The bridge between an inline atom and the note it lives in.**
///
/// `InlineAtomHost` deliberately knows nothing about `Block` or `AppState`, so
/// that the widgets below it can be built and tested with no app at all. This
/// is the one file that joins the two, and both the read view and the editing
/// session build their host through it — a second copy would be a second
/// answer to what saving a cell means.
///
/// **Nothing here captures a `Block`.** An undo or a sync pull rebuilds the
/// page's blocks from JSON, and an atom widget outlives that: it is
/// constructed once per id and handed back unchanged for as long as its id is
/// unchanged. A captured block would quietly become a detached object that
/// accepts writes nobody will ever see again.
InlineAtomHost blockAtomHost(
  AppState app,
  String blockId, {
  required bool editable,
  void Function(bool holding)? onKeyboard,
  void Function(String id)? onExit,
  void Function(String id, int row, int col)? onOpen,
  void Function(double total)? onNeedWidth,
}) =>
    InlineAtomHost(
      atoms: () {
        final b = app.blockById(blockId);
        return b == null ? const {} : InlineAtom.allIn(b.content);
      },
      write: (id, content, {required bool pushUndo}) {
        final b = app.blockById(blockId);
        if (b == null) return;
        if (pushUndo) app.pushUndo();
        final was = InlineAtom.allIn(b.content)[id];
        InlineAtom.putIn(
            b.content,
            InlineAtom(
                id: id, type: was?.type ?? 'table', content: content));
        b.updatedAt = nowMs();
        app.markDirty();
      },
      editable: editable,
      // The app itself: an undo, a sync pull or the same note open in a
      // second view all announce themselves this way, and an atom that did
      // not listen would show yesterday's table until its text happened to
      // move.
      revision: app,
      onKeyboard: onKeyboard,
      onExit: onExit,
      onOpen: onOpen,
      onNeedWidth: onNeedWidth,
      takeInitialCell: (id) => app.takePendingAtomCell(blockId, id),
    );

/// Keep a block's payloads and its references in step after the text changed.
///
/// Returns true when the block's content was altered, which the caller must
/// then save. See [reconcileAtoms]: deleting a reference drops its payload
/// (and remembers it), and a reference that arrives without one — a paste —
/// gets it back.
bool reconcileBlockAtoms(AppState app, String blockId, String text) {
  final b = app.blockById(blockId);
  if (b == null) return false;
  // The overwhelming majority of blocks have no atoms and never will. One
  // substring test keeps this off the per-keystroke path for all of them.
  if (!text.contains(InlineAtom.scheme) && !b.content.containsKey('atoms')) {
    return false;
  }
  return reconcileAtoms(b.content, text,
      remember: app.rememberAtom, recall: app.recallAtom);
}

/// **A host for a block being looked at rather than edited.**
///
/// A window onto another page (`portal_view.dart`) draws blocks that are not
/// on the open page at all, so there is no id to look up and nothing this
/// view is allowed to change: every callback on a window is a read. The
/// table inside is drawn, and it is inert.
InlineAtomHost readingAtomHost(Block block) => InlineAtomHost(
      atoms: () => InlineAtom.allIn(block.content),
      write: (_, __, {required bool pushUndo}) {},
      editable: false,
    );
