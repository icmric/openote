import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/models.dart';
import '../state/app_state.dart';
import '../theme/onote_theme.dart';
import 'wrap_selection.dart';

/// A trello-style task board on the page (PLANNING.md: "having the ability
/// to have a trello like task board would be incredibly helpful").
///
/// content: `{'columns': [{'title': 'To do', 'cards': ['…', …]}, …]}`
///
/// Deliberately a BLOCK, not a page mode: a board block stretched wide on an
/// empty page IS a board page, while a board beside lecture notes is a thing
/// a page mode could never give. Cards are plain strings — the unit of a
/// board is a sentence, and anything richer belongs on a page a card can
/// link to. Every mutation goes through the ordinary undo/save/sync path,
/// so Ctrl+Z, autosave and the op log all treat a board edit like any other
/// edit.
class BoardBlockView extends StatefulWidget {
  const BoardBlockView({super.key, required this.block, required this.app});
  final Block block;
  final AppState app;

  /// What a new board starts as.
  static Map<String, dynamic> starterContent() => {
        'columns': [
          {'title': 'To do', 'cards': <String>[]},
          {'title': 'Doing', 'cards': <String>[]},
          {'title': 'Done', 'cards': <String>[]},
        ],
      };

  @override
  State<BoardBlockView> createState() => _BoardBlockViewState();
}

/// A card's address while being dragged.
typedef _CardRef = ({int col, int card});

class _BoardBlockViewState extends State<BoardBlockView> {
  Block get b => widget.block;
  AppState get app => widget.app;

  /// Which card (or column title, or "new card in column N") owns the inline
  /// editor right now. One at a time, like everything else in the app.
  _CardRef? _editingCard;
  int? _editingTitle;
  int? _addingTo;
  final _editCtrl = TextEditingController();

  // ── Keyboard (v0.16 phase 4) ────────────────────────────────────────────
  //
  // The board was mouse-only: cards moved by `Draggable`/`DragTarget` and
  // nothing else, so a student who cannot use a mouse could read a board and
  // change nothing on it. Enter on the selected block steps IN, arrows walk
  // the cards, Ctrl+arrows carry the card with you, Enter edits, Delete
  // removes, and Escape (the shell's ladder) steps back out.
  //
  // Handled on the board's own focus node rather than in `Shortcuts`,
  // because a focused node's handler runs before ANY ancestor's: the canvas
  // binds these same arrows and Ctrl+arrows, and while the board holds focus
  // the canvas's actions report disabled, so neither shadows the other.

  final FocusNode _keys = FocusNode(debugLabel: 'board');

  /// Where the keyboard is: (column, row). A row equal to the column's card
  /// count is the "Add a card" line at its foot — so adding is an ordinary
  /// stop on the walk instead of a chord nobody would guess.
  _CardRef _cursor = (col: 0, card: 0);

  /// Committing on blur is what makes Escape safe. Escape is caught by the
  /// shell (it means "leave this block"), so without this, typing a card and
  /// pressing Escape threw the text away without saying so.
  late final FocusNode _editFocus = FocusNode(debugLabel: 'board-card-text')
    ..addListener(() {
      // `mounted` first: disposing a focus node detaches it, which notifies,
      // and committing then would setState on a dead State.
      if (mounted && !_editFocus.hasFocus) _commitEditor();
    });

  @override
  void initState() {
    super.initState();
    // The cursor marker is only drawn while the board actually has the
    // keyboard, so gaining and losing focus has to repaint.
    _keys.addListener(_repaint);
  }

