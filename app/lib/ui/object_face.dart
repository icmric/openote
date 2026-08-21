/// What the object row is about, right now.
///
/// A pure function over [AppState], deliberately: it decides a whole band of
/// chrome, and a decision that big should be checkable without a widget tree
/// standing up around it.
library;

import '../model/models.dart';
import '../state/app_state.dart';

/// The faces the object row can wear.
///
/// **The bar for earning one** — write this down and hold to it, because it is
/// what stops the row becoming the next mess:
///
/// > A thing gets a face only when it has **six or more controls that must be
/// > reachable while the caret is still inside it**.
///
/// An equation qualifies: two hundred and thirty symbols behind eight doors,
/// and a student in the middle of writing one cannot go and find them. A
/// graph will qualify. A table, a code block, a picture, a board, a file and
/// a page window do **not** — their handful of controls belong on the block
/// or in its right-click menu, which is where they already are. A row that
/// flipped every time you clicked something would be the jitter this design
/// exists to remove.
///
/// Text gets no face either: Home already carries the formatting, on the tab
/// the student chose.
enum ObjectFace {
  /// Nothing is being written. The thing you are touching is the page.
  page,

  /// An equation — in a box of its own or inside a sentence, which this
  /// deliberately cannot tell apart.
  equation,
}

/// Which face belongs to what the app is doing.
///
/// **The order is load-bearing and both halves are copied from code that
/// already works.** Do not reorder it.
ObjectFace objectFaceOf(AppState app) {
  final id = app.editingBlockId;
  if (id != null) {
    for (final b in app.blocks) {
      // `return` on a MATCH, not on a miss. Written the other way round it
      // answered "no" for every INLINE equation and never reached the line
      // below — the block being edited there is the paragraph, which is a
      // text block — so the whole palette was dead code in the case it was
      // most needed for.
      if (b.id == id && b.type == BlockType.math) return ObjectFace.equation;
    }
  }
  // An equation inside a sentence: the block being edited is TEXT, so only
  // the open editor itself can say. One frame late by design — it registers
  // from `EquationEditor.build`.
  if (app.activeMath != null) return ObjectFace.equation;
  return ObjectFace.page;
}
