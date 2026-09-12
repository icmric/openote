import 'package:flutter/material.dart';

import '../model/inline_atom.dart';
import '../model/models.dart';
import '../state/app_state.dart';
import 'inline_table.dart';

export 'inline_table.dart' show kTableColumnCap, kTableColumnMin;

/// A table in a box of its own (MEDIA-3). `content: { cells: [[String,…],…] }`.
///
/// **Thirty lines, because the table itself is [InlineTable]** — the same
/// widget a table inside a paragraph is drawn with. This used to be five
/// hundred lines of grid, column arithmetic, focus traversal and a row of
/// add/remove buttons, and putting a table into a sentence would have meant a
/// second copy of every one of them: two answers to what Tab does, two
/// answers to how wide a column is, two menus drifting apart.
///
/// What this file still owns is the BINDING — where a standalone table's data
/// lives (`content.cells`, straight off the block) and what widening it means
/// (the box grows). An inline table binds to an atom's payload instead, and
/// that is the whole of the difference between them.
///
/// The button row is gone, and the right-click menu replaced it: the owner,
/// *"we can remove the menu that was persistantly there on the current one in
/// favour of a right click menu, allowing me to insert a row/colum above/below
/// the cell i clicked in"*. Those buttons could only ever add and remove at
/// the END, which is why inserting a row in the middle meant retyping
/// everything below it.
class TableBlockView extends StatelessWidget {
  const TableBlockView({super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  /// The block as the page holds it NOW.
  ///
  /// An undo or a sync pull rebuilds the page's blocks from JSON, and a
  /// widget that kept writing to the object it was constructed with would be
  /// writing to a detached copy nobody will ever read.
  Block get _live => app.blockById(block.id) ?? block;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(builder: (context, cons) {
      return InlineTable(
        binding: TableBinding(
          read: () => TableData.from(_live.content),
          write: (next, {required bool pushUndo}) {
            // Regression this guards: table writes used to mark the page
            // dirty without pushing an undo step, so Ctrl+Z jumped straight
            // past every table edit to whatever preceded the table.
            if (pushUndo) app.pushUndo();
            final b = _live;
            b.content['cells'] = next.cells;
            if (next.colWidths.isEmpty) {
              b.content.remove('colWidths');
            } else {
              b.content['colWidths'] = next.colWidths;
            }
            b.updatedAt = nowMs();
            app.markDirty();
          },
          // **The box grows to hold the table.** Reported: *"if the table
          // overflows the box, it doesnt seem to auto expand the box with
          // it."* Quite so — the block carries its own width and nothing was
          // moving it, so a column dragged past the edge simply spilled out.
          //
          // It only ever GROWS: a box somebody widened by hand must not snap
          // back because a column was narrowed afterwards.
          onNeedWidth: (total) {
            final b = _live;
            final needed = total + _kBlockContentInset * 2;
            if (needed <= b.w) return;
            b.w = needed;
            app.markDirty();
          },
        ),
        editable: app.editingBlockId == block.id,
        style: const TextStyle(fontSize: 13),
        dark: dark,
        revision: app,
        maxWidth: cons.maxWidth.isFinite ? cons.maxWidth : null,
      );
    });
  }
}

/// The padding a block reserves around its content, per side — `_kChromePad`
/// in `block_view.dart`, which is private to it. Named here so the arithmetic
/// that makes a table fit its box says what the number is rather than
/// carrying an 8 nobody can trace.
const double _kBlockContentInset = 8;