  void _repaint() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _keys.removeListener(_repaint);
    _keys.dispose();
    _editFocus.dispose();
    _editCtrl.dispose();
    super.dispose();
  }

  /// The cursor, forced back inside a board that may have changed under it.
  _CardRef _clamped(List<Map<String, dynamic>> cols) {
    final col = _cursor.col.clamp(0, cols.length - 1);
    return (col: col, card: _cursor.card.clamp(0, _cards(cols[col]).length));
  }

  bool _onCursor(int col, int card) =>
      _keys.hasFocus && _cursor.col == col && _cursor.card == card;

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    // Repeats count. Holding an arrow to run down a long column is how this
    // is actually used, and dropping `KeyRepeatEvent` makes the board feel
    // stuck after the first card — the same trap the list editor documents.
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final cols = _cols();
    if (cols.isEmpty) return KeyEventResult.ignored;
    final hw = HardwareKeyboard.instance;
    if (hw.isAltPressed) return KeyEventResult.ignored;
    final carry = hw.isControlPressed || hw.isMetaPressed;
    final k = e.logicalKey;

    var dx = 0, dy = 0;
    if (k == LogicalKeyboardKey.arrowLeft) {
      dx = -1;
    } else if (k == LogicalKeyboardKey.arrowRight) {
      dx = 1;
    } else if (k == LogicalKeyboardKey.arrowUp) {
      dy = -1;
    } else if (k == LogicalKeyboardKey.arrowDown) {
      dy = 1;
    }
    if (dx != 0 || dy != 0) {
      if (carry) {
        _carry(cols, dx, dy); // _mutate repaints
      } else {
        setState(() => _walk(cols, dx, dy));
      }
      return KeyEventResult.handled;
    }
    if (carry) return KeyEventResult.ignored; // some other chord, not ours
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _openEditorAtCursor(cols);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      return _deleteAtCursor(cols)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  /// Move the cursor. Left/right changes column and keeps the row as close
  /// as the new column allows, so walking across a board of uneven columns
  /// never dumps you back at the top.
  void _walk(List<Map<String, dynamic>> cols, int dx, int dy) {
    final col = (_cursor.col + dx).clamp(0, cols.length - 1);
    final row = _cursor.card + (dx != 0 ? 0 : dy);
    _cursor = (col: col, card: row.clamp(0, _cards(cols[col]).length));
  }

  /// Take the card with you. The whole point of the board's keyboard: a
  /// to-do that cannot be moved from "Doing" to "Done" without a mouse is a
  /// list, not a board.
  void _carry(List<Map<String, dynamic>> cols, int dx, int dy) {
    final from = _clamped(cols);
    final cards = _cards(cols[from.col]);
    if (from.card >= cards.length) return; // the "Add a card" line
    if (dx != 0) {
      final to = (from.col + dx).clamp(0, cols.length - 1);
      if (to == from.col) return;
      final at = from.card.clamp(0, _cards(cols[to]).length);
      _cursor = (col: to, card: at);
      _moveCard(from, to, at);
    } else {
      final to = (from.card + dy).clamp(0, cards.length - 1);
      if (to == from.card) return;
      _cursor = (col: from.col, card: to);
      // _moveCard's index means "insert BEFORE this card", so going down
      // needs one past the slot being landed on.
      _moveCard(from, from.col, dy > 0 ? to + 1 : to);
    }
  }

  void _openEditorAtCursor(List<Map<String, dynamic>> cols) {
    final at = _clamped(cols);
    final cards = _cards(cols[at.col]);
    _commitEditor();
    setState(() {
      _cursor = at;
      if (at.card >= cards.length) {
        _addingTo = at.col;
        _editCtrl.clear();
      } else {
        _editingCard = at;
        _editCtrl.text = cards[at.card];
      }
    });
  }

  /// Delete undoes like everything else here, which is what makes a bare
  /// Delete key defensible: the alternative was Enter, select-all, Delete,
  /// Enter — four steps to do what one key does everywhere else.
  bool _deleteAtCursor(List<Map<String, dynamic>> cols) {
    final at = _clamped(cols);
    if (at.card >= _cards(cols[at.col]).length) return false;
    _cursor = at;
    _mutate((c) {
      final list = _cards(c[at.col])..removeAt(at.card);
      c[at.col]['cards'] = list;
    });
    return true;
  }

  List<Map<String, dynamic>> _cols() {
    final raw = b.content['columns'];
    if (raw is! List) return [];
    return [
      for (final c in raw)
        if (c is Map) c.cast<String, dynamic>()
    ];
  }

  List<String> _cards(Map<String, dynamic> col) =>
      [for (final c in (col['cards'] as List? ?? const [])) '$c'];

  /// One undoable, saved, synced step. Everything the board does funnels
  /// through here so no gesture can mutate without the full paper trail.
  void _mutate(void Function(List<Map<String, dynamic>> cols) fn) {
    final cols = _cols();
    app.pushUndo();
    fn(cols);
    b.content['columns'] = cols;
    app.updateBlock(b);
    setState(() {});
  }

  void _commitEditor() {
    final text = _editCtrl.text.trim();
    final editing = _editingCard;
    final title = _editingTitle;
    final adding = _addingTo;
    setState(() {
      _editingCard = null;
      _editingTitle = null;
      _addingTo = null;
    });
    if (editing != null) {
      _mutate((cols) {
        final cards = _cards(cols[editing.col]);
        if (text.isEmpty) {
          cards.removeAt(editing.card); // emptied = deleted, like a text box
        } else {
          cards[editing.card] = text;
        }
        cols[editing.col]['cards'] = cards;
      });
    } else if (title != null && text.isNotEmpty) {
      _mutate((cols) => cols[title]['title'] = text);
    } else if (adding != null && text.isNotEmpty) {
      _mutate((cols) {
        cols[adding]['cards'] = [..._cards(cols[adding]), text];
      });
    }
  }

  void _moveCard(_CardRef from, int toCol, int toIndex) {
    if (from.col == toCol && (from.card == toIndex || from.card == toIndex - 1)) {
      return; // dropped where it already is
    }
    _mutate((cols) {
      final source = _cards(cols[from.col]);
      final text = source.removeAt(from.card);
      cols[from.col]['cards'] = source;
      final dest = _cards(cols[toCol]);
      var at = toIndex;
      if (from.col == toCol && from.card < toIndex) at--;
      dest.insert(at.clamp(0, dest.length), text);
      cols[toCol]['cards'] = dest;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cols = _cols();
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Normalise before painting: a delete or a drag can leave the cursor
    // pointing past the end, and a marker drawn nowhere is worse than none.
    if (cols.isNotEmpty) _cursor = _clamped(cols);
    // The host decides THAT a block is being edited (Enter on the canvas);
    // the board takes the keyboard when it is — unless an inline text editor
    // wants it instead, which is the one thing that outranks card walking.
    final wantKeys = app.editingBlockId == b.id &&
        _editingCard == null &&
        _editingTitle == null &&
        _addingTo == null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !wantKeys) return;
      if (_keys.context != null && !_keys.hasFocus) _keys.requestFocus();
    });
    return Focus(
      focusNode: _keys,
      onKeyEvent: _onKey,
      child: _board(context, cols, dark),
    );
  }

  Widget _board(
      BuildContext context, List<Map<String, dynamic>> cols, bool dark) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cols.length; i++) ...[
              _column(context, i, cols[i], dark),
              const SizedBox(width: 8),
            ],
            // Small on purpose: adding a column is rare after week one.
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Tooltip(
                message: 'Add a column',
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _mutate((cols) =>
                      cols.add({'title': 'New column', 'cards': <String>[]})),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child:
                        Icon(Icons.add, size: 16, color: OnoteColors.graphite400),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _column(
      BuildContext context, int i, Map<String, dynamic> col, bool dark) {
    final cards = _cards(col);
    final title = '${col['title'] ?? ''}';
    return Container(
      width: 210,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: dark ? OnoteColors.night100 : OnoteColors.paper100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Expanded(
              child: _editingTitle == i
                  ? _inlineEditor()
                  : InkWell(
                      onTap: () {
                        _commitEditor();
                        setState(() {
                          _editingTitle = i;
                          _editCtrl.text = title;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: Text(
                          '$title  ·  ${cards.length}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
            ),
            if (cards.isEmpty && _editingTitle != i)
              Tooltip(
                // Only an EMPTY column offers deletion: the cost of a slip
                // is somebody's task list, and emptying it first is one drag
                // per card.
                message: 'Remove this empty column',
                child: InkWell(
                  onTap: () => _mutate((cols) => cols.removeAt(i)),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close,
                        size: 12, color: OnoteColors.graphite400),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 4),
          for (var j = 0; j < cards.length; j++)
            _dropZone(
              i,
              j,
              child: _editingCard == (col: i, card: j)
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _inlineEditor(),
                    )
                  : _card(context, i, j, cards[j], dark),
            ),
          // The column's tail catches drops below the last card — and IS the
          // whole surface of an empty column.
          _dropZone(i, cards.length,
              child: _addingTo == i
                  ? _inlineEditor()
                  : DecoratedBox(
                      decoration: _onCursor(i, cards.length)
                          ? BoxDecoration(
                              border: Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2),
                              borderRadius: BorderRadius.circular(6))
                          : const BoxDecoration(),
                      child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        _commitEditor();
                        setState(() {
                          _addingTo = i;
                          _editCtrl.clear();
                        });
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          SizedBox(width: 4),
                          Icon(Icons.add,
                              size: 13, color: OnoteColors.graphite400),
                          SizedBox(width: 4),
                          Text('Add a card',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: OnoteColors.graphite400)),
                        ]),
                      ),
                    ))),
        ],
      ),
    );
  }

  /// A target that inserts an incoming card at [index] of column [col],
  /// glowing while a drag hovers so the drop point is never a guess.
  Widget _dropZone(int col, int index, {required Widget child}) {
    return DragTarget<_CardRef>(
      onWillAcceptWithDetails: (d) =>
          !(d.data.col == col && d.data.card == index),
      onAcceptWithDetails: (d) => _moveCard(d.data, col, index),
      builder: (context, candidates, _) => Container(
        decoration: candidates.isEmpty
            ? null
            : BoxDecoration(
                border: Border(
                    top: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2)),
              ),
        child: child,
      ),
    );
  }

  Widget _card(BuildContext context, int col, int idx, String text, bool dark) {
    final card = Material(
      color: dark ? OnoteColors.night0 : OnoteColors.paper0,
      // `shape` rather than `borderRadius` so the keyboard cursor can ride on
      // the same outline — Material forbids both being set at once. The ring
      // is the only way a keyboard user can tell which card they are on.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: _onCursor(col, idx)
            ? BorderSide(
                color: Theme.of(context).colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          _commitEditor();
          setState(() {
            _editingCard = (col: col, card: idx);
            _editCtrl.text = text;
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Text(text, style: const TextStyle(fontSize: 12, height: 1.3)),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Draggable<_CardRef>(
        data: (col: col, card: idx),
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: 198,
            child: Opacity(opacity: .9, child: card),
          ),
        ),
        childWhenDragging: Opacity(opacity: .35, child: card),
        child: card,
      ),
    );
  }

  Widget _inlineEditor() => TextField(
        controller: _editCtrl,
        focusNode: _editFocus,
        autofocus: true,
        maxLines: null,
        style: const TextStyle(fontSize: 12),
        // Wrap-on-selection, same as every other content field.
        inputFormatters: const [
          WrapSelectionFormatter(
              pairs: WrapSelectionFormatter.bracketPairs,
              autoCloseFences: false)
        ],
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _commitEditor(),
        onTapOutside: (_) => _commitEditor(),
      );
}
